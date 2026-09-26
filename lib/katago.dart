import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'game_session.dart';
import 'go_ai_settings.dart';
import 'go_engine_profiles.dart';
import 'go_engine_config.dart';
export 'go_engine_config.dart';
import 'go_models.dart';
import 'katago_web_stub.dart'
    if (dart.library.js_interop) 'katago_web.dart'
    as web_katago;

class KataGoModelSpec {
  final String id;
  final String displayName;
  final Uri url;
  final String? sha256;
  const KataGoModelSpec({
    required this.id,
    required this.displayName,
    required this.url,
    this.sha256,
  });
}

/// The pinned b6 network is bundled for offline Android and static Web play.
class KataGoCatalog {
  static final b6 = KataGoModelSpec(
    id: 'b6',
    displayName: 'KataGo b6（小模型）',
    url: Uri.parse(
      'https://media.katagotraining.org/uploaded/networks/models/g170-b6c96-s175395328-d26788732.bin.gz',
    ),
    sha256: 'f5d32604e3675c480c7c8f6aa579a1ea857135628a0afccc8fa56330fbacd38d',
  );

  static const b6Asset = 'assets/katago/g170-b6c96-s175395328-d26788732.bin.gz';

  /// Returns the bundled, gzip-compressed CC0 b6 network. KataGo accepts
  /// gzipped networks directly, so callers can pass these bytes to a runtime.
  static Future<Uint8List> loadBundledB6() async {
    final data = await rootBundle.load(b6Asset);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (KataGoDownloadClient.sha256Hex(bytes) != b6.sha256) {
      throw StateError('内置 KataGo 模型校验失败');
    }
    return bytes;
  }
}

class KataGoDownloadClient {
  final http.Client client;
  KataGoDownloadClient({http.Client? client})
    : client = client ?? http.Client();

  Future<Uint8List> download(
    KataGoModelSpec model, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final request = http.Request('GET', model.url);
    final response = await client.send(request);
    if (response.statusCode != 200) {
      throw StateError('KataGo 下载失败：HTTP ${response.statusCode}');
    }
    final builder = BytesBuilder();
    var received = 0;
    await for (final chunk in response.stream) {
      builder.add(chunk);
      received += chunk.length;
      onProgress?.call(received, response.contentLength);
    }
    final bytes = builder.takeBytes();
    if (model.sha256 != null && sha256Hex(bytes) != model.sha256) {
      throw StateError('KataGo 模型校验失败：${model.id}');
    }
    return bytes;
  }

  static String sha256Hex(Uint8List bytes) {
    return sha256.convert(bytes).toString();
  }
}

/// Transport-neutral GTP client. Android can connect this to a native process
/// stdin/stdout; Web can connect it to a Worker or remote service.
class KataGoGtpClient {
  final Future<String> Function(String command) send;
  KataGoGtpClient(this.send);

  Future<void> initialize({required int boardSize, double komi = 7.5}) async {
    await send('boardsize $boardSize');
    await send('komi $komi');
    await send('clear_board');
  }

  Future<String> genmove(Side side) async =>
      _clean(await send('genmove ${side == Side.black ? 'B' : 'W'}'));

  Future<void> play(Side side, String vertex) async {
    await send('play ${side == Side.black ? 'B' : 'W'} $vertex');
  }

  Future<void> undo() async {
    await send('undo');
  }

  Future<void> quit() async {
    await send('quit');
  }

  String _clean(String response) {
    final line = response
        .split('\n')
        .map((v) => v.trim())
        .firstWhere(
          (v) => v.isNotEmpty && !v.startsWith('=') && !v.startsWith('?'),
          orElse: () => response.trim(),
        );
    return line.replaceFirst(RegExp(r'^=\s*'), '').trim();
  }
}

Future<void> validateKataGoSelection(
  GoAiSettings settings,
  GoEngineProfile engine,
) async {
  settings.validateHumanStyle();
  final main = await GoModelLibrary.byId(settings.modelId);
  final human = settings.usesHumanStyle && settings.humanModelId != null
      ? await GoModelLibrary.byId(settings.humanModelId!)
      : null;
  GoModelCompatibility.validate(
    model: main,
    engine: engine,
    humanModel: human,
    useBuiltinHumanStyle:
        settings.usesHumanStyle && settings.useBuiltinHumanStyle,
  );
  if (main.isHumanModel && !settings.usesHumanStyle) {
    throw ArgumentError('人类棋风主模型需要选择人类棋风和有效段位');
  }
}

/// Android GTP transport. The Kotlin host owns the upstream KataGo process;
/// all blocking pipe reads happen away from Flutter's UI thread.
class KataGoAndroidRuntime {
  static const MethodChannel _channel = MethodChannel('easyplay/katago');
  bool _started = false;
  int _generation = 0;
  Future<void> _tail = Future<void>.value();
  bool get isStarted => _started;

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<Map<String, Object?>> backendPreflight(GoEngineBackend backend) async {
    if (!isSupported) {
      return {
        'backend': backend.name,
        'available': false,
        'runnable': false,
        'reason': '当前平台不是 Android',
      };
    }
    final result = await _channel.invokeMethod<Map>('backendPreflight', {
      'backend': backend.name,
    });
    return result?.cast<String, Object?>() ?? <String, Object?>{};
  }

  Future<void> start({
    required GoConfig config,
    GoAiSettings settings = const GoAiSettings(),
  }) async {
    if (!isSupported) throw UnsupportedError('当前平台尚未接入 KataGo 原生引擎');
    final generation = _generation;
    await _enqueue(() async {
      if (generation != _generation) throw StateError('引擎启动已取消');
      if (_started) return;
      final model = await GoModelLibrary.load(settings.modelId);
      final engine = await GoEngineLibrary.byId(settings.engineProfileId);
      await validateKataGoSelection(settings, engine);

      await GoModelLibrary.validateForEngine(
        id: settings.modelId,
        backend: engine.backend,
      );
      Uint8List? humanModel;
      if (settings.style == GoAiStyle.human &&
          !settings.useBuiltinHumanStyle &&
          settings.humanModelId != null) {
        await GoModelLibrary.validateForEngine(
          id: settings.humanModelId!,
          backend: engine.backend,
          humanModel: true,
        );
        humanModel = await GoModelLibrary.load(settings.humanModelId!);
      }
      try {
        final configText = await _configText(config, settings, engine);
        final arguments = <String, Object?>{
          'model': model,
          'modelFileName': (await GoModelLibrary.byId(
            settings.modelId,
          )).fileName,
          'humanModel': ?humanModel,
          if (humanModel != null)
            'humanModelFileName': (await GoModelLibrary.info(
              settings.humanModelId!,
            )).fileName,

          'backend': engine.backend.name,
          'boardSize': config.boardSize,
          if (engine.openclGpuIdx != null) 'openclGpuIdx': engine.openclGpuIdx,
          if (engine.openclLibraryName != null)
            'openclLibraryName': engine.openclLibraryName,
          'config': configText,
        };
        if (generation != _generation) throw StateError('引擎启动已取消');
        await _channel.invokeMethod<String>('start', arguments);
        if (generation != _generation) throw StateError('引擎启动已取消');
        _started = true;
        await _sendNow('boardsize ${config.boardSize}');
        await _sendNow('clear_board');
        await _sendNow('komi ${config.komi}');
      } catch (_) {
        _started = false;
        try {
          await _channel.invokeMethod<String>('stop');
        } catch (_) {
          // Preserve the startup error when the host channel itself is absent.
        }
        rethrow;
      }
    });
  }

  Future<String> send(String command) => _enqueue(() => _sendNow(command));

  Future<String> _sendNow(String command) async {
    if (!_started) throw StateError('KataGo 尚未启动');
    final response = await _channel.invokeMethod<String>('command', {
      'line': command,
    });
    return response ?? '';
  }

  Future<void> stop() async {
    _generation++;
    _started = false;
    if (isSupported) await _channel.invokeMethod<String>('stop');
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    // A failed command should be reported to its caller without poisoning the
    // queue; otherwise a later stop/restart could never reach the native side.
    _tail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  static Future<String> _configText(
    GoConfig config,
    GoAiSettings settings,
    GoEngineProfile engine,
  ) async {
    return resolveKataGoConfig(
      config: config,
      settings: settings,
      engine: engine,
    );
  }
}

/// Browser engine adapter. Each request runs in a same-origin Web Worker with
/// a threaded WebAssembly module; static hosting must provide COOP/COEP headers.
class KataGoWebRuntime {
  static bool get isSupported => kIsWeb;

  Future<String> genmove({
    required GoConfig config,
    required GoAiSettings settings,
    required List<String> setup,
    required List<String> moves,
    required Side side,
  }) async {
    final engine = await GoEngineLibrary.byId(settings.engineProfileId);
    await validateKataGoSelection(settings, engine);
    if (engine.backend == GoEngineBackend.tflite) {
      throw UnsupportedError('静态 Web 不支持 TFLite，请选择 CPU/WASM 和标准模型');
    }
    final mainModelId = settings.modelId;
    await GoModelLibrary.validateForEngine(
      id: mainModelId,
      backend: GoEngineBackend.cpu,
    );
    final modelBase64 = mainModelId == GoModelLibrary.bundledId
        ? null
        : base64Encode(await GoModelLibrary.load(mainModelId));
    final humanModelBase64 =
        settings.style == GoAiStyle.human &&
            !settings.useBuiltinHumanStyle &&
            settings.humanModelId != null
        ? base64Encode(await _loadWebHumanModel(settings.humanModelId!))
        : null;
    final configText = await resolveKataGoConfig(
      config: config,
      settings: settings,
      engine: engine,
      forWeb: true,
    );
    return web_katago.genmoveOnWeb(
      config: config,
      settings: settings,
      modelBase64: modelBase64,
      modelFileName: (await GoModelLibrary.byId(mainModelId)).fileName,
      humanModelFileName: humanModelBase64 == null
          ? null
          : (await GoModelLibrary.byId(settings.humanModelId!)).fileName,
      humanModelBase64: humanModelBase64,
      humanSLProfile: settings.usesHumanStyle
          ? settings.resolvedHumanSLProfile
          : null,
      backend: engine.backend.name,
      configText: configText,
      maxTimeSeconds: engine.maxTimeSeconds,
      searchThreads: engine.searchThreads,
      configOverrides: engine.configOverrides,
      setup: setup,
      moves: moves,
      side: side,
    );
  }

  Future<Map<String, Object?>> adjudicate({
    required GoConfig config,
    GoAiSettings settings = const GoAiSettings(),
    required List<String> setup,
    required List<String> moves,
  }) async {
    final engine = await GoEngineLibrary.byId(settings.engineProfileId);
    await validateKataGoSelection(settings, engine);
    if (engine.backend == GoEngineBackend.tflite) {
      throw UnsupportedError('静态 Web 不支持 TFLite');
    }
    final mainModelId = settings.modelId;
    await GoModelLibrary.validateForEngine(
      id: mainModelId,
      backend: GoEngineBackend.cpu,
    );
    final modelBase64 = mainModelId == GoModelLibrary.bundledId
        ? null
        : base64Encode(await GoModelLibrary.load(mainModelId));
    final humanModelBase64 =
        settings.style == GoAiStyle.human &&
            !settings.useBuiltinHumanStyle &&
            settings.humanModelId != null
        ? base64Encode(await _loadWebHumanModel(settings.humanModelId!))
        : null;
    final configText = await resolveKataGoConfig(
      config: config,
      settings: settings,
      engine: engine,
      forWeb: true,
    );
    return web_katago.adjudicateOnWeb(
      config: config,
      settings: settings,
      modelBase64: modelBase64,
      modelFileName: (await GoModelLibrary.byId(mainModelId)).fileName,
      humanModelFileName: humanModelBase64 == null
          ? null
          : (await GoModelLibrary.byId(settings.humanModelId!)).fileName,
      humanModelBase64: humanModelBase64,
      humanSLProfile: settings.usesHumanStyle
          ? settings.resolvedHumanSLProfile
          : null,
      backend: engine.backend.name,
      configText: configText,
      maxTimeSeconds: engine.maxTimeSeconds,
      searchThreads: engine.searchThreads,
      configOverrides: engine.configOverrides,
      setup: setup,
      moves: moves,
    );
  }

  Future<Uint8List> _loadWebHumanModel(String id) async {
    await GoModelLibrary.validateForEngine(
      id: id,
      backend: GoEngineBackend.cpu,
      humanModel: true,
    );
    return GoModelLibrary.load(id);
  }
}
