import createKataGo from './katago/katago.js';

const modelName = 'g170-b6c96-s175395328-d26788732.bin.gz';

function setConfigValue(config, key, value) {
  const expression = new RegExp(`^#?\\s*${key}\\s*=.*$`, 'm');
  if (expression.test(config)) return config.replace(expression, `${key} = ${value}`);
  return `${config}\n${key} = ${value}\n`;
}

function parseConfigLines(text) {
  const values = [];
  for (const line of String(text ?? '').split(/\r?\n/)) {
    const match = line.trim().match(/^([A-Za-z][A-Za-z0-9]*)\s*=\s*(.*)$/);
    if (match) values.push([match[1], match[2]]);
  }
  return values;
}

async function loadModelBytes(data, field, fallbackUrl) {
  if (data[field]) {
    const binary = atob(data[field]);
    return Uint8Array.from(binary, (character) => character.charCodeAt(0));
  }
  if (!fallbackUrl) return null;
  const response = await fetch(new URL(fallbackUrl, self.location.href));
  if (!response.ok) {
    throw new Error(`KataGo model request failed: HTTP ${response.status}`);
  }
  return new Uint8Array(await response.arrayBuffer());
}

self.onmessage = async ({ data }) => {
  let module;
  const output = [];
  const diagnostics = [];
  try {
    if (!self.crossOriginIsolated || typeof SharedArrayBuffer === 'undefined') {
      throw new Error('KataGo Web requires COOP/COEP response headers for WebAssembly threads.');
    }
    const modelBytes = await loadModelBytes(
      data,
      'modelBase64',
      `assets/assets/katago/${modelName}`,
    );
    const humanModelBytes = await loadModelBytes(data, 'humanModelBase64', null);
    if (data.backend === 'tflite') throw new Error('静态 Web 不支持 TFLite 模型');
    let configText = data.configText;
    if (typeof configText !== 'string') {
    const configResponse = await fetch(
      new URL('assets/assets/katago/gtp_example.cfg', self.location.href),
    );
    if (!configResponse.ok) {
      throw new Error(`KataGo config request failed: HTTP ${configResponse.status}`);
    }
    configText = await configResponse.text();
    const style = data.style === 'traditional'
      ? { early: 0.7, temperature: 0.5, halfLife: 19 }
      : { early: 0.3, temperature: 0.1, halfLife: 30 };
    for (const [key, value] of Object.entries({
      rules: data.rules,
      maxVisits: Math.max(16, Math.min(10000, Number(data.maxVisits) || 500)),
      numSearchThreads: Math.max(1, Math.min(16, Number(data.searchThreads) || 2)),
      logAllGTPCommunication: false,
      logSearchInfo: false,
      logToStderr: true,
      allowResignation: false,
      chosenMoveTemperatureEarly: style.early,
      chosenMoveTemperature: style.temperature,
      chosenMoveTemperatureHalflife: style.halfLife,
    })) {
      configText = setConfigValue(configText, key, value);
    }
    // A Web build always runs the bundled EIGEN/WASM backend. Keep the
    // requested backend in the payload for diagnostics, but do not pretend
    // that OpenCL or TFLite is available in a static browser deployment.
    if (data.backend && data.backend !== 'cpu') {
      configText = setConfigValue(configText, 'logToStderr', true);
    }
    if (data.style === 'human') {
      if (data.humanSLProfile) {
        configText = setConfigValue(configText, 'humanSLProfile', data.humanSLProfile);
      }
    }
    if (Number(data.maxTimeSeconds) > 0) {
      configText = setConfigValue(configText, 'maxTime', Number(data.maxTimeSeconds));
    }
    // Resolved rank-specific rules are applied before the user's free-form
    // overrides. This mirrors Android and keeps custom values authoritative.
    for (const [key, value] of parseConfigLines(data.resolvedOverrides)) {
      configText = setConfigValue(configText, key, value);
    }
    for (const line of String(data.configOverrides ?? '').split('\n')) {
      const match = line.trim().match(/^([A-Za-z][A-Za-z0-9]*)\s*=\s*(.*)$/);
      if (match) configText = setConfigValue(configText, match[1], match[2]);
    }
    }
    const commands = [
      `boardsize ${data.boardSize}`,
      'clear_board',
      `komi ${data.komi}`,
      ...data.setup,
      ...data.moves,
      ...(data.mode === 'adjudicate'
        ? ['final_status_list dead', 'final_score']
        : [`genmove ${data.side}`]),
      'quit',
    ];
    const stdin = new TextEncoder().encode(commands.join('\n') + '\n');
    let stdinOffset = 0;
    module = await createKataGo({
      locateFile: (path) => new URL(`katago/${path}`, self.location.href).href,
      stdin: () => stdinOffset < stdin.length ? stdin[stdinOffset++] : null,
      print: (line) => output.push(String(line)),
      printErr: (line) => diagnostics.push(String(line)),
      noExitRuntime: false,
    });
    module.FS.mkdir('/katago');
    const modelPath = String(data.modelFileName).endsWith('.txt.gz') ? '/katago/model.txt.gz' : '/katago/model.bin.gz';
    const humanPath = String(data.humanModelFileName).endsWith('.txt.gz') ? '/katago/human-model.txt.gz' : '/katago/human-model.bin.gz';
    module.FS.writeFile(modelPath, modelBytes);
    if (humanModelBytes) module.FS.writeFile(humanPath, humanModelBytes);
    module.FS.writeFile('/katago/gtp.cfg', configText);
    const args = [
      'gtp', '-model', modelPath, '-config', '/katago/gtp.cfg',
    ];
    if (humanModelBytes) args.push('-human-model', humanPath);
    const exitCode = module.callMain(args);
    if (exitCode !== 0) throw new Error(`KataGo exited ${exitCode}: ${diagnostics.slice(-16).join('\n')}`);
    const responses = [];
    let currentResponse;
    for (const line of output) {
      if (/^\?/.test(line)) throw new Error(`KataGo GTP: ${line}`);
      if (/^=/.test(line)) {
        if (currentResponse !== undefined) responses.push(currentResponse);
        currentResponse = line.slice(1).trim();
      } else if (currentResponse !== undefined && line.trim()) {
        currentResponse += ` ${line.trim()}`;
      } else if (currentResponse !== undefined) {
        responses.push(currentResponse);
        currentResponse = undefined;
      }
    }
    if (currentResponse !== undefined) responses.push(currentResponse);
    if (data.mode === 'adjudicate') {
      const statusIndex = 3 + data.setup.length + data.moves.length;
      if (responses.length <= statusIndex + 1) {
        throw new Error(JSON.stringify({
          reason: 'KataGo returned no final adjudication',
          responses,
          output: output.slice(-24), diagnostics: diagnostics.slice(-16),
        }));
      }
      self.postMessage({
        id: data.id,
        adjudication: JSON.stringify({
          dead: responses[statusIndex],
          score: responses[statusIndex + 1],
        }),
      });
      return;
    }
    const response = output.join('\n').match(/(?:^|\n)=\s*([A-T][0-9]+|pass|resign)\s*(?:\n|$)/i);
    if (!response) {
      throw new Error(JSON.stringify({
        reason: 'KataGo returned no GTP move',
        exitCode,
        stdinOffset,
        stdinLength: stdin.length,
        output: output.slice(-24), diagnostics: diagnostics.slice(-16),
      }));
    }
    self.postMessage({ id: data.id, vertex: response[1] });
  } catch (error) {
    let detail;
    if (error?.excPtr && module?.getExceptionMessage) {
      try {
        detail = JSON.stringify(module.getExceptionMessage(error));
      } catch (decodeError) {
        detail = `Native exception pointer ${error.excPtr}; decode failed: ${String(decodeError)}`;
      }
    }
    if (detail) {
      detail = `${detail}\n${diagnostics.slice(-16).join('\n')}`;
    } else if (error instanceof Error) {
      detail = `${error.name}: ${error.message}\n${error.stack ?? ''}`;
    } else {
      try {
        detail = JSON.stringify(error, Object.getOwnPropertyNames(error ?? {}));
      } catch (_) {
        detail = String(error);
      }
    }
    self.postMessage({ id: data.id, error: detail || String(error) });
  }
};
