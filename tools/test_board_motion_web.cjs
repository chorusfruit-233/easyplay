// Real browser coverage of all production board renderers and reduced motion.
const {chromium} = require('playwright');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../build/board-motion-smoke');
const capture = process.env.CAPTURE_BOARD_MOTION === '1';
(async () => {
  const server = http.createServer((req, res) => {
    const relative = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\/easyplay\//, '');
    const file = path.resolve(root, relative || 'index.html');
    if (!file.startsWith(root + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) { res.writeHead(404); res.end(); return; }
    res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
    res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
    res.setHeader('Content-Type', ({'.html':'text/html','.js':'application/javascript','.wasm':'application/wasm','.json':'application/json'})[path.extname(file)] || 'application/octet-stream');
    fs.createReadStream(file).pipe(res);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let browser;
  try {
    browser = await chromium.launch({headless:true, args:['--no-sandbox'], executablePath:process.env.CHROME_PATH || undefined});
    const page = await (await browser.newContext({viewport:{width:420,height:720}})).newPage();
    const failures=[];
    page.on('pageerror',e=>failures.push(e.message));
    page.on('console',m=>{if(m.type()==='error' && /overflowed|Exception caught/.test(m.text())) failures.push(m.text());});
    await page.goto(`http://127.0.0.1:${server.address().port}/easyplay/`);
    await page.waitForFunction(()=>!!window.easyplayBoardMotion,undefined,{timeout:60000});
    if(capture) await page.evaluate(()=>easyplayBoardMotion.slow(3));
    const state=()=>page.evaluate(()=>JSON.parse(easyplayBoardMotion.state()));
    const change=async game=>{
      await page.evaluate(g=>easyplayBoardMotion.game(g),game);
      await page.waitForFunction(g=>{const s=JSON.parse(easyplayBoardMotion.state());return s.game===g && s.generation===s.renderedGeneration && s.moves===0 && !s.active;},game);
    };
    fs.mkdirSync(path.join(root,'frames'),{recursive:true});
    let frame=0;
    const shot=()=>page.screenshot({path:path.join(root,'frames',`motion-${String(frame++).padStart(4,'0')}.png`)});
    for(const game of ['go','gomoku','chess','xiangqi','draughts']) {
      await change(game);
      if(capture) {await page.waitForLoadState('networkidle');await page.waitForTimeout(3000);await shot();}
      // Record in the page before clicking: a short animation can finish
      // between two browser protocol round trips on a busy CI worker.
      await page.evaluate(()=>{
        const token=window.motionRecording=(window.motionRecording||0)+1;
        window.motionSamples=[];
        const tick=()=>{
          if(token!==window.motionRecording)return;
          window.motionSamples.push(JSON.parse(easyplayBoardMotion.state()));
          requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
      });
      await page.getByRole('button',{name:'演示行棋',exact:true}).click();
      const sample=await page.waitForFunction(()=>window.motionSamples.find(s=>s.moves===1 && s.active && s.frames.some(p=>p.moving)));
      const moving=await sample.jsonValue();await sample.dispose();assert.equal(moving.moves,1);
      assert.equal(moving.frames.filter(p=>p.moving).length,game==='chess'?2:1);
      if(capture) for(let n=0;n<24;n++){await shot();await page.waitForTimeout(35);}
      await page.waitForFunction(()=>!JSON.parse(easyplayBoardMotion.state()).active);
      await page.evaluate(()=>window.motionRecording++);
      const settled=await state();assert.ok(settled.frames.every(p=>!p.moving && !p.departing && p.opacity===1 && p.scale===1));
      if(capture) await page.screenshot({path:path.join(root,`${game}.png`)});
      await page.getByRole('button',{name:'悔棋',exact:true}).click();
      await page.waitForFunction(()=>{const s=JSON.parse(easyplayBoardMotion.state());return s.moves===0 && !s.active;});
      console.log(`PASS ${game}: animation, final board and undo`);
    }
    await change('gomoku');
    await page.evaluate(()=>{easyplayBoardMotion.move();});
    await page.waitForFunction(()=>JSON.parse(easyplayBoardMotion.state()).active);
    await page.evaluate(()=>easyplayBoardMotion.move());
    await page.waitForFunction(()=>JSON.parse(easyplayBoardMotion.state()).moves===2);
    await page.waitForFunction(()=>!JSON.parse(easyplayBoardMotion.state()).active);
    assert.equal((await state()).frames.length,2);
    await page.emulateMedia({reducedMotion:'reduce'});
    await page.waitForFunction(()=>JSON.parse(easyplayBoardMotion.state()).reduced);
    await change('gomoku');
    await page.getByRole('button',{name:'演示行棋',exact:true}).click();
    const reducedSample=await page.waitForFunction(()=>{const s=JSON.parse(easyplayBoardMotion.state());return s.moves===1 && s.frames.length===1 ? s : null;});
    const reduced=await reducedSample.jsonValue();await reducedSample.dispose();assert.equal(reduced.active,false);assert.equal(reduced.frames[0].scale,1);
    assert.deepEqual(failures,[]);
    console.log('PASS fast replies and system reduced motion');
  } finally {await browser?.close();await new Promise(resolve=>server.close(resolve));}
})().catch(error=>{console.error(error);process.exitCode=1;});
