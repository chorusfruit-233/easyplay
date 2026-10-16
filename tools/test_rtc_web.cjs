// Production Dart RTC transport + real Chromium DataChannels, no signal server.
const { chromium } = require('playwright');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../build/rtc-smoke');
(async () => {
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://localhost');
    let relative = decodeURIComponent(url.pathname);
    if (!relative.startsWith('/easyplay/')) { res.writeHead(404); res.end(); return; }
    relative = relative.slice('/easyplay/'.length) || 'index.html';
    const file = path.resolve(root, relative);
    if (!file.startsWith(root + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) { res.writeHead(404); res.end(); return; }
    res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
    res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
    res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
    const type = {'.html': 'text/html', '.js': 'application/javascript', '.wasm': 'application/wasm', '.json': 'application/json'}[path.extname(file)] || 'application/octet-stream';
    res.setHeader('Content-Type', type);
    fs.createReadStream(file).pipe(res);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let browser;
  try {
    browser = await chromium.launch({headless: true, executablePath: process.env.CHROME_PATH || undefined, args: ['--no-sandbox']});
    const contexts = await Promise.all([browser.newContext(), browser.newContext()]);
    // Keep test-only references so late ICE notifications can be exercised
    // deterministically after the room has authenticated the guest.
    await Promise.all(contexts.map(context => context.addInitScript(() => {
      const NativePeer = window.RTCPeerConnection;
      window.__easyplayTestPeers = [];
      window.RTCPeerConnection = new Proxy(NativePeer, {
        construct(target, args) {
          const peer = new target(...args);
          window.__easyplayTestPeers.push(peer);
          return peer;
        },
      });
    })));
    const [host, guest] = await Promise.all(contexts.map(c => c.newPage()));
    const url = `http://127.0.0.1:${server.address().port}/easyplay/`;
    await Promise.all([host.goto(url), guest.goto(url)]);
    await Promise.all([host,guest].map(p => p.waitForFunction(() => !!globalThis.easyplayRtcSmoke, undefined, {timeout: 60000})));
    assert.equal(await host.evaluate(() => crossOriginIsolated), true);
    // Opt-in only: CI must not depend on public STUN availability.
    if (process.env.RTC_STUN_PROBE === '1') {
      for (const [name, urls] of [
        ['domestic-default', ''],
        ['domestic-with-unresponsive-provider', 'stun:stun.miwifi.com:3478\nstun:127.0.0.1:9'],
      ]) {
        const result = await host.evaluate(u => easyplayRtcSmoke.stunProbe(u).then(JSON.parse), urls);
        assert.ok(result.srflx > 0, `${name}: no server-reflexive candidate`);
        console.log(`STUN ${name}: ${JSON.stringify(result)}`);
      }
    }

    let phase = 'initialization';
    for (const [role, page] of [['host', host], ['guest', guest]]) {
      page.on('pageerror', error => console.error(`${phase} ${role}: ${error.message}`));
    }
    const action = (page, name) => page.evaluate(n => easyplayRtcSmoke.action(n).then(JSON.parse).catch(e => { throw new Error(`${n}: ${String(easyplayRtcSmoke.lastError() || e.message)}`); }), name);
    const state = page => page.evaluate(() => JSON.parse(easyplayRtcSmoke.state()));
    const transportGames = process.env.RTC_UI_ONLY === '1' ? [] : ['go','chess','xiangqi','gomoku','gomoku-standard','gomoku-renju','english','international','brazilian','russian','pool','italian','spanish','turkish'];
    for (const game of transportGames) {
      phase = `${game}: handshake`;
      console.log(phase);
      const invitation = await host.evaluate(g => easyplayRtcSmoke.offer(g).catch(e => { throw new Error(`offer: ${String(easyplayRtcSmoke.lastError() || e.message)}`); }), game);
      const response = await guest.evaluate(text => easyplayRtcSmoke.answer(text).catch(e => { throw new Error(`answer: ${String(easyplayRtcSmoke.lastError() || e.message)}`); }), invitation);
      // Stress the open-to-room handoff without masking failures with retries.
      await host.evaluate(text => easyplayRtcSmoke.acceptDelayed(text).catch(e => { throw new Error(`acceptDelayed: ${String(easyplayRtcSmoke.lastError() || e.message)}`); }), response);
      assert.equal((await state(host)).started, false);
      assert.equal((await state(guest)).started, false);
      await action(host, 'start');
      await guest.waitForFunction(() => JSON.parse(easyplayRtcSmoke.state()).started);
      await action(host, 'move');
      await guest.waitForFunction(() => JSON.parse(easyplayRtcSmoke.state()).seq === 1);
      assert.equal((await state(host)).signature, (await state(guest)).signature);
      phase = `${game}: reconnect`;
      console.log(phase);
      const resumed = await host.evaluate(() => easyplayRtcSmoke.resume().catch(e => { throw new Error(`resume: ${String(easyplayRtcSmoke.lastError() || e.message)}`); }));
      const resumedAnswer = await guest.evaluate(text => easyplayRtcSmoke.answer(text).catch(e => { throw new Error(`answer resumed: ${String(easyplayRtcSmoke.lastError() || e.message)}`); }), resumed);
      await host.evaluate(text => easyplayRtcSmoke.accept(text).catch(e => { throw new Error(`accept resumed: ${String(easyplayRtcSmoke.lastError() || e.message)}`); }), resumedAnswer);
      await guest.waitForFunction(() => JSON.parse(easyplayRtcSmoke.state()).seq === 1);
      assert.equal((await state(host)).signature, (await state(guest)).signature);
      await action(host, 'large');
      await guest.waitForFunction(() => JSON.parse(easyplayRtcSmoke.state()).padding === 120000);
      let seq = 1;
      if (game === 'go') {
        await action(guest, 'pass');
        await host.waitForFunction(() => JSON.parse(easyplayRtcSmoke.state()).seq === 2);
        await action(host, 'pass');
        await guest.waitForFunction(() => JSON.parse(easyplayRtcSmoke.state()).seq === 3);
        await action(host, 'score');
        await guest.waitForFunction(() => JSON.parse(easyplayRtcSmoke.state()).seq === 4);
        await action(guest, 'scoreAccept');
        seq = 5;
      } else {
        await action(guest, 'resign');
        seq = 2;
      }
      await host.waitForFunction(n => JSON.parse(easyplayRtcSmoke.state()).seq === n, seq);
      await action(host, 'request');
      await guest.waitForFunction(n => JSON.parse(easyplayRtcSmoke.state()).seq === n, seq + 1);
      await action(guest, 'accept');
      await host.waitForFunction(n => JSON.parse(easyplayRtcSmoke.state()).seq === n, seq + 2);
      assert.equal((await state(host)).signature, (await state(guest)).signature);
      await action(host, 'close');
      console.log(`${game}: real RTC handshake, start, move, authenticated renegotiation, UTF-8 sync, completed game and rematch passed`);
    }
    // Actual Flutter lobby: copy/paste non-trickle messages and manual start.
    await Promise.all(contexts.map(c => c.grantPermissions(['clipboard-read','clipboard-write'])));
    const fillInvitation = async (page, text) => {
      const field = page.getByRole('textbox', {name: '粘贴邀请或回应信息'});
      // Flutter establishes its text input connection after focus. Wait for
      // that frame before sending input, then let the controller receive it.
      await field.click();
      await page.evaluate(() => new Promise(requestAnimationFrame).then(() => new Promise(requestAnimationFrame)));
      await field.fill(text);
      await page.evaluate(() => new Promise(requestAnimationFrame).then(() => new Promise(requestAnimationFrame)));
      assert.ok((await field.inputValue()) === text, 'Flutter text input connection did not retain the invitation');
    };
    const uiGoState = page => page.evaluate(() => JSON.parse(easyplayRtcSmoke.uiGoState()));
    const waitGoPosition = (page, seq, moves) => page.waitForFunction(expected => {
      const view = JSON.parse(easyplayRtcSmoke.uiGoState());
      return view.ready && view.seq === expected.seq && view.moves.length === expected.moves;
    }, {seq, moves});
    const clickGoCell = async (page, row, col) => {
      const view = await uiGoState(page);
      assert.equal(view.ready, true);
      const {x, y, width, height} = view.bounds;
      await page.mouse.click(x + (col + .5) * width / view.size, y + (row + .5) * height / view.size);
    };
    const waitGoPreview = (page, row, col, seq) => page.waitForFunction(expected => {
      const view = JSON.parse(easyplayRtcSmoke.uiGoState());
      return view.ready && view.seq === expected.seq &&
        view.preview?.[0] === expected.row && view.preview?.[1] === expected.col;
    }, {row, col, seq});
    const assertGoSynced = async (moves, seq) => {
      await Promise.all([host, guest].map(page => waitGoPosition(page, seq, moves)));
      const [left, right] = await Promise.all([host, guest].map(uiGoState));
      assert.deepEqual(left.moves, right.moves);
      assert.deepEqual(left.stones, right.stones);
      assert.equal(left.turn, right.turn);
      assert.equal(left.preview, null);
      assert.equal(right.preview, null);
      return left;
    };
    for (const game of ['go', 'chess', 'xiangqi', 'gomoku', 'gomoku-standard', 'gomoku-renju']) {
      phase = `Flutter RTC ${game}: lobby`;
      const isGomoku = game.startsWith('gomoku');
      const wireGame = isGomoku ? 'gomoku' : game;
      const wireVariant = game === 'gomoku-standard' ? 'standard' : game === 'gomoku-renju' ? 'renju' : 'freestyle';
      const label = {freestyle: '自由五子棋', standard: '标准五子棋', renju: '连珠禁手'}[wireVariant];
      const boardLabel = `${label}棋盘，15 行 15 列`;
      try {
        await Promise.all([host,guest].map(p => p.evaluate(g => easyplayRtcSmoke.lobby(g), game)));
        await host.getByRole('button', {name: '创建邀请', exact: true}).click();
        await host.evaluate(() => navigator.clipboard.writeText(''));
        await host.getByRole('button', {name: '复制邀请信息', exact: true}).click();
        await host.waitForFunction(g => navigator.clipboard.readText().then(text => {
          try { const data = JSON.parse(text); return data.game === g.game && (!g.variant || data.variant === g.variant) && data.description?.type === 'offer'; } catch { return false; }
        }), {game: wireGame, variant: isGomoku ? wireVariant : null});
        const uiInvite = await host.evaluate(() => navigator.clipboard.readText());
        await fillInvitation(guest, uiInvite);
        await guest.getByRole('button', {name: '导入', exact: true}).click();
        await guest.evaluate(() => navigator.clipboard.writeText(''));
        await guest.getByRole('button', {name: '复制回应信息', exact: true}).click();
        await guest.waitForFunction(g => navigator.clipboard.readText().then(text => {
          try { const data = JSON.parse(text); return data.game === g.game && (!g.variant || data.variant === g.variant) && data.description?.type === 'answer'; } catch { return false; }
        }), {game: wireGame, variant: isGomoku ? wireVariant : null});
        const uiResponse = await guest.evaluate(() => navigator.clipboard.readText());
        await fillInvitation(host, uiResponse);
        await host.getByRole('button', {name: '导入', exact: true}).click();
        await guest.getByText('已加入，等待房主开始对局', {exact: true}).waitFor();
        await guest.evaluate(async () => {
          window.__easyplayTestPeers.at(-1).dispatchEvent(new Event('connectionstatechange'));
          await new Promise(requestAnimationFrame);
          await new Promise(requestAnimationFrame);
        });
        await guest.getByText('已加入，等待房主开始对局', {exact: true}).waitFor();
        if (isGomoku) {
          assert.equal(await guest.getByText(boardLabel, {exact: true}).count(), 0);
        }
        await host.getByRole('button', {name: '开始对局', exact: true}).click();
        await Promise.all([host,guest].map(p => p.getByRole('button', {name: isGomoku || game === 'go' ? '请求悔棋' : '悔棋', exact: true}).waitFor()));
        if (game === 'go') {
          phase = 'Flutter RTC go: double-tap confirmation';
          const initial = await assertGoSynced(0, 0);
          assert.equal(initial.side, 'black');
          assert.equal((await uiGoState(guest)).side, 'white');
          for (const page of [host, guest]) {
            assert.equal((await uiGoState(page)).placementMode, 'doubleTap');
          }
          const center = Math.floor(initial.size / 2);
          await clickGoCell(host, center, center);
          await waitGoPreview(host, center, center, 0);
          // The first click changes only the mounted board's preview. Neither
          // peer has a committed move or an incremented authority sequence.
          for (const page of [host, guest]) {
            const view = await uiGoState(page);
            assert.equal(view.seq, 0);
            assert.deepEqual(view.moves, []);
            assert.deepEqual(view.stones, []);
          }
          if (process.env.CAPTURE_RTC_GO === '1') {
            const screenshot = path.resolve(__dirname, '../docs/images/go-lan-confirmation.png');
            fs.mkdirSync(path.dirname(screenshot), {recursive: true});
            await host.screenshot({path: screenshot, fullPage: true});
          }
          await clickGoCell(host, center, center);
          const blackMove = await assertGoSynced(1, 1);
          assert.deepEqual(blackMove.stones, [{cell: [center, center], side: 'black'}]);

          await clickGoCell(guest, center, center + 1);
          await waitGoPreview(guest, center, center + 1, 1);
          assert.equal((await uiGoState(host)).seq, 1);
          assert.equal((await uiGoState(host)).moves.length, 1);
          assert.equal((await uiGoState(guest)).moves.length, 1);
          await clickGoCell(guest, center, center + 1);
          const whiteMove = await assertGoSynced(2, 2);
          assert.deepEqual(whiteMove.stones, [
            {cell: [center, center], side: 'black'},
            {cell: [center, center + 1], side: 'white'},
          ]);

          phase = 'Flutter RTC go: negotiated undo';
          await guest.getByRole('button', {name: '请求悔棋', exact: true}).click();
          await host.getByText('对手请求悔棋', {exact: true}).waitFor();
          await host.getByRole('button', {name: '同意', exact: true}).click();
          const undone = await assertGoSynced(1, 4);
          assert.deepEqual(undone.stones, blackMove.stones);
          assert.equal(undone.turn, 'white');
          console.log('Flutter RTC go board: first-click preview, two-click confirmation, remote reply and negotiated undo passed');
        }
        if (isGomoku) {
          await Promise.all([host,guest].map(p => p.getByText(boardLabel, {exact: true}).waitFor()));
          await Promise.all([host,guest].map(p => p.getByText(`15×15 · ${label} · 0 手`, {exact: false}).first().waitFor()));
        }
        console.log(`Flutter RTC ${game} lobby: create, invite, answer, authenticated wait and manual start passed`);
      } catch (error) {
        for (const [name, page] of [['host', host], ['guest', guest]]) {
          const status = await page.locator('flt-semantics').evaluateAll(nodes => nodes.filter(n => !n.querySelector('flt-semantics')).map(n => n.getAttribute('aria-label') || n.textContent || '').filter(text => text.length < 300 && /FormatException|StateError|失败|已加入|等待|连接|人数/.test(text)));
          console.error(`${game} ${name}: ${JSON.stringify(status)}`);
          await page.screenshot({path: `/tmp/easyplay-rtc-${game}-${name}.png`});
        }
        throw error;
      }
    }
    await Promise.all(contexts.map(c => c.close()));
  } finally {
    await browser?.close();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
