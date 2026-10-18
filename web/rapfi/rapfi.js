/* Rapfi 0.43.01, GPL-3.0-or-later; see assets/rapfi/NOTICE.txt. */
'use strict';
importScripts('rapfi-single-simd128.js');
let engine;
let failed = false;
const queued = [];
const fail = error => {
  failed = true;
  postMessage('ERROR Rapfi: ' + (error && error.message || error));
};
const run = command => {
  try { engine.sendCommand(command); } catch (error) { fail(error); }
};
onmessage = event => {
  if (typeof event.data !== 'string' || failed) return;
  if (event.data.length > 32768) { fail('Protocol command too long'); return; }
  if (engine) run(event.data); else queued.push(event.data);
};
Rapfi({
  locateFile: name => new URL(name, self.location.href).href,
  onReceiveStdout: line => postMessage(line),
  onReceiveStderr: line => postMessage('MESSAGE ' + line),
  onAbort: fail,
}).then(instance => {
  engine = instance;
  for (const command of queued.splice(0)) {
    if (!failed) run(command);
  }
}).catch(fail);
