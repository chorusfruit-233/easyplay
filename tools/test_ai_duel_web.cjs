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
      const count = record => record?.session?.moves?.length ?? record?.moves?.length ?? 0;
      const waitMoves = minimum => page.waitForFunction(({game, minimum}) => {
        const record = window.duelRecords(game)[0];
        return (record?.session?.moves?.length ?? record?.moves?.length ?? 0) >= minimum;
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
      await button('开始观战').click();
      await waitMoves(4);
      await button('暂停').click();
      const paused = count((await records())[0]);
      await page.waitForTimeout(1200);
      assert.equal(count((await records())[0]), paused);
      assert.deepEqual((await records())[0].aiDuel, {blackLevel:'beginner', whiteLevel:'intermediate'});
      await button('单步').click();
      await waitMoves(paused + 1);
      await page.waitForTimeout(1200);
      assert.equal(count((await records())[0]), paused + 1);
      await button('悔棋').click();
      await page.waitForFunction(({game, expected}) => {
        const r = window.duelRecords(game)[0];
        return (r?.session?.moves?.length ?? r?.moves?.length ?? 0) === expected;
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
      assert.deepEqual(failures, []);
      console.log(`PASS ${game}: autoplay, independent levels, pause, step, undo, resume, restart, landscape, exit and persisted records`);
      await context.close();
    }
  } finally {await browser?.close(); await new Promise(resolve => server.close(resolve));}
})().catch(error => {console.error(error); process.exitCode = 1;});
