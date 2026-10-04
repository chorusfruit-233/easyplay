// GPL-3.0-or-later. Official Pikafish in one cooperative Web Worker.
// Worker scheduling and Asyncify keep stop responsive without SharedArrayBuffer.
'use strict';
const commands = [];
self.Module = {
  easyplayCommands: commands,
  easyplayStop: false,
  print: line => postMessage(line),
  printErr: line => postMessage(`info string ${line}`),
  locateFile: name => new URL(name, self.location.href).href,
  onAbort: reason => postMessage(`info string CRITICAL ERROR Pikafish WASM: ${reason}`),
};
self.onmessage = event => {
  if (typeof event.data !== 'string' || /[\r\n]/.test(event.data) || event.data.length >= 131000) return;
  if (event.data === 'stop' || event.data === 'quit') Module.easyplayStop = true;
  commands.push(event.data);
};
(async () => {
  const response = await fetch(new URL('pikafish.nnue', self.location.href));
  if (!response.ok) throw Error(`NNUE HTTP ${response.status}`);
  const weights = new Uint8Array(await response.arrayBuffer());
  if (crypto.subtle) {
  const digest = await crypto.subtle.digest('SHA-256', weights);
  const actual = Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join('');
  if (actual !== '7d13d73569a9b571ba0eb20cf1596247bc2a42738967e61afef6482b231e900e') throw Error('NNUE checksum mismatch');
  }
  Module.preRun = [() => Module.FS.writeFile('/pikafish.nnue', weights)];
  importScripts(new URL('pikafish-core.js', self.location.href).href);
})().catch(error => postMessage(`info string CRITICAL ERROR Pikafish initialization: ${error.message}`));
