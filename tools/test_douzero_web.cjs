// Real WASM with native APIs, then with LAN HTTP feature availability simulated.
const {chromium} = require('playwright');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname,'..');
const fixtures = JSON.parse(fs.readFileSync(path.join(root,'test/doudizhu/fixtures/douzero_reference.json'),'utf8')).cases;
const workerSource = fs.readFileSync(path.join(root,'web/douzero/worker.js'),'utf8');
const hash = vm.runInNewContext(workerSource+';sha256;',{
  importScripts(){},ort:{env:{wasm:{}}},URL,self:{location:{href:'http://example.test/douzero/worker.js'}},
});
for (const size of [0,1,55,56,63,64,65,1024,6064183]) {
  const bytes=crypto.randomBytes(size);
  assert.equal(hash(bytes),crypto.createHash('sha256').update(bytes).digest('hex'));
}

(async()=>{
  const server=http.createServer((req,res)=>{
    const url=new URL(req.url,'http://localhost');
    if(!url.searchParams.has('lan')) {
      res.setHeader('Cross-Origin-Opener-Policy','same-origin');res.setHeader('Cross-Origin-Embedder-Policy','require-corp');
    }
    if(url.pathname==='/easyplay/') {res.setHeader('Content-Type','text/html');res.end('<!doctype html><title>DouZero inference</title>');return;}
    const relative=url.pathname.replace(/^\/easyplay\//,'');
    const file=relative.startsWith('assets/assets/douzero/')
      ? path.join(root,relative.replace(/^assets\/assets\//,'assets/'))
      : path.join(root,'web',relative);
    if(!file.startsWith(root+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()) {res.writeHead(404);res.end();return;}
    res.setHeader('Content-Type',({'.js':'application/javascript','.mjs':'application/javascript','.wasm':'application/wasm','.json':'application/json'})[path.extname(file)]||'application/octet-stream');
    fs.createReadStream(file).pipe(res);
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  let browser;
  try {
    browser=await chromium.launch({headless:true,args:['--no-sandbox'],executablePath:process.env.CHROME_PATH||undefined});
    for(const simulatedLan of [false,true]) {
      const host=simulatedLan?'LAN feature simulation':'localhost';
      const context=await browser.newContext();const page=await context.newPage();
      page.on('console',message=>{if(message.type()==='error') console.error(`${host}: ${message.text()}`);});
      page.on('pageerror',error=>console.error(`${host}: ${error.message}`));
      await page.goto(`http://127.0.0.1:${server.address().port}/easyplay/${simulatedLan?'?lan=1':''}`);
      await page.route('**/douzero/worker.js',route=>{
        const prefix=simulatedLan?"Object.defineProperty(self.crypto,'subtle',{value:undefined});Object.defineProperty(self,'isSecureContext',{value:false});\n":'';
        const probe="\nself.postMessage({environment:{secure:isSecureContext,isolated:crossOriginIsolated,subtle:!!self.crypto?.subtle,shared:typeof SharedArrayBuffer!=='undefined'}});";
        return route.fulfill({contentType:'application/javascript',headers:simulatedLan?{}:{'Cross-Origin-Embedder-Policy':'require-corp'},body:prefix+workerSource+probe});
      });
      await page.evaluate(()=>{
        window.startWorker=()=>{
          window.worker?.terminate();
          window.worker=new Worker('douzero/worker.js');
          let id=0;const pending=new Map();
          worker.onmessage=({data})=>{if(data.environment) window.workerEnvironment=data.environment;const entry=pending.get(data.id);if(entry){pending.delete(data.id);clearTimeout(entry.timer);entry.resolve(data);}};
          worker.onerror=event=>{for(const entry of pending.values()){clearTimeout(entry.timer);entry.reject(Error(`Worker failed to load: ${event.message}`));}pending.clear();};
          window.rpc=payload=>new Promise((resolve,reject)=>{
            const current=++id;
            const timer=setTimeout(()=>{pending.delete(current);reject(Error('Worker response timed out'));},20000);
            pending.set(current,{resolve,reject,timer});worker.postMessage({id:current,...payload});
          });
        };
        window.score=async fixture=>{
          const prefix=Array.from(fixture.xPrefix,Number),width=prefix.length+54;
          const x=new Float32Array(fixture.actions.length*width);
          fixture.actions.forEach((action,row)=>{
            x.set(prefix,row*width);const counts=new Uint8Array(15);
            for(const card of action) counts[card<52?Math.floor(card/4):card-39]++;
            for(let rank=0;rank<13;rank++) for(let copy=0;copy<counts[rank];copy++) x[row*width+prefix.length+rank*4+copy]=1;
            x[row*width+prefix.length+52]=counts[13];x[row*width+prefix.length+53]=counts[14];
          });
          const reply=await rpc({role:fixture.role,x,z:Float32Array.from(fixture.z,Number)});
          return reply.error?reply:Array.from(reply.values);
        };
        startWorker();
      });
      for(const fixture of fixtures) {
        const actual=await page.evaluate(f=>score(f),fixture);
        assert.ok(Array.isArray(actual),`${host}: ${JSON.stringify(actual)}`);
        assert.equal(actual.length,fixture.values.length);
        actual.forEach((value,i)=>assert.ok(Math.abs(value-fixture.values[i])<=0.00002,`${host} ${fixture.name} ${i}`));
        assert.equal(actual.indexOf(Math.max(...actual)),fixture.values.indexOf(Math.max(...fixture.values)));
      }
      const environment=await page.evaluate(()=>workerEnvironment);
      assert.equal(environment.secure,!simulatedLan);assert.equal(environment.subtle,!simulatedLan);
      assert.equal(environment.isolated,!simulatedLan);assert.equal(environment.shared,!simulatedLan);
      // Fresh session must reject a corrupted public model, then recover.
      await page.route('**/assets/assets/douzero/landlord.onnx',async route=>{
        const response=await route.fetch();const bytes=await response.body();bytes[0]^=1;
        await route.fulfill({response,body:bytes});
      });
      await page.evaluate(()=>startWorker());
      const rejected=await page.evaluate(f=>score(f),fixtures[0]);
      assert.ok(rejected.error,`${host}: checksum failure must be reported`);
      await page.unroute('**/assets/assets/douzero/landlord.onnx');
      await page.evaluate(()=>startWorker());
      const recovered=await page.evaluate(f=>score(f),fixtures[0]);
      assert.ok(Array.isArray(recovered));
      await page.evaluate(()=>worker.terminate());await context.close();
      console.log(`DOUZERO WASM PASS ${host}: ${fixtures.length} upstream references, checksum rejection and retry; ${JSON.stringify(environment)}`);
    }
  } finally {await browser?.close();await new Promise(resolve=>server.close(resolve));}
})().catch(error=>{console.error(error);process.exitCode=1;});
