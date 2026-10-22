// Real library entry points and shared playback widgets in a release Web build.
'use strict';
const {chromium}=require('playwright');
const http=require('node:http'), fs=require('node:fs'), path=require('node:path');
const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../build/playback-smoke');
(async()=>{
  const server=http.createServer((req,res)=>{
    const relative=decodeURIComponent(new URL(req.url,'http://localhost').pathname).replace(/^\/easyplay\//,'');
    const file=path.resolve(root,relative||'index.html');
    if(!file.startsWith(root+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404);res.end();return;}
    res.setHeader('Cross-Origin-Opener-Policy','same-origin');
    res.setHeader('Cross-Origin-Embedder-Policy','require-corp');
    res.setHeader('Content-Type',({'.html':'text/html','.js':'application/javascript','.wasm':'application/wasm','.json':'application/json'})[path.extname(file)]||'application/octet-stream');
    fs.createReadStream(file).pipe(res);
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  let browser,lastPage;
  try {
    browser=await chromium.launch({headless:true,args:['--no-sandbox'],executablePath:process.env.CHROME_PATH||undefined});
    for(const [game,label,length] of [['go','围棋',3],['gomoku','五子棋',12],['draughts','跳棋',12]]) {
      console.log(`Record playback: ${game}`);
      const context=await browser.newContext({viewport:{width:390,height:844}});
      const page=await context.newPage(),errors=[];
      lastPage=page;
      page.setDefaultTimeout(30000);
      page.on('pageerror',e=>errors.push(e.message));
      page.on('console',m=>{if(m.type()==='error'&&/overflowed|Exception caught/.test(m.text()))errors.push(m.text());});
      const button=name=>page.getByRole('button',{name,exact:typeof name==='string'});
      const scroll=async delta=>{const v=page.viewportSize();await page.mouse.move(v.width-8,v.height-50);await page.mouse.wheel(0,delta);await page.waitForTimeout(120);};
      const click=async locator=>{
        await scroll(-10000);
        for(let n=0;n<24;n++) {
          const r=await locator.count()?await locator.boundingBox():null,v=page.viewportSize();
          if(r&&r.y>5&&r.y+r.height<v.height-4){await page.mouse.click(r.x+r.width/2,r.y+r.height/2);await page.waitForTimeout(100);return;}
          await scroll(220);
        }
        throw Error(`Cannot show ${locator}`);
      };
      const state=()=>page.evaluate(()=>JSON.parse(easyplayPlaybackSmoke.state()));
      const stored=()=>page.evaluate(async()=>{
        const s=JSON.parse(await easyplayPlaybackSmoke.storage());
        return Object.fromEntries(Object.entries(s).filter(([key])=>key==='easyplay.go_records'||/easyplay\.(gomoku|draughts)\.records\.v1/.test(key)));
      });
      await page.goto(`http://127.0.0.1:${server.address().port}/easyplay/`);
      await page.waitForFunction(()=>!!window.easyplayPlaybackSmoke,undefined,{timeout:60000});
      await click(button(new RegExp(`^${label}，`)));
      if(game==='go') {await page.getByRole('tab',{name:'棋谱库',exact:true}).click();}
      else {await click(button(/^棋谱库/));}
      await page.waitForTimeout(400);
      await page.screenshot({path:path.join(root,`${game}-library.png`)});
      const original=await stored();
      await click(button('播放棋谱').first());
      await page.waitForFunction(()=>JSON.parse(easyplayPlaybackSmoke.state()).progress?.startsWith('0 /'));
      assert.equal((await state()).playing,false);
      await click(button('下一步'));
      assert.ok((await state()).progress.startsWith('1 /'));
      await click(button('播放棋谱'));
      await page.waitForFunction(()=>JSON.parse(easyplayPlaybackSmoke.state()).progress.startsWith('2 /'));
      await click(button('暂停播放'));
      const paused=(await state()).progress;
      await page.waitForTimeout(1300);
      assert.equal((await state()).progress,paused);
      await click(button('回到开局'));
      const speed=page.getByRole('button',{name:'1×',exact:true});
      await click(speed);
      await page.getByRole('menuitem',{name:'2×',exact:true}).click();
      await page.waitForTimeout(350);
      await click(button('跳到末尾'));
      assert.ok((await state()).progress.startsWith(`${length} / ${length}`));
      if(game==='gomoku') {
        const end=(await state()).session;
        assert.equal(end.actions.length,12);assert.equal(end.moves.length,5);assert.equal(end.gameOver,true);
        await click(button('上一步'));
        assert.equal((await state()).session.gameOver,false);
        for(let i=0;i<3;i++)await click(button('上一步'));
        assert.equal((await state()).session.moves.length,4);
      }
      if(game==='go') {
        await click(button('主线'));
        await page.getByRole('menuitem',{name:'变化 1',exact:true}).click();
        await page.waitForTimeout(350);
        assert.ok((await state()).progress.startsWith('0 / 2'));
        await click(button('跳到末尾'));
        await page.getByText('另一条变化',{exact:true}).waitFor();
      }
      await page.waitForTimeout(1500);
      await page.screenshot({path:path.join(root,`${game}-playback.png`)});
      await page.setViewportSize({width:844,height:390});await page.waitForTimeout(250);
      await page.screenshot({path:path.join(root,`${game}-playback-landscape.png`)});
      assert.deepEqual(await stored(),original,'Playback cannot rewrite saved records');
      const back=await button('Back').boundingBox();
      await page.mouse.click(back.x+back.width/2,back.y+back.height/2);
      await page.waitForFunction(()=>!JSON.parse(easyplayPlaybackSmoke.state()).progress);
      await page.waitForTimeout(1200);
      assert.deepEqual(await stored(),original,'Leaving playback cannot save or launch a game');
      assert.deepEqual(errors,[]);
      await context.close();
    }
    console.log('RECORD PLAYBACK WEB PASS: all three libraries, automatic/manual playback, pause, speed, SGF variation, Soosyrv-8 actions, portrait/landscape and unchanged storage');
  } catch(error) {
    if(lastPage&&!lastPage.isClosed()) {
      await lastPage.screenshot({path:path.join(root,'failure.png')});
      console.error(await lastPage.locator('body').ariaSnapshot());
    }
    throw error;
  } finally {await browser?.close();await new Promise(resolve=>server.close(resolve));}
})().catch(error=>{console.error(error);process.exitCode=1;});
