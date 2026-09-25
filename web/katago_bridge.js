let worker;
const pending = new Map();
let requestQueue = Promise.resolve();

function getWorker() {
  if (worker) return worker;
  worker = new Worker(new URL('./katago_worker.js', import.meta.url), {
    type: 'module',
  });
  worker.onmessage = ({ data }) => {
    const callbacks = pending.get(data.id);
    if (!callbacks) return;
    pending.delete(data.id);
    worker?.terminate();
    worker = undefined;
    if (data.error) callbacks.reject(new Error(data.error));
    else callbacks.resolve(data.vertex ?? data.adjudication);
  };
  worker.onerror = (event) => {
    const errorDetails = {};
    if (event.error) {
      for (const key of Object.getOwnPropertyNames(event.error)) {
        try { errorDetails[key] = String(event.error[key]); } catch (_) {}
      }
    }
    const detail = JSON.stringify({
      message: event.message,
      filename: event.filename,
      line: event.lineno,
      column: event.colno,
      error: errorDetails,
    });
    const error = new Error(detail);
    for (const { reject } of pending.values()) reject(error);
    pending.clear();
    worker.terminate();
    worker = undefined;
  };
  return worker;
}

globalThis.easyPlayKataGoGenmove = (json) => {
  const payload = JSON.parse(json);
  const result = requestQueue.catch(() => {}).then(() => new Promise((resolve, reject) => {
    pending.set(payload.id, { resolve, reject });
    getWorker().postMessage(payload);
  }));
  requestQueue = result;
  return result;
};

globalThis.easyPlayKataGoAdjudicate = (json) => {
  const payload = JSON.parse(json);
  payload.mode = 'adjudicate';
  const result = requestQueue.catch(() => {}).then(() => new Promise((resolve, reject) => {
    pending.set(payload.id, { resolve, reject });
    getWorker().postMessage(payload);
  }));
  requestQueue = result;
  return result;
};
