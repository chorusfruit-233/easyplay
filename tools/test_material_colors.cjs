// Compare every role across the Java (Android) and bundled JS (Web) algorithms.
const {execFileSync} = require('node:child_process');
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const out = fs.mkdtempSync(path.join(os.tmpdir(), 'easyplay-color-test-'));
const files = dir => fs.readdirSync(dir, {withFileTypes: true}).flatMap(x => x.isDirectory() ? files(path.join(dir,x.name)) : x.name.endsWith('.java') ? [path.join(dir,x.name)] : []);
try {
  execFileSync('javac', ['-d', out, ...files(path.join(root,'android/app/src/main/java/com/easyplay/easyplay/materialcolor')), ...files(path.join(root,'test/theme/java'))], {stdio: 'inherit'});
  require(path.join(root, 'web/material_colors.js'));
  const seeds = [0xff3f51b5, 0xffff9ca8, 0xff42a795];
  for (const style of ['tonalSpot','neutral','vibrant','expressive','rainbow','fruitSalad','monochrome','fidelity','content']) {
    for (const spec of ['spec2021','spec2025']) for (const dark of [false,true]) {
      const java = JSON.parse(execFileSync('java', ['-cp', out, 'MaterialColorsHarness', style, spec, String(dark)], {encoding:'utf8'}));
      const js = JSON.parse(globalThis.easyplayMaterialColors(JSON.stringify({seeds,style,spec,dark})));
      assert.deepEqual(js, java, `${style}/${spec}/${dark}`);
      assert.equal(Object.keys(js[0]).length, 46);
    }
  }
  const scheme = spec => JSON.parse(globalThis.easyplayMaterialColors(JSON.stringify({seeds,style:'tonalSpot',spec,dark:false})))[0];
  assert.notDeepEqual(scheme('spec2021'), scheme('spec2025'));
  console.log('108 schemes: Android/Web roles agree; 2021/2025 produce distinct colors.');
} finally { fs.rmSync(out, {recursive:true,force:true}); }
