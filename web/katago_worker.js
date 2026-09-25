import createKataGo from './katago/katago.js';

const modelName = 'g170-b6c96-s175395328-d26788732.bin.gz';

function setConfigValue(config, key, value) {
  const expression = new RegExp(`^#?\\s*${key}\\s*=.*$`, 'm');
  if (expression.test(config)) return config.replace(expression, `${key} = ${value}`);
  return `${config}\n${key} = ${value}\n`;
}

self.onmessage = async ({ data }) => {
  let module;
  const output = [];
  try {
    if (!self.crossOriginIsolated || typeof SharedArrayBuffer === 'undefined') {
      throw new Error('KataGo Web requires COOP/COEP response headers for WebAssembly threads.');
    }
    let modelBytes;
    if (data.modelBase64) {
      const binary = atob(data.modelBase64);
      modelBytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
    } else {
      const modelResponse = await fetch(
        new URL(`assets/assets/katago/${modelName}`, self.location.href),
      );
      if (!modelResponse.ok) {
        throw new Error(`KataGo model request failed: HTTP ${modelResponse.status}`);
      }
      modelBytes = new Uint8Array(await modelResponse.arrayBuffer());
    }
    const configResponse = await fetch(
      new URL('assets/assets/katago/gtp_example.cfg', self.location.href),
    );
    if (!configResponse.ok) {
      throw new Error(`KataGo config request failed: HTTP ${configResponse.status}`);
    }
    let configText = await configResponse.text();
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
    if (Number(data.maxTimeSeconds) > 0) {
      configText = setConfigValue(configText, 'maxTime', Number(data.maxTimeSeconds));
    }
    for (const line of String(data.configOverrides ?? '').split('\n')) {
      const match = line.trim().match(/^([A-Za-z][A-Za-z0-9]*)\s*=\s*(.*)$/);
      if (match) configText = setConfigValue(configText, match[1], match[2]);
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
      printErr: (line) => output.push(String(line)),
      noExitRuntime: false,
    });
    module.FS.mkdir('/katago');
    module.FS.writeFile('/katago/model.bin.gz', modelBytes);
    module.FS.writeFile('/katago/gtp.cfg', configText);
    const exitCode = module.callMain([
      'gtp', '-model', '/katago/model.bin.gz', '-config', '/katago/gtp.cfg',
    ]);
    const responses = [];
    let currentResponse;
    for (const line of output) {
      if (/^[=?]/.test(line)) {
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
          output: output.slice(-24),
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
    const response = output.join('\n').match(/(?:^|\n)=\s*([A-T][0-9]+|pass)\s*(?:\n|$)/i);
    if (!response) {
      throw new Error(JSON.stringify({
        reason: 'KataGo returned no GTP move',
        exitCode,
        stdinOffset,
        stdinLength: stdin.length,
        output: output.slice(-24),
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
      detail = `${detail}\n${output.slice(-16).join('\n')}`;
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
