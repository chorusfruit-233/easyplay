/* DouZero-WP local inference. Runtime: ONNX Runtime Web 1.22.0 (MIT).
 * Model/source attribution and hashes: assets/douzero/manifest.json, NOTICE.txt.
 */
'use strict';
importScripts('ort.wasm.min.js');
ort.env.wasm.numThreads = 1; // Also works on LAN HTTP without COOP/COEP.
ort.env.wasm.proxy = false;
ort.env.wasm.wasmPaths = new URL('./', self.location.href).href;
const root = new URL('../', self.location.href);
const sessions = new Map();
let manifest;
let queue = Promise.resolve();

async function sessionFor(role) {
  if (!['landlord', 'landlord_up', 'landlord_down'].includes(role)) throw Error('Invalid role');
  if (sessions.has(role)) return sessions.get(role);
  const load = (async () => {
    manifest ||= fetch(new URL('assets/assets/douzero/manifest.json', root)).then(async r => {
      if (!r.ok) throw Error('Missing DouZero manifest');
      return r.json();
    });
    const info = (await manifest).models[role];
    const response = await fetch(new URL(`assets/assets/douzero/${info.file}`, root));
    if (!response.ok) throw Error('Missing DouZero model');
    const bytes = await response.arrayBuffer();
    // crypto.subtle is unavailable on non-secure LAN HTTP. A small, pinned
    // pure-JS SHA-256 implementation is loaded there instead; no remote CDN.
    const hash = self.crypto?.subtle
      ? Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), b => b.toString(16).padStart(2, '0')).join('')
      : sha256(new Uint8Array(bytes));
    if (bytes.byteLength !== info.bytes || hash !== info.sha256) throw Error('DouZero checksum mismatch');
    return ort.InferenceSession.create(bytes, {
      executionProviders: ['wasm'], graphOptimizationLevel: 'all',
    });
  })();
  sessions.set(role, load);
  try { return await load; }
  catch (error) { sessions.delete(role); manifest = undefined; throw error; }
}

async function score({id, role, x, z}) {
  try {
    const width = role === 'landlord' ? 373 : 484;
    if (!(x instanceof Float32Array) || !(z instanceof Float32Array) ||
        z.length !== 810 || x.length % width || x.length < width || x.length > width * 16384 ||
        x.some(v => !Number.isFinite(v)) || z.some(v => !Number.isFinite(v))) throw Error('Invalid features');
    const session = await sessionFor(role);
    const count = x.length / width;
    const values = new Float32Array(count);
    const history = new ort.Tensor('float32', z, [1, 5, 162]);
    try {
      for (let start = 0; start < count; start += 128) {
        const end = Math.min(count, start + 128);
        const candidates = new ort.Tensor('float32', x.subarray(start * width, end * width), [end - start, width]);
        let output;
        try {
          output = await session.run({z: history, x: candidates});
          if (output.values.data.length !== end - start) throw Error('Invalid output shape');
          values.set(output.values.data, start);
        } finally {
          candidates.dispose();
          if (output) for (const tensor of Object.values(output)) tensor.dispose();
        }
      }
    } finally { history.dispose(); }
    if (values.some(v => !Number.isFinite(v))) throw Error('Non-finite scores');
    self.postMessage({id, values}, [values.buffer]);
  } catch (_) {
    self.postMessage({id, error: 'DouZero model inference failed'});
  }
}

self.onmessage = event => {
  // Serialize hint/AI calls: bounded batches and one thread keep memory stable.
  queue = queue.then(() => score(event.data));
};

// SHA-256 over public model bytes, for ordinary LAN HTTP as well as HTTPS.
function sha256(bytes) {
  const constants = new Uint32Array([
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
  ]);
  const h = new Uint32Array([0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19]);
  const length = Math.ceil((bytes.length + 9) / 64) * 64;
  const padded = new Uint8Array(length);padded.set(bytes);padded[bytes.length] = 128;
  const data = new DataView(padded.buffer);
  data.setUint32(length - 8, Math.floor(bytes.length / 0x20000000));
  data.setUint32(length - 4, bytes.length * 8);
  const w = new Uint32Array(64), r = (x,n) => (x >>> n) | (x << (32-n));
  for (let offset = 0; offset < length; offset += 64) {
    for (let i=0;i<16;i++) w[i] = data.getUint32(offset+i*4);
    for (let i=16;i<64;i++) {
      const a=w[i-15], b=w[i-2];
      w[i] = w[i-16] + (r(a,7)^r(a,18)^(a>>>3)) + w[i-7] + (r(b,17)^r(b,19)^(b>>>10));
    }
    let [a,b,c,d,e,f,g,v] = h;
    for (let i=0;i<64;i++) {
      const t1=(v+(r(e,6)^r(e,11)^r(e,25))+((e&f)^(~e&g))+constants[i]+w[i])|0;
      const t2=((r(a,2)^r(a,13)^r(a,22))+((a&b)^(a&c)^(b&c)))|0;
      v=g;g=f;f=e;e=(d+t1)|0;d=c;c=b;b=a;a=(t1+t2)|0;
    }
    [a,b,c,d,e,f,g,v].forEach((value,i) => {h[i] += value;});
  }
  return Array.from(h,v=>v.toString(16).padStart(8,'0')).join('');
}
