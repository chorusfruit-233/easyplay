// Smoke the separately built Search ABI and its Eigen fallback in Node.
// Browser WebGPU and real threaded Search still require browser validation.
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const createKata = require('../web/katago-webgpu/kataeval-mt.js');
const module = await createKata();
for (const name of ['_kgeLoad', '_kgeSearchBegin', '_kgePollAll', '_kgeBackendIsGpu']) {
  if (typeof module[name] !== 'function') throw new Error(`Missing ${name}`);
}
const model = readFileSync(new URL('../assets/katago/g170-b6c96-s175395328-d26788732.bin.gz', import.meta.url));
module.FS.writeFile('/b6.bin.gz', new Uint8Array(model));
const loaded = await module.ccall('kgeLoad', 'number', ['string', 'number'], ['/b6.bin.gz', 9], { async: true });
if (!loaded) throw new Error(`b6 load: ${module.ccall('kgeError', 'string', [], [])}`);
if (module.ccall('kgeBackendIsGpu', 'number', [], []) !== 0) {
  throw new Error('Node should use Eigen fallback');
}
// The threaded Search path needs a browser worker. The single-thread binary
// uses the same backend dispatcher and can evaluate the model under Node.
const createEval = require('../web/katago-webgpu/kataeval.js');
const evaluator = await createEval();
evaluator.FS.writeFile('/b6.bin.gz', new Uint8Array(model));
if (!(await evaluator.ccall('kgeLoad', 'number', ['string', 'number'],
  ['/b6.bin.gz', 9], { async: true }))) {
  throw new Error(`single b6 load: ${evaluator.ccall('kgeError', 'string', [], [])}`);
}
if (evaluator.ccall('kgeBackendIsGpu', 'number', [], []) !== 0) {
  throw new Error('Single-thread Node should use Eigen fallback');
}
const stones = evaluator._malloc(81 * 4);
const policy = evaluator._malloc(82 * 4);
const value = evaluator._malloc(5 * 4);
evaluator.HEAP32.fill(0, stones >> 2, (stones >> 2) + 81);
const evaluated = await evaluator.ccall('kgeEval', 'number',
  ['number', 'number', 'number', 'number', 'number', 'number'],
  [stones, 1, 7.5, policy, value, 0], { async: true });
if (!evaluated) throw new Error(`b6 eval: ${evaluator.ccall('kgeError', 'string', [], [])}`);
const numbers = [...evaluator.HEAPF32.subarray(policy >> 2, (policy >> 2) + 82),
  ...evaluator.HEAPF32.subarray(value >> 2, (value >> 2) + 5)];
if (!numbers.every(Number.isFinite)) throw new Error('Non-finite NN output');
console.log('PASS: b6 model, finite NN output, Eigen fallback, Search ABI present');
process.exit(0);
