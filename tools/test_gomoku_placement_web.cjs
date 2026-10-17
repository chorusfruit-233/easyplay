// Real production UI: competitive opening, confirmation, AI roles and records.
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
    res.setHeader('Content-Type', ({'.html':'text/html', '.js':'application/javascript', '.wasm':'application/wasm', '.json':'application/json', '.png':'image/png'})[path.extname(file)] || 'application/octet-stream');
    fs.createReadStream(file).pipe(res);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let browser;
  try {
    browser = await chromium.launch({headless:true, args:['--no-sandbox'], executablePath:process.env.CHROME_PATH || undefined});
    for (const scenario of [
      {name:'local keep colours phone', exchange:false, width:420},
      {name:'local exchange desktop', exchange:true, width:1280},
      {name:'AI opening black', ai:true, human:'black', width:420},
      {name:'AI opening white then exchange', ai:true, human:'white', exchange:true, width:1280},
    ]) {
      const context = await browser.newContext({viewport:{width:scenario.width, height:scenario.width===420 ? 800 : 720}});
      const page = await context.newPage(), failures = [];
      let phase = 'home';
      page.on('pageerror', error => failures.push(error.message));
      page.on('console', m => {if (m.type()==='error' && /overflowed|Exception caught/.test(m.text())) failures.push(m.text());});
      await page.addInitScript(explicit => {
        if (explicit) localStorage.setItem('flutter.easyplay.go_placement_mode', JSON.stringify('automatic'));
        window.gomokuSession = () => {
          let records = localStorage.getItem('flutter.easyplay.gomoku.records.v1');
          while (typeof records === 'string') records = JSON.parse(records);
          return records?.[0]?.session ?? null;
        };
      }, !!scenario.ai);
      const state = () => page.evaluate(() => window.gomokuSession());
      const button = name => page.getByRole('button', {name, exact:typeof name==='string'});
      const reveal = async target => {
        for (let i=0; i<20 && !await target.count(); i++) {
          await page.mouse.wheel(0,300);
          await page.waitForTimeout(100);
        }
        await target.waitFor();
      };
      const waitCount = (field, count) => page.waitForFunction(({field,count}) => window.gomokuSession()?.[field]?.length===count, {field,count});
      try {
        await page.goto(`http://127.0.0.1:${server.address().port}/easyplay/`);
        await page.locator('flt-semantics-placeholder').waitFor({state:'attached',timeout:60000});
        await page.locator('flt-semantics-placeholder').dispatchEvent('click');
        await button(/^五子棋，/).click();
        assert.equal(await button(/规则，/).count(), 0);
        assert.equal(await page.getByText('自由五子棋', {exact:true}).count(),0);
        assert.equal(await page.getByText('标准五子棋', {exact:true}).count(),0);
        await button(new RegExp(`^${scenario.ai ? '人机对弈' : '本地双人'}`)).click();
        if (scenario.ai) {
          if (scenario.human==='white') {
            await button(/^开局执棋方/).click();
            await page.getByRole('menuitem',{name:'白方',exact:true}).click();
          }
          await button('开始对局').click();
        }
        const board = page.getByText('竞技连珠棋盘，15 行 15 列', {exact:true}).locator('xpath=ancestor-or-self::flt-semantics[1]');
        await board.waitFor();
        await page.waitForLoadState('networkidle');
        await page.waitForFunction(() => !!window.gomokuSession());
        const frame = () => page.evaluate(() => new Promise(requestAnimationFrame).then(() => new Promise(requestAnimationFrame)));
        const click = async (row,col) => {
          await frame();
          const rect=await board.boundingBox();
          await page.mouse.click(rect.x+(col+.5)*rect.width/15, rect.y+(row+.5)*rect.height/15);
        };
        const confirm = async (row,col) => {
          const before=await state();
          await click(row,col);
          await frame();
          assert.deepEqual(await state(),before,'preview must not save or start AI');
          await click(row,col);
          await page.waitForFunction(n => window.gomokuSession()?.actions?.length>=n,before.actions.length+1);
        };
        if (!scenario.ai || scenario.human==='black') {
          phase='default preview, adjust and cancel';
          await waitCount('moves',0);
          await click(6,5);
          await click(7,7);
          assert.deepEqual((await state()).moves,[]);
          const rect=await board.boundingBox(), x=rect.x+rect.width/2, y=rect.y+rect.height/2;
          await page.mouse.move(x,y); await page.mouse.down();
          await page.mouse.move(x,y-40,{steps:4}); await page.mouse.up();
          await confirm(7,7);
          await confirm(6,7);
          await confirm(6,6);
        } else {
          phase='AI sets the three-stone opening';
          await waitCount('moves',3);
        }
        phase='three-move exchange';
        if (!scenario.ai || scenario.human==='white') {
          await reveal(button(scenario.exchange ? '交换执棋' : '不交换'));
          await button(scenario.exchange ? '交换执棋' : '不交换').click();
        }
        await page.waitForFunction(() => window.gomokuSession()?.actions?.length>=4);
        let current=await state();
        const exchanged=current.actions[3].exchange;
        const humanWhite=scenario.ai && (scenario.human==='white')!==exchanged;
        if (!scenario.ai || humanWhite) {
          phase='white fourth move';
          await confirm(8,8);
        }
        await waitCount('moves',4);
        phase='two fifth-move proposals';
        if (!scenario.ai || !humanWhite) {
          // AI's fourth move is free, so choose unoccupied, non-equivalent points.
          current=await state();
          const occupied=new Set(current.moves.map(m=>`${m.row},${m.col}`));
          let added=0;
          for (const [r,c] of [[8,7],[7,8],[9,8],[8,9],[5,6],[9,5]]) {
            if (occupied.has(`${r},${c}`)) continue;
            const n=(await state()).actions.length;
            await click(r,c); await frame();
            assert.equal((await state()).actions.length,n);
            await click(r,c); await frame();
            await page.waitForTimeout(100);
            if ((await state()).actions.length>n) added++;
            if (added===2) break;
          }
          assert.equal(added,2);
        }
        await page.waitForFunction(() => window.gomokuSession()?.actions?.length>=7);
        if (!scenario.ai || humanWhite) {
          current=await state();
          assert.equal(current.moves.length,4,'proposals must not be committed moves');
          const proposal=current.actions[5];
          if (process.env.CAPTURE_GOMOKU_PLACEMENT==='1' && !scenario.ai && scenario.width===420) {
            await page.screenshot({path:path.resolve(__dirname,'../docs/images/gomoku-professional-opening.png')});
          }
          phase='white chooses the fifth and places the sixth';
          await confirm(proposal.row,proposal.col);
          current=await state();
          const rejected=current.actions[6];
          assert.equal(current.moves[4].row,proposal.row);
          assert.equal(current.moves[4].col,proposal.col);
          assert.equal(current.moves[4].side,'black');
          await confirm(rejected.row,rejected.col);
        }
        await page.waitForFunction(() => window.gomokuSession()?.moves?.length>=6);
        current=await state();
        assert.equal(current.variant,'professional');
        assert.equal(current.version,3);
        assert.deepEqual(current.moves.slice(0,3).map(m=>m.side),['black','white','black']);
        assert.equal(current.actions[3].player,'white');
        assert.equal(current.actions[4].player,exchanged ? 'black' : 'white');
        assert.equal(current.actions[5].player,exchanged ? 'white' : 'black');
        assert.equal(current.actions[6].player,current.actions[5].player);
        assert.equal(current.actions[7].player,exchanged ? 'black' : 'white');
        assert.equal(current.actions[8].player,current.actions[7].player);
        assert.deepEqual(current.moves.slice(3,6).map(m=>m.side),['white','black','white']);
        if (!scenario.ai) {
          phase='resume competitive record';
          const saved=current;
          await button('Back').click();
          const record=button(/^竞技连珠 · 6 手/);
          await reveal(record); await record.click();
          await board.waitFor();
          assert.deepEqual(await state(),saved);
        }
        assert.deepEqual(failures,[]);
        console.log(`PASS ${scenario.name}: confirmed opening, exchange, two proposals, selection, W6${scenario.ai ? ' and AI identities' : ' and resume'}`);
      } catch (error) {
        console.error(`${scenario.name} / ${phase}: ${error.message}`);
        await page.screenshot({path:`/tmp/easyplay-professional-${scenario.name.replaceAll(' ','-')}.png`});
        throw error;
      } finally {await context.close();}
    }
  } finally {await browser?.close(); await new Promise(resolve => server.close(resolve));}
})().catch(error => {console.error(error);process.exitCode=1;});
