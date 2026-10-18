// Exercise the release app through real spectator controls and saved records.
const {chromium} = require('playwright');
const fs = require('node:fs'), path = require('node:path'), http = require('node:http');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../build/web');
const capture = process.env.CAPTURE_AI_DUEL === '1';

(async () => {
  const server = http.createServer((req, res) => {
    const relative = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\/(?:easyplay\/)?/, '');
    const file = path.resolve(root, relative || 'index.html');
    if (!file.startsWith(root + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {res.writeHead(404); res.end(); return;}
    res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
    res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
    res.setHeader('Content-Type', ({'.html':'text/html', '.js':'application/javascript', '.wasm':'application/wasm', '.json':'application/json', '.png':'image/png'})[path.extname(file)] || 'application/octet-stream');
    fs.createReadStream(file).pipe(res);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let browser;
  try {
    browser = await chromium.launch({headless:true, args:['--no-sandbox'], executablePath:process.env.CHROME_PATH || undefined});
    for (const [game, label] of [['gomoku', '五子棋'], ['draughts', '跳棋']]) {
      const context = await browser.newContext({viewport:{width:420, height:800}});
      const page = await context.newPage(), failures = [];
      page.on('pageerror', e => failures.push(e.message));
      page.on('console', m => {if (m.type() === 'error' && /overflowed|Exception caught/.test(m.text())) failures.push(m.text());});
      await page.addInitScript(() => {
        window.duelRecords = game => {
          let value = localStorage.getItem(`flutter.easyplay.${game}.records.v1`);
          while (typeof value === 'string') value = JSON.parse(value);
          return value || [];
        };
      });
      const records = () => page.evaluate(g => window.duelRecords(g), game);
      const count = record => game === 'gomoku' ? record?.session?.actions?.length ?? 0 : record?.session?.moves?.length ?? record?.moves?.length ?? 0;
      const waitMoves = minimum => page.waitForFunction(({game, minimum}) => {
        const record = window.duelRecords(game)[0];
        return (game === 'gomoku' ? record?.session?.actions?.length ?? 0 : record?.session?.moves?.length ?? record?.moves?.length ?? 0) >= minimum;
      }, {game, minimum});
      const button = name => page.getByRole('button', {name, exact:typeof name === 'string'});
      const reveal = async locator => {
        for (let n = 0; n < 20 && !await locator.count(); n++) {
          await page.mouse.wheel(0, 350);
          await page.waitForTimeout(150);
        }
        await locator.waitFor();
      };
      await page.goto(`http://127.0.0.1:${server.address().port}/easyplay/`);
      await page.locator('flt-semantics-placeholder').waitFor({state:'attached', timeout:60000});
      await page.locator('flt-semantics-placeholder').dispatchEvent('click');
      await button(new RegExp(`^${label}，`)).click();
      const entry = button(/^AI 对抗/);
      await reveal(entry);
      await entry.click();
      await button(/^黑方 AI 难度/).click();
      await page.getByRole('menuitem', {name:'初级', exact:true}).click();
      await button(/^白方 AI 难度/).click();
      await page.getByRole('menuitem', {name:'高级', exact:true}).click();
      await button('开始观战').click();
      await waitMoves(4);
      await button('暂停').click();
      const paused = count((await records())[0]);
      await page.waitForTimeout(1200);
      assert.equal(count((await records())[0]), paused);
      assert.deepEqual((await records())[0].aiDuel, {blackLevel:'beginner', whiteLevel:'advanced'});
      await button('单步').click();
      await waitMoves(paused + 1);
      await page.waitForTimeout(1200);
      assert.equal(count((await records())[0]), paused + 1);
      await button('悔棋').click();
      await page.waitForFunction(({game, expected}) => {
        const r = window.duelRecords(game)[0];
        return (game === 'gomoku' ? r?.session?.actions?.length ?? 0 : r?.session?.moves?.length ?? r?.moves?.length ?? 0) === expected;
      }, {game, expected:paused});
      await button('继续').click();
      await waitMoves(paused + 2);
      await button('暂停').click();
      await page.waitForTimeout(800);
      if (capture) {
        await page.waitForLoadState('networkidle');
        await page.waitForTimeout(3000);
        await page.screenshot({path:path.resolve(__dirname, `../docs/images/${game}-ai-duel.png`)});
      }
      await page.setViewportSize({width:640, height:360});
      await button('重开').click();
      await button('取消').click();
      await button('继续').waitFor();
      const old = (await records())[0];
      await button('重开').click();
      await button('重新开始').click();
      await page.waitForFunction(game => window.duelRecords(game).length === 2, game);
      assert.equal(count((await records())[0]), 0);
      assert.equal((await records())[1].id, old.id);
      await button('Back').click();
      await page.waitForTimeout(1200);
      assert.equal(count((await records())[0]), 0);
      await page.reload();
      await page.locator('flt-semantics-placeholder').waitFor({state:'attached', timeout:60000});
      await page.locator('flt-semantics-placeholder').dispatchEvent('click');
      assert.equal((await records())[1].id, old.id);
      await button(new RegExp(`^${label}，`)).click();
      const library = button(/^棋谱库/);
      await reveal(library); await library.click();
      if (game === 'draughts') {
        const next = page.waitForEvent('download');
        await button('导出 PDN').nth(1).click();
        const download = await next, stream = await download.createReadStream(), chunks = [];
        for await (const chunk of stream) chunks.push(chunk);
        const pdn = Buffer.concat(chunks).toString('utf8');
        assert.equal(await download.failure(), null);
        assert.match(download.suggestedFilename(), /\.pdn$/);
        assert.match(pdn, /^\[Variant "English"\]/m);
        assert.match(pdn, /^\[GameType "21,B,8,8,N1,0"\]/m);
        assert.match(pdn, /^\[EasyPlayNotationVersion "2"\]/m);
        assert.ok(old.moves.length > 0);
        for (const move of old.moves) {
          const token = move.path.map(c => c[0] * 4 + Math.floor(c[1] / 2) + 1).join(move.captures.length ? 'x' : '-');
          assert.ok(pdn.includes(token), `PDN retains ${token}`);
        }
      }
      await page.setViewportSize({width:420, height:800});
      if (process.env.CAPTURE_RECORD_LIBRARY === '1' && game === 'draughts') {
        await page.waitForTimeout(250);
        await page.screenshot({path:path.resolve(__dirname, '../docs/images/draughts-record-library.png')});
      }
      await button(/^.*AI 对抗 · 黑初级 \/ 白高级/).nth(1).click();
      await button('继续').waitFor();
      const restored = (await records()).find(r => r.id === old.id);
      const restoredCount = count(restored);
      await page.waitForTimeout(1000);
      assert.equal(count((await records()).find(r => r.id === old.id)), restoredCount, 'library restores spectator paused');
      assert.deepEqual(failures, []);
      console.log(`PASS ${game}: autoplay, independent levels, pause, step, undo, resume, restart, landscape, library restore${game === 'draughts' ? ' and PDN download' : ''}`);
      await context.close();
    }
  } finally {await browser?.close(); await new Promise(resolve => server.close(resolve));}
})().catch(error => {console.error(error); process.exitCode = 1;});
