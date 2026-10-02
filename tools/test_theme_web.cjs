const {chromium} = require('playwright');
const fs = require('node:fs'), path = require('node:path'), http = require('node:http');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../build/theme-smoke');
(async () => {
  const server = http.createServer((req,res) => {
    const url = new URL(req.url, 'http://localhost');
    let relative = decodeURIComponent(url.pathname);
    if (!relative.startsWith('/easyplay/')) {res.writeHead(404);res.end();return;}
    relative = relative.slice(10) || 'index.html';
    const file = path.resolve(root,relative);
    if (!file.startsWith(root+path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) {res.writeHead(404);res.end();return;}
    res.setHeader('Cross-Origin-Opener-Policy','same-origin');
    res.setHeader('Cross-Origin-Embedder-Policy','require-corp');
    res.setHeader('Cross-Origin-Resource-Policy','same-origin');
    res.setHeader('Content-Type', {'.html':'text/html','.js':'application/javascript','.wasm':'application/wasm','.json':'application/json'}[path.extname(file)] || 'application/octet-stream');
    fs.createReadStream(file).pipe(res);
  });
  await new Promise(r => server.listen(0,'127.0.0.1',r));
  let browser;
  try {
    browser = await chromium.launch({headless:true,executablePath:process.env.CHROME_PATH || undefined,args:['--no-sandbox']});
    const page = await browser.newPage({viewport:{width:390,height:844}});
    if (process.env.THEME_TEST_FONT) {
      await page.route('https://fonts.gstatic.com/**', route => route.fulfill({status:200,contentType:'font/ttf',headers:{'Access-Control-Allow-Origin':'*','Cross-Origin-Resource-Policy':'cross-origin'},body:fs.readFileSync(process.env.THEME_TEST_FONT)}));
    }
    const errors = [];
    page.on('pageerror',e => errors.push(e.message));
    const url = `http://127.0.0.1:${server.address().port}/easyplay/`;
    await page.goto(url);
    await page.waitForFunction(() => globalThis.easyplayThemeSmoke && JSON.parse(easyplayThemeSmoke.state()).loaded, undefined,{timeout:60000});
    assert.equal(await page.evaluate(() => crossOriginIsolated),true);
    const state = () => page.evaluate(() => JSON.parse(easyplayThemeSmoke.state()));
    const button = label => page.getByRole('button',{name:label,exact:true});
    await button('设置').click({force:true});
    await page.getByRole('button',{name:/主题设置/}).click({force:true});
    await button('AMOLED 纯黑').click({force:true});
    await page.waitForFunction(() => JSON.parse(easyplayThemeSmoke.state()).appearance === 'amoled');
    assert.equal((await state()).darkSurface,0xff000000);
    await button('浅色').click({force:true});
    await page.waitForFunction(() => JSON.parse(easyplayThemeSmoke.state()).appearance === 'light');
    await button('红色').click({force:true});
    await page.waitForFunction(() => JSON.parse(easyplayThemeSmoke.state()).seed === 0xfff44336);
    const modernPrimary = (await state()).lightPrimary;
    await page.getByRole('button',{name:/色彩标准/}).click({force:true});
    const menu = await page.getByRole('menu').boundingBox();
    // Flutter only exposes the selected row during the menu transition.
    // Use the rendered menu's first row so this remains a real pointer action.
    await page.mouse.click(menu.x + menu.width / 2, menu.y + menu.height / 4);
    await page.waitForFunction(p => JSON.parse(easyplayThemeSmoke.state()).lightPrimary !== p,modernPrimary);
    assert.equal((await state()).spec,'spec2021');
    assert.equal((await state()).error,null);
    await page.screenshot({path:'/tmp/easyplay-theme-mobile.png'});
    await page.evaluate(() => easyplayThemeSmoke.scale(1.1));
    await button('深色').click({force:true});
    await page.waitForFunction(() => JSON.parse(easyplayThemeSmoke.state()).appearance === 'dark');
    await page.setViewportSize({width:1280,height:800});
    await page.evaluate(() => easyplayThemeSmoke.scale(1));
    await page.screenshot({path:'/tmp/easyplay-theme-desktop.png'});
    await page.reload();
    await page.waitForFunction(() => globalThis.easyplayThemeSmoke && JSON.parse(easyplayThemeSmoke.state()).loaded);
    assert.equal((await state()).appearance,'dark');
    assert.equal((await state()).seed,0xfff44336);
    assert.equal((await state()).spec,'spec2021');
    assert.deepEqual(errors,[]);
    console.log('Theme Web UI: real 2025/2021 colors, AMOLED, scaled touch, isolated resource and saved preferences passed.');
  } finally {await browser?.close(); await new Promise(r=>server.close(r));}
})().catch(e=>{console.error(e);process.exitCode=1;});
