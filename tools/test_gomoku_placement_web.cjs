// Exercise default confirmation through the production app and saved records.
const {chromium} = require('playwright');
const fs = require('node:fs'), path = require('node:path'), http = require('node:http');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../build/web');

(async () => {
  const server = http.createServer((req, res) => {
    const relative = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/^\/(?:easyplay\/)?/, '');
    const file = path.resolve(root, relative || 'index.html');
    if (!file.startsWith(root + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {res.writeHead(404); res.end(); return;}
    res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
    res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
    res.setHeader('Content-Type', ({'.html':'text/html', '.js':'application/javascript', '.wasm':'application/wasm', '.json':'application/json'})[path.extname(file)] || 'application/octet-stream');
    fs.createReadStream(file).pipe(res);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let browser;
  try {
    browser = await chromium.launch({headless:true, args:['--no-sandbox'], executablePath:process.env.CHROME_PATH || undefined});
    for (const [variant, label] of [['freestyle','自由五子棋'], ['standard','标准五子棋'], ['renju','连珠禁手']]) {
      for (const ai of [false, true]) {
        const context = await browser.newContext({viewport:variant === 'standard' ? {width:1280,height:720} : {width:420,height:800}});
        const page = await context.newPage(), failures = [];
        let phase = `${variant} ${ai ? 'AI' : 'local'}: start`;
        page.on('pageerror', error => failures.push(error.message));
        page.on('console', message => {if (message.type() === 'error' && /overflowed|Exception caught/.test(message.text())) failures.push(message.text());});
        await page.addInitScript(explicit => {
          if (explicit) localStorage.setItem('flutter.easyplay.go_placement_mode', JSON.stringify('automatic'));
          window.gomokuMoves = () => {
            let value = localStorage.getItem('flutter.easyplay.gomoku.records.v1');
            while (typeof value === 'string') value = JSON.parse(value);
            const record = value?.[0];
            return record?.session?.moves ?? record?.moves ?? null;
          };
        }, ai);
        const moves = () => page.evaluate(() => window.gomokuMoves());
        const button = name => page.getByRole('button', {name, exact:typeof name === 'string'});
        try {
          await page.goto(`http://127.0.0.1:${server.address().port}/easyplay/`);
          await page.locator('flt-semantics-placeholder').waitFor({state:'attached',timeout:60000});
          await page.locator('flt-semantics-placeholder').dispatchEvent('click');
          await button(/^五子棋，/).click();
          if (variant !== 'freestyle') {
            await button(/规则/).click();
            await page.getByRole('menuitem', {name:label,exact:true}).click();
          }
          await button(new RegExp(`^${ai ? '人机对弈' : '本地双人'}`)).click();
          if (ai) await button('开始对局').click();
          // Text spans in Flutter semantics can extend beyond their board.
          const board = page.getByText(`${label}棋盘，15 行 15 列`, {exact:true})
            .locator('xpath=ancestor-or-self::flt-semantics[1]');
          await board.waitFor();
          await page.waitForLoadState('networkidle');
          await page.waitForFunction(() => window.gomokuMoves()?.length === 0);
          // The label is informational; send real pointer input to the board.
          // Wait for its geometry to settle after the route transition.
          const bounds = await board.evaluate(async element => {
            let previous, stable=0;
            for (let frame=0; frame<120; frame++) {
              await new Promise(requestAnimationFrame);
              const {x,y,width,height}=element.getBoundingClientRect();
              const rect={x,y,width,height}, current=JSON.stringify(rect);
              stable=current===previous ? stable+1 : 0;
              if(stable>=6) return rect;
              previous=current;
            }
            throw new Error('board geometry did not settle');
          });
          assert.ok(bounds.width / 15 >= 24, 'cover a board that previously skipped confirmation');
          const click = async (row,col) => {
            const rect=await board.boundingBox();
            await page.mouse.click(rect.x+(col+.5)*rect.width/15,rect.y+(row+.5)*rect.height/15);
          };
          const frame = () => page.evaluate(() => new Promise(requestAnimationFrame).then(() => new Promise(requestAnimationFrame)));
          phase = `${variant} ${ai ? 'AI' : 'local'}: preview and adjust`;
          await click(6,5);
          await frame();
          assert.deepEqual(await moves(), []);
          await click(6,6);
          await frame();
          assert.deepEqual(await moves(), []);
          const currentBounds=await board.boundingBox();
          const x=currentBounds.x+6.5*currentBounds.width/15, y=currentBounds.y+6.5*currentBounds.height/15;
          await page.mouse.move(x,y);
          await page.mouse.down();
          await page.mouse.move(x,y-40,{steps:4});
          await page.mouse.up();
          await click(6,6);
          await frame();
          assert.deepEqual(await moves(), [], 'cancelled preview requires a new confirmation');
          if (process.env.CAPTURE_GOMOKU_PLACEMENT === '1' && variant === 'freestyle' && !ai) {
            await page.waitForLoadState('networkidle');
            await page.waitForTimeout(3000);
            await page.screenshot({path:path.resolve(__dirname,'../docs/images/gomoku-placement-confirmation.png')});
          }
          phase = `${variant} ${ai ? 'AI' : 'local'}: confirm`;
          await click(6,6);
          await page.waitForFunction(() => window.gomokuMoves()?.length >= 1);
          assert.deepEqual((await moves())[0], {row:6,col:6,side:'black'});
          if (ai) {
            await page.waitForFunction(() => window.gomokuMoves()?.length === 2);
            assert.equal((await moves())[1].side, 'white');
          }
          assert.deepEqual(failures, []);
          console.log(`PASS ${variant} ${ai ? 'AI' : 'local'}: default preview, adjust, cancel and confirm${ai ? ', then AI reply' : ''}`);
        } catch (error) {
          console.error(`${phase}: ${error.message}`);
          await page.screenshot({path:`/tmp/easyplay-gomoku-placement-${variant}-${ai ? 'ai' : 'local'}.png`});
          throw error;
        } finally {await context.close();}
      }
    }
  } finally {await browser?.close();await new Promise(resolve => server.close(resolve));}
})().catch(error => {console.error(error);process.exitCode=1;});
