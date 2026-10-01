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

    const action = (page, name) => page.evaluate(n => easyplayRtcSmoke.action(n).then(JSON.parse), name);
    const state = page => page.evaluate(() => JSON.parse(easyplayRtcSmoke.state()));
    for (const game of ['go','chess','english','international','brazilian','russian','pool','italian','spanish','turkish']) {
      const invitation = await host.evaluate(g => easyplayRtcSmoke.offer(g), game);
      const response = await guest.evaluate(text => easyplayRtcSmoke.answer(text), invitation);
      await host.evaluate(text => easyplayRtcSmoke.accept(text), response);
      assert.equal((await state(host)).started, false);
      assert.equal((await state(guest)).started, false);
      await action(host, 'start');
      await guest.waitForFunction(() => JSON.parse(easyplayRtcSmoke.state()).started);
      await action(host, 'move');
      await guest.waitForFunction(() => JSON.parse(easyplayRtcSmoke.state()).seq === 1);
      assert.equal((await state(host)).signature, (await state(guest)).signature);
      const resumed = await host.evaluate(() => easyplayRtcSmoke.resume());
      const resumedAnswer = await guest.evaluate(text => easyplayRtcSmoke.answer(text), resumed);
      await host.evaluate(text => easyplayRtcSmoke.accept(text), resumedAnswer);
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
    await Promise.all([host,guest].map(p => p.evaluate(() => easyplayRtcSmoke.lobby('chess'))));
    await host.getByRole('button', {name: '创建邀请', exact: true}).click();
    await host.getByRole('button', {name: '复制邀请信息', exact: true}).click();
    const uiInvite = await host.evaluate(() => navigator.clipboard.readText());
    await guest.getByRole('textbox', {name: '粘贴邀请或回应信息'}).fill(uiInvite);
    await guest.getByRole('button', {name: '导入', exact: true}).click();
    await guest.getByRole('button', {name: '复制回应信息', exact: true}).click();
    const uiResponse = await guest.evaluate(() => navigator.clipboard.readText());
    await host.getByRole('textbox', {name: '粘贴邀请或回应信息'}).fill(uiResponse);
    await host.getByRole('button', {name: '导入', exact: true}).click();
    await guest.getByText('已加入，等待房主开始对局', {exact: true}).waitFor();
    await host.getByRole('button', {name: '开始对局', exact: true}).click();
    await Promise.all([host,guest].map(p => p.getByRole('button', {name: '悔棋', exact: true}).waitFor()));
    console.log('Flutter RTC lobby: create, invite, answer, authenticated wait and manual start passed');
    await Promise.all(contexts.map(c => c.close()));
  } finally {
    await browser?.close();
    await new Promise(resolve => server.close(resolve));
  }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
