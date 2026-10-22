// Real production widgets and two independent RtcPeer/DataChannel clients.
'use strict';
const {chromium} = require('playwright');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../build/battleship-smoke');
(async () => {
  const server = http.createServer((req,res) => {
    const relative = decodeURIComponent(new URL(req.url,'http://localhost').pathname).replace(/^\/easyplay\//,'');
    const file = path.resolve(root, relative || 'index.html');
    if (!file.startsWith(root+path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {res.writeHead(404);res.end();return;}
    res.setHeader('Cross-Origin-Opener-Policy','same-origin');
    res.setHeader('Cross-Origin-Embedder-Policy','require-corp');
    res.setHeader('Content-Type',({'.html':'text/html','.js':'application/javascript','.mjs':'application/javascript','.wasm':'application/wasm','.json':'application/json'})[path.extname(file)] || 'application/octet-stream');
    fs.createReadStream(file).pipe(res);
  });
  await new Promise(resolve => server.listen(0,'127.0.0.1',resolve));
  let browser;
  let pages=[];
  try {
    browser = await chromium.launch({headless:true,args:['--no-sandbox'],executablePath:process.env.CHROME_PATH || undefined});
    pages = await Promise.all([0,1].map(async () => (await browser.newContext({viewport:{width:390,height:844}})).newPage()));
    const errors=[];
    for (const [i,p] of pages.entries()) {
      p.setDefaultTimeout(30000);
      p.on('pageerror',e=>errors.push(`page ${i}: ${e.message}`));
      p.on('console',m=>{if(m.type()==='error' && /overflowed|Exception caught/.test(m.text())) errors.push(m.text());});
      await p.addInitScript(() => {
        const send=RTCDataChannel.prototype.send;
        const dropped=new WeakSet();
        window.__battleshipDroppedHello=0;
        RTCDataChannel.prototype.send=function(raw) {
          if(this.protocol==='easyplay-hello-v1' && !dropped.has(this) && typeof raw==='string') {
            try {
              const frame=JSON.parse(raw);
              if(frame.total===1) {
                const message=JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(frame.data),c=>c.charCodeAt(0))));
                if(message.type==='battleship' && message.action==='hello') {
                  dropped.add(this);window.__battleshipDroppedHello++;return;
                }
              }
            } catch (_) { /* Other traffic remains unchanged. */ }
          }
          return send.call(this,raw);
        };
      });
    }
    const url=`http://127.0.0.1:${server.address().port}/easyplay/`;
    await Promise.all(pages.map(async p=>{await p.goto(url);await p.waitForFunction(()=>!!window.easyplayBattleshipSmoke,undefined,{timeout:60000});}));
    const state=p=>p.evaluate(()=>JSON.parse(easyplayBattleshipSmoke.state()));
    const frame=p=>p.evaluate(()=>new Promise(requestAnimationFrame).then(()=>new Promise(requestAnimationFrame)));
    const scroll=async(p,delta)=>{const v=p.viewportSize();await p.mouse.move(v.width-8,v.height-55);await p.mouse.wheel(0,delta);await frame(p);};
    const box=async(p,key)=>p.evaluate(k=>JSON.parse(easyplayBattleshipSmoke.rect(k)),key);
    const clickKey=async(p,key)=>{
      for(let n=0;n<20;n++) {
        const r=await box(p,key),v=p.viewportSize();
        if(r && r.width>0 && r.height>0 && r.y>=65 && r.y+r.height<=v.height-5) {
          await p.mouse.click(r.x+r.width/2,r.y+r.height/2);await frame(p);return;
        }
        await scroll(p,r && r.y<65?-260:260);
      }
      throw Error(`Cannot bring ${key} into view`);
    };
    const clickLocator=async(p,locator)=>{
      await scroll(p,-10000);
      for(let n=0;n<20;n++) {
        const r=await locator.count()?await locator.boundingBox():null,v=p.viewportSize();
        if(r && r.y>=5 && r.y+r.height<=v.height-5) {await locator.click();await frame(p);return;}
        await scroll(p,260);
      }
      throw Error('Cannot bring home entry into view');
    };
    const p=pages[0];
    console.log('Battleship home: seventh game and production section');
    await p.evaluate(()=>easyplayBattleshipSmoke.home());
    await clickLocator(p,p.getByRole('button',{name:/^海战棋，/}));
    await p.getByText('先布阵，再侦察',{exact:true}).waitFor();
    await p.getByText(/^单人对战/).waitFor();
    await p.getByText(/^同机双人/).waitFor();
    await p.screenshot({path:path.join(root,'home.png')});

    console.log('Local AI: manual placement, edge validation, confirmation and resume');
    await p.evaluate(()=>easyplayBattleshipSmoke.local(false));await frame(p);
    await clickKey(p,'battleship-own-cell-0');
    assert.equal((await state(p)).view.ownFleet.length,0,'Preview must not commit a ship');
    await clickKey(p,'battleship-place');
    assert.equal((await state(p)).view.ownFleet.length,1);
    await clickKey(p,'battleship-own-cell-15');
    assert.equal(await p.getByRole('button',{name:'放置战列舰',exact:true}).isDisabled(),true,'Ships cannot touch even diagonally');
    await clickKey(p,'battleship-own-cell-9');
    assert.equal(await p.getByRole('button',{name:'放置战列舰',exact:true}).isDisabled(),true,'Horizontal ship cannot wrap around an edge');
    await clickKey(p,'battleship-rotate');
    await clickKey(p,'battleship-place');
    const manual=(await state(p)).view.ownFleet.find(s=>s.ship==='battleship');
    assert.equal(manual.start,9);assert.equal(manual.direction,'vertical');
    await clickKey(p,'battleship-randomize');
    assert.equal((await state(p)).view.ownFleet.length,5);
    await scroll(p,-10000);await p.waitForTimeout(1500);await p.screenshot({path:path.join(root,'placement-portrait.png')});
    await clickKey(p,'battleship-ready');
    assert.equal((await state(p)).view.phase,'playing');
    assert.deepEqual((await state(p)).view.enemyFleet,[]);
    await clickKey(p,'battleship-target-cell-0');
    assert.equal((await state(p)).view.shots.length,0,'Selecting a target must require confirmation');
    await clickKey(p,'battleship-fire');
    await p.evaluate(()=>easyplayBattleshipSmoke.active(false));
    assert.equal((await state(p)).view.shots.length,1);
    await p.waitForTimeout(2100);
    assert.equal((await state(p)).view.shots.length,1,'Backgrounding must pause the pending AI shot');
    await p.evaluate(()=>easyplayBattleshipSmoke.active(true));
    await p.waitForFunction(()=>JSON.parse(easyplayBattleshipSmoke.state()).view.shots.length===2);
    assert.equal((await state(p)).error,null);
    assert.equal((await state(p)).visibleFleets.target,0);
    await scroll(p,-10000);await p.screenshot({path:path.join(root,'battle-portrait.png')});
    await p.setViewportSize({width:844,height:390});await frame(p);await scroll(p,-10000);
    await p.screenshot({path:path.join(root,'battle-landscape.png')});
    await p.getByRole('button',{name:'开火记录',exact:true}).click();
    await p.getByText('开火记录 · 2 次',{exact:true}).waitFor();
    await p.getByRole('button',{name:'关闭开火记录',exact:true}).click();
    await p.getByRole('button',{name:'认输',exact:true}).click();
    await clickKey(p,'battleship-confirm-resign');
    assert.equal((await state(p)).view.phase,'finished');
    assert.equal((await state(p)).visibleFleets.target,5,'Finished games reveal both fleets');
    await clickKey(p,'battleship-rematch');
    assert.equal((await state(p)).view.phase,'placement');
    assert.equal((await state(p)).view.ownFleet.length,0);

    console.log('Hotseat: private grids disappear at every handoff');
    await p.setViewportSize({width:390,height:844});
    await p.evaluate(()=>easyplayBattleshipSmoke.local(true));await frame(p);
    for(let seat=0;seat<2;seat++) {
      assert.equal((await state(p)).covered,true);
      assert.equal((await state(p)).view,null);
      assert.deepEqual((await state(p)).visibleFleets,{});
      await clickKey(p,'battleship-reveal');
      assert.equal((await state(p)).view.seat,seat);
      await clickKey(p,'battleship-randomize');
      await clickKey(p,'battleship-ready');
    }
    assert.equal((await state(p)).covered,true);
    assert.deepEqual((await state(p)).visibleFleets,{});
    await clickKey(p,'battleship-reveal');
    await clickKey(p,'battleship-target-cell-0');await clickKey(p,'battleship-fire');
    assert.equal((await state(p)).covered,true);
    assert.deepEqual((await state(p)).visibleFleets,{});
    await clickKey(p,'battleship-reveal');
    assert.equal((await state(p)).view.seat,1);
    assert.deepEqual((await state(p)).view.enemyFleet,[]);
    await Promise.all(pages.map(p=>p.evaluate(()=>easyplayBattleshipSmoke.close())));

    console.log('Real RTC: private fleets, reliable HELLO and reconnect');
    const connect=async()=>{
      const invite=await pages[0].evaluate(()=>easyplayBattleshipSmoke.offer());
      const parsed=JSON.parse(invite);assert.equal(parsed.game,'battleship');
      assert.ok(!('fleet' in parsed) && !('view' in parsed));
      const answer=await pages[1].evaluate(i=>easyplayBattleshipSmoke.answer(i),invite);
      await pages[0].evaluate(a=>easyplayBattleshipSmoke.accept(a),answer);
      await Promise.all(pages.map(p=>p.waitForFunction(()=>JSON.parse(easyplayBattleshipSmoke.state()).connected)));
    };
    const synced=async()=>{
      const s=await state(pages[0]);
      await Promise.all(pages.map(p=>p.waitForFunction(seq=>JSON.parse(easyplayBattleshipSmoke.state()).seq===seq,s.seq)));
      await Promise.all(pages.map(frame));
    };
    const action=async(p,name,payload={})=>{await p.evaluate(([n,d])=>easyplayBattleshipSmoke.action(n,JSON.stringify(d)),[name,payload]);await synced();};
    const privacy=async()=>{
      for(const [i,p] of pages.entries()) {
        const current=await state(p);assert.equal(current.view.seat,i);
        const wire=await p.evaluate(()=>JSON.parse(easyplayBattleshipSmoke.wire()));
        for(const raw of wire) {
          const message=JSON.parse(raw);if(message.action!=='snapshot') continue;
          assert.equal(message.type,'battleship');assert.equal(message.payload.view.seat,i);
          assert.equal(message.protocolVersion,1);assert.equal(message.rulesVersion,2);
          assert.deepEqual(Object.keys(message.payload).sort(),['roomId','started','round','view','seats','rematch'].sort());
          assert.deepEqual(Object.keys(message.payload.view).sort(),['seat','phase','turn','winner','ready','ownFleet','enemyFleet','shots'].sort());
          if(message.payload.view.phase!=='finished') assert.deepEqual(message.payload.view.enemyFleet,[],'No opponent fleet may be serialized during play');
        }
      }
    };
    await connect();await synced();
    await action(pages[0],'start');
    for(const p of pages) {await action(p,'randomize');await action(p,'ready');}
    await Promise.all(pages.map(p=>p.evaluate(()=>easyplayBattleshipSmoke.mount())));await synced();
    await privacy();
    await clickKey(pages[0],'battleship-target-cell-0');
    assert.equal((await state(pages[0])).view.shots.length,0);
    await clickKey(pages[0],'battleship-fire');await synced();
    const before=(await state(pages[1])).view;
    for(let n=0;n<2;n++) {
      await pages[1].evaluate(()=>easyplayBattleshipSmoke.disconnect());
      await pages[0].waitForFunction(()=>!JSON.parse(easyplayBattleshipSmoke.state()).seats[1].connected);
      await connect();await synced();
      assert.deepEqual((await state(pages[1])).view,before,'Reconnect restores only the same private fleet and public history');
    }
    assert.ok(await pages[1].evaluate(()=>window.__battleshipDroppedHello>0));
    let checkedHalo=false;
    for(let n=0;n<200;n++) {
      const s=await state(pages[0]);if(s.view.phase==='finished') break;
      const shooter=pages[s.view.turn],current=await state(shooter);
      const fired=new Set(current.view.shots.filter(shot=>shot.attacker===current.view.seat).map(shot=>shot.cell));
      const halo=current.excludedCells.find(cell=>!fired.has(cell));
      if(!checkedHalo && halo!==undefined) {
        console.log('Sunk ship: inferred water is visible, untargetable and does not add shots');
        const sunk=current.view.shots.filter(shot=>shot.attacker===current.view.seat && shot.outcome==='sunk');
        assert.ok(sunk.length>0);
        const expected=new Set();
        for(const shot of sunk) {
          const hull=new Set(shot.sunkCells);
          for(const cell of hull) for(let dr=-1;dr<=1;dr++) for(let dc=-1;dc<=1;dc++) {
            const row=Math.floor(cell/10)+dr,column=cell%10+dc,target=row*10+column;
            if(row>=0 && row<10 && column>=0 && column<10 && !hull.has(target)) expected.add(target);
          }
        }
        assert.deepEqual([...current.excludedCells].sort((a,b)=>a-b),[...expected].sort((a,b)=>a-b));
        const coordinate=String.fromCharCode(65+Math.floor(halo/10))+(halo%10+1);
        await clickKey(shooter,`battleship-target-cell-${halo}`);
        assert.equal(await shooter.getByRole('button',{name:`敌方海域 ${coordinate} 已排除，击沉周边`,exact:true}).isDisabled(),true);
        assert.equal(await shooter.getByRole('button',{name:'确认开火',exact:true}).isDisabled(),true);
        assert.deepEqual((await state(shooter)).view,current.view,'Tapping inferred water cannot change history, turn or private view');
        assert.deepEqual((await state(shooter)).view.enemyFleet,[],'Only the sunk hull is public');
        await scroll(shooter,-10000);await shooter.screenshot({path:path.join(root,'battle-portrait.png')});
        await shooter.setViewportSize({width:844,height:390});await frame(shooter);await scroll(shooter,-10000);
        await shooter.screenshot({path:path.join(root,'battle-landscape.png')});
        await shooter.setViewportSize({width:390,height:844});await frame(shooter);
        checkedHalo=true;
      }
      await action(shooter,'auto');
    }
    assert.equal(checkedHalo,true,'A full match must exercise automatic sunk-ship exclusion');
    await privacy();
    for(const p of pages) {
      const s=await state(p);assert.equal(s.view.phase,'finished');
      assert.equal(s.view.enemyFleet.length,5);assert.equal(s.visibleFleets.target,5);
    }
    await Promise.all(pages.map(p=>clickKey(p,'battleship-rematch')));await synced();
    for(const p of pages) {
      const s=await state(p);assert.equal(s.view.phase,'placement');assert.equal(s.view.turn,1);
      assert.deepEqual(s.view.shots,[]);assert.deepEqual(s.view.ownFleet,[]);assert.deepEqual(s.view.enemyFleet,[]);
    }
    await privacy();
    assert.deepEqual(errors,[]);
    console.log('BATTLESHIP WEB PASS: home, separated manual/random fleets, confirmed fire, sunk-ship exclusion, private handoff, AI resume, two real RTC views, reconnect, complete game and rematch');
  } catch(error) {
    await Promise.all(pages.map((p,i)=>p.screenshot({path:path.join(root,`failure-${i}.png`)}).catch(()=>{})));
    throw error;
  } finally {await browser?.close();await new Promise(resolve=>server.close(resolve));}
})().catch(error=>{console.error(error);process.exitCode=1;});
