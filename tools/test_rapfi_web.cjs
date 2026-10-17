// Real browser Worker smoke: no COOP/COEP headers and a nested Pages-like URL.
const { chromium } = require('playwright');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../web');
(async () => {
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    if (url.pathname === '/easyplay/') {
      res.setHeader('Content-Type', 'text/html');
      res.end('<!doctype html><base href="/easyplay/"><title>Rapfi Worker smoke</title>');
      return;
    }
    const name = path.basename(url.pathname);
    if (!['rapfi.js', 'rapfi-single-simd128.js', 'rapfi-single-simd128.wasm', 'rapfi-single-simd128.data'].includes(name)) {
      res.writeHead(404); res.end(); return;
    }
    res.setHeader('Content-Type', name.endsWith('.wasm') ? 'application/wasm' : 'text/javascript');
    fs.createReadStream(path.join(root, 'rapfi', name)).pipe(res);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let browser;
  try {
    browser = await chromium.launch({ headless: true, executablePath: process.env.CHROME_PATH || undefined, args: ['--no-sandbox'] });
    const page = await browser.newPage();
    await page.goto(`http://127.0.0.1:${server.address().port}/easyplay/`);
    const result = await page.evaluate(async () => {
      if (crossOriginIsolated) throw Error('Test must run without isolation');
      const outcomes = [];
      for (let i = 0; i < 2; i++) {
        const worker = new Worker(new URL('rapfi/rapfi.js', document.baseURI));
        const waiting = [];
        worker.onmessage = event => {
          for (const waiter of [...waiting]) {
            if (waiter.match.test(event.data)) {
              waiting.splice(waiting.indexOf(waiter), 1);
              clearTimeout(waiter.timeout);
              waiter.resolve(event.data);
            }
          }
        };
        const answer = (command, match) => new Promise((resolve, reject) => {
          const timeout = setTimeout(() => reject(Error(`Timed out: ${command}`)), 120000);
          waiting.push({ match, resolve, timeout });
          worker.postMessage(command);
        });
        worker.onerror = event => { throw Error(event.message); };
        await answer('START 15', /^OK$/);
        worker.postMessage('INFO RULE 4');
        worker.postMessage('INFO MAX_MEMORY 33554432');
        worker.postMessage('INFO TIMEOUT_TURN 150');
        worker.postMessage('INFO STRENGTH 100');
        worker.postMessage('YXBOARD\n7,7,2\n7,8,1\n8,8,2\nDONE');
        const best = await answer('YXNBEST 8', /^\d+,\d+$/);
        const move = best;
        if (!/^\d+,\d+$/.test(move)) throw Error(`Invalid Renju move: ${move}`);
        // Restrict the root to an actual black immediate win.
        worker.postMessage('YXBOARD\n3,7,1\n0,0,2\n4,7,1\n2,0,2\n5,7,1\n4,0,2\n6,7,1\n6,0,2\nDONE');
        const winning = await answer('YXNBEST 1', /^\d+,\d+$/);
        if (!['2,7', '7,7'].includes(winning)) throw Error('Missed immediate win: ' + winning);
        let ticks = 0;
        const timer = setInterval(() => ticks++, 10);
        worker.postMessage('INFO TIMEOUT_TURN 2000');
        worker.postMessage('YXBOARD\n7,7,2\n7,8,1\n8,8,2\nDONE');
        worker.postMessage('YXNBEST 8');
        await new Promise(resolve => setTimeout(resolve, 200));
        clearInterval(timer);
        if (ticks < 5) throw Error(`UI froze: ${ticks} ticks`);
        worker.terminate();
        outcomes.push({ move, ticks, terminated: true });
      }
      return outcomes;
    });
    console.log('PASS Rapfi browser Worker:', JSON.stringify(result));
  } finally {
    if (browser) await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
