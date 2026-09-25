import createKataGo from './katago/katago.js';

const modelName = 'g170-b6c96-s175395328-d26788732.bin.gz';

self.onmessage = async ({ data }) => {
  let module;
  const output = [];
  try {
    if (!self.crossOriginIsolated || typeof SharedArrayBuffer === 'undefined') {
      throw new Error('KataGo Web requires COOP/COEP response headers for WebAssembly threads.');
    }
    const modelResponse = await fetch(
      new URL(`assets/assets/katago/${modelName}`, self.location.href),
    );
    if (!modelResponse.ok) {
      throw new Error(`KataGo model request failed: HTTP ${modelResponse.status}`);
    }
    const modelBytes = new Uint8Array(await modelResponse.arrayBuffer());
    const configResponse = await fetch(
      new URL('assets/assets/katago/gtp_example.cfg', self.location.href),
    );
    if (!configResponse.ok) {
      throw new Error(`KataGo config request failed: HTTP ${configResponse.status}`);
    }
    const configText = (await configResponse.text())
      .replace(/^rules\s*=.*$/m, `rules = ${data.rules}`)
      .replace(/^maxVisits\s*=.*$/m, 'maxVisits = 48')
      .replace(/^numSearchThreads\s*=.*$/m, 'numSearchThreads = 1')
      .replace(/^logAllGTPCommunication\s*=.*$/m, 'logAllGTPCommunication = false')
      .replace(/^logSearchInfo\s*=.*$/m, 'logSearchInfo = false')
      .replace(/^logToStderr\s*=.*$/m, 'logToStderr = true')
      .replace(/^allowResignation\s*=.*$/m, 'allowResignation = false');
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
