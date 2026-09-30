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
      res.end('<!doctype html><base href="/easyplay/"><title>Stockfish Worker smoke</title>');
      return;
    }
    const name = path.basename(url.pathname);
    if (!['stockfish-19-lite-single.js', 'stockfish-19-lite-single.wasm'].includes(name)) {
      res.writeHead(404); res.end(); return;
    }
    res.setHeader('Content-Type', name.endsWith('.wasm') ? 'application/wasm' : 'text/javascript');
    fs.createReadStream(path.join(root, 'stockfish', name)).pipe(res);
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
        const worker = new Worker(new URL('stockfish/stockfish-19-lite-single.js', document.baseURI));
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
          const timeout = setTimeout(() => reject(Error(`Timed out: ${command}`)), 20000);
          waiting.push({ match, resolve, timeout });
          worker.postMessage(command);
        });
        worker.onerror = event => { throw Error(event.message); };
        await answer('uci', /^uciok$/);
        worker.postMessage('setoption name Hash value 16');
        await answer('isready', /^readyok$/);
        worker.postMessage('ucinewgame');
        worker.postMessage('position fen rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
        const best = await answer('go movetime 150', /^bestmove [a-h][1-8][a-h][1-8][qrbn]?/);
        const move = best.split(' ')[1];
        if (!/^(?:[a-h]2[a-h][34]|[bg]1[acfh]3)$/.test(move)) throw Error(`Illegal initial move: ${move}`);
        let ticks = 0;
        const timer = setInterval(() => ticks++, 10);
        const stopped = answer('go infinite', /^bestmove /);
        await new Promise(resolve => setTimeout(resolve, 200));
        worker.postMessage('stop');
        await stopped;
        clearInterval(timer);
        if (ticks < 5) throw Error(`UI froze: ${ticks} ticks`);
        await answer('isready', /^readyok$/);
        worker.terminate();
        outcomes.push({ move, ticks, terminated: true });
      }
      return outcomes;
    });
    console.log('PASS Stockfish 19 browser Worker:', JSON.stringify(result));
  } finally {
    if (browser) await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
