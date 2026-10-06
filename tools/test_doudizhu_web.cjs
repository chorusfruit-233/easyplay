// Three independent browser contexts, actual production RtcPeer/DataChannels.
const {chromium} = require('playwright');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../build/doudizhu-smoke');
(async () => {
  const server = http.createServer((req,res) => {
    const relative = decodeURIComponent(new URL(req.url,'http://localhost').pathname).replace(/^\/easyplay\//,'');
    const file = path.resolve(root,relative || 'index.html');
    if(!file.startsWith(root+path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {res.writeHead(404);res.end();return;}
    res.setHeader('Cross-Origin-Opener-Policy','same-origin');res.setHeader('Cross-Origin-Embedder-Policy','require-corp');
    res.setHeader('Content-Type',({'.html':'text/html','.js':'application/javascript','.wasm':'application/wasm','.json':'application/json'})[path.extname(file)] || 'application/octet-stream');
    fs.createReadStream(file).pipe(res);
  });
  await new Promise(r => server.listen(0,'127.0.0.1',r));
  let browser;
  try {
    browser = await chromium.launch({headless:true,args:['--no-sandbox'],executablePath:process.env.CHROME_PATH || undefined});
    const pages = await Promise.all([0,1,2].map(async () => (await browser.newContext({viewport:{width:390,height:844}})).newPage()));
    const failures=[];
    pages.forEach((p,i) => { p.on('pageerror',e => failures.push(`page ${i}: ${e.message}`));p.on('console',m => {if(m.type()==='error' && /overflowed|Exception caught/.test(m.text())) failures.push(m.text());}); });
    const url = `http://127.0.0.1:${server.address().port}/easyplay/`;
    await Promise.all(pages.map(async p => {await p.goto(url);await p.waitForFunction(() => !!window.easyplayDoudizhuSmoke,undefined,{timeout:60000});}));
    const state = p => p.evaluate(() => JSON.parse(easyplayDoudizhuSmoke.state()));
    const action = (p,name) => p.evaluate(n => easyplayDoudizhuSmoke.action(n),name);
    const connect = async (seat,ai=false) => {
      const offer=await pages[0].evaluate(([s,a]) => easyplayDoudizhuSmoke.offer(s,a),[seat,ai]);
      const signal=JSON.parse(offer);assert.equal(signal.seat,seat);assert.equal(signal.game,'doudizhu');
      assert.deepEqual(Object.keys(signal).sort(),['createdAt','formatVersion','game','protocolVersion','roomId','rulesVersion','sdp','seat','sessionId','token','type'].sort());
      const answer=await pages[seat].evaluate(o => easyplayDoudizhuSmoke.answer(o),offer);
      await pages[0].evaluate(a => easyplayDoudizhuSmoke.accept(a),answer);
      try { await pages[seat].waitForFunction(() => JSON.parse(easyplayDoudizhuSmoke.state()).connected); }
      catch (e) { const info = await pages[seat].evaluate(() => {const s=JSON.parse(easyplayDoudizhuSmoke.state());return {connected:s.connected,error:s.error,seq:s.seq};});console.error(`Guest ${seat}: ${JSON.stringify(info)}`);throw e; }
    };
    const synced = async (active=pages) => {
      const s=await state(pages[0]);
      await Promise.all(active.map(p => p.waitForFunction(seq => JSON.parse(easyplayDoudizhuSmoke.state()).seq===seq,s.seq)));
    };
    const privacy = async (active=pages) => {
      const states=await Promise.all(active.map(state));
      for(let i=0;i<states.length;i++) {
        const v=states[i].view;assert.equal(v.seat,i);
        assert.deepEqual(v.public.history.flatMap(p=>p.cards),v.public.played);
        assert.deepEqual(v.public.history,states[0].view.public.history);
        for(let j=0;j<states.length;j++) if(i!==j) {
          const publicIds=new Set([...v.public.bottom,...v.public.played]);
          assert.ok(v.hand.every(id => publicIds.has(id) || !states[j].view.hand.includes(id)));
        }
        const wire=await active[i].evaluate(() => JSON.parse(easyplayDoudizhuSmoke.wire()));
        for(const raw of wire) {
          const m=JSON.parse(raw);if(m.action !== 'snapshot') continue;assert.equal(m.payload.view.seat,i);
          assert.deepEqual(Object.keys(m.payload).sort(),['roomId','view','seats','rematch'].sort());
          assert.deepEqual(Object.keys(m.payload.view).sort(),['hand','public','seat']);
          if(m.payload.view.public.phase==='bidding') assert.deepEqual(m.payload.view.public.bottom,[]);
          assert.ok(!('events' in m.payload) && !('seed' in m.payload));
        }
      }
    };
    if (process.env.DDZ_UI_ONLY !== '1') {
    console.log('Three players: connect two independent peers');
    await connect(1);await connect(2);await pages[0].waitForFunction(() => JSON.parse(easyplayDoudizhuSmoke.state()).seats.every(s=>s.ready));await synced();
    await action(pages[0],'start');await synced();await privacy();
    const dealt=await Promise.all(pages.map(state));assert.deepEqual(dealt.map(s=>s.view.hand.length),[17,17,17]);
    assert.equal(new Set(dealt.flatMap(s=>s.view.hand)).size,51);
    await action(pages[0],'bid');await synced();await action(pages[0],'play');await synced();await privacy();
    console.log('Reconnect guest 1 while guest 2 stays alive');
    const before=await state(pages[1]);await pages[1].evaluate(() => easyplayDoudizhuSmoke.disconnect());
    await pages[0].waitForFunction(() => !JSON.parse(easyplayDoudizhuSmoke.state()).seats[1].connected);
    await connect(1);await synced();assert.deepEqual((await state(pages[1])).view.hand,before.view.hand);
    assert.deepEqual((await state(pages[1])).view.public.history,before.view.public.history);
    assert.equal((await state(pages[2])).connected,true);await privacy();
    for(let n=0;n<400;n++) {
      const s=await state(pages[0]);if(s.view.public.phase==='finished') break;
      await action(pages[s.view.public.turn],'auto');await synced();
    }
    assert.equal((await state(pages[0])).view.public.phase,'finished');await privacy();
    for(const p of pages) {await action(p,'rematch');await synced();}
    assert.equal((await state(pages[0])).view.public.phase,'bidding');
    assert.deepEqual((await state(pages[0])).view.public.history,[]);
    await pages[0].evaluate(() => easyplayDoudizhuSmoke.mount());await pages[0].waitForTimeout(300);
    await pages[0].screenshot({path:'build/doudizhu-smoke/portrait.png'});
    await pages[0].setViewportSize({width:568,height:320});await pages[0].waitForTimeout(300);
    await pages[0].screenshot({path:'build/doudizhu-smoke/landscape.png'});
    await Promise.all(pages.map(p => p.evaluate(() => easyplayDoudizhuSmoke.close())));
    console.log('Two humans + host AI: complete a second game');
    await connect(1,true);await pages[0].waitForFunction(() => JSON.parse(easyplayDoudizhuSmoke.state()).seats.every(s=>s.ready));await synced(pages.slice(0,2));
    await action(pages[0],'start');await synced(pages.slice(0,2));await action(pages[0],'bid');
    for(let n=0;n<400;n++) {
      await pages[0].waitForFunction(() => {const s=JSON.parse(easyplayDoudizhuSmoke.state());return s.view.public.turn!==2 || s.view.public.phase==='finished';});
      await synced(pages.slice(0,2));const s=await state(pages[0]);if(s.view.public.phase==='finished') break;
      await action(pages[s.view.public.turn],'auto');
    }
    assert.equal((await state(pages[0])).view.public.phase,'finished');await privacy(pages.slice(0,2));
    await Promise.all(pages.map(p => p.evaluate(() => easyplayDoudizhuSmoke.close())));
    }
    console.log('Actual Flutter lobby: two invites, two answers, manual start and selected card');
    await Promise.all(pages.map(async p => {
      await p.setViewportSize({width:390,height:844});
      await p.context().grantPermissions(['clipboard-read','clipboard-write']);
      await p.evaluate(() => easyplayDoudizhuSmoke.lobby());
      await p.waitForTimeout(400);
      await p.getByRole('button', {name:/国内 STUN/}).press('Enter');
      await p.getByRole('menuitem', {name:'同网连接（关闭 STUN）',exact:true}).click();
    }));
    await pages[0].getByRole('button',{name:'创建三人房间',exact:true}).click();
    const fill = async (p,label,text) => {
      const field=p.getByRole('textbox',{name:label});await field.click();
      await p.evaluate(() => new Promise(requestAnimationFrame).then(() => new Promise(requestAnimationFrame)));
      await field.fill(text);
      await p.evaluate(() => new Promise(requestAnimationFrame).then(() => new Promise(requestAnimationFrame)));
    };
    const scroll = async (p, delta) => { await p.mouse.move(382,760); await p.mouse.wheel(0,delta); await p.evaluate(() => new Promise(requestAnimationFrame).then(() => new Promise(requestAnimationFrame))); };
    for (const seat of [1,2]) {
      await scroll(pages[0], -1600);
      if(seat===2) {
        await pages[0].getByRole('button',{name:'玩家 2',exact:true}).press('Enter');
        await pages[0].getByRole('menuitem',{name:'玩家 3',exact:true}).click();
      }
      await pages[0].getByRole('button',{name:'为此座位生成邀请 / 重连邀请',exact:true}).click();
      await pages[0].getByRole('button',{name:'复制邀请，发给对应玩家',exact:true}).click();
      await pages[0].waitForFunction(s => navigator.clipboard.readText().then(t => {try {const x=JSON.parse(t);return x.type==='offer' && x.seat===s;}catch{return false;}}),seat);
      const invite=await pages[0].evaluate(() => navigator.clipboard.readText());
      await fill(pages[seat],'粘贴房主邀请（重连须为原座位）',invite);
      await pages[seat].getByRole('button',{name:'加入 / 重连并生成回应',exact:true}).click();
      await pages[seat].getByRole('button',{name:'复制回应，发给房主',exact:true}).click();
      await pages[seat].waitForFunction(s => navigator.clipboard.readText().then(t => {try {const x=JSON.parse(t);return x.type==='answer' && x.seat===s;}catch{return false;}}),seat);
      const answer=await pages[seat].evaluate(() => navigator.clipboard.readText());
      await fill(pages[0],'粘贴对应座位的回应',answer);
      await pages[0].getByRole('button',{name:'接收回应',exact:true}).click();
      await scroll(pages[seat], 650);
      await pages[seat].getByText(/已连接 · 已准备/).last().waitFor();
    }
    await scroll(pages[0], 1400);
    await pages[0].getByRole('button',{name:'三人准备后开始',exact:true}).click();
    await Promise.all(pages.map((p,i) => p.getByText(`玩家 ${i+1} · 17 张`,{exact:true}).waitFor()));
    await pages[0].getByRole('button',{name:'叫 3 分',exact:true}).click();
    await pages[0].getByText('玩家 1 · 地主 · 20 张',{exact:true}).waitFor();
    await pages[0].getByRole('button',{name:/[♠♥♣♦]/}).first().click();
    await pages[0].getByRole('button',{name:'出牌',exact:true}).click();
    await pages[0].getByText('玩家 1 · 地主 · 19 张',{exact:true}).waitFor();
    for (const p of pages) {
      await p.getByRole('button',{name:'历史出牌',exact:true}).click();
      await p.getByText('1 · 玩家 1 · 地主 · 单牌',{exact:false}).waitFor();
    }
    for (const [i,p] of pages.entries()) {
      if(i===0) continue;
      await p.getByRole('button',{name:'关闭历史出牌',exact:true}).click();
      await p.getByRole('button',{name:'不要',exact:true}).click();
      await pages[0].getByText(`${i+1} · 玩家 ${i+1} · 农民 · 不要`,{exact:true}).waitFor();
    }
    await pages[0].screenshot({path:'build/doudizhu-smoke/history-portrait.png'});
    await pages[0].setViewportSize({width:568,height:320});
    await pages[0].waitForTimeout(300);
    await pages[0].screenshot({path:'build/doudizhu-smoke/history-landscape.png'});
    assert.deepEqual(failures,[]);console.log('DOUDIZHU RTC PASS: private deal, public plays, reconnect, rematch, mixed AI, responsive UI, real lobby controls');
  } finally {await browser?.close();await new Promise(r=>server.close(r));}
})().catch(e=>{console.error(e);process.exitCode=1;});
