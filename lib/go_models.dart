import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'go_model_storage.dart';
import 'go_engine_profiles.dart';

enum GoModelKind { standard, human, tflite }

/// Validate the compressed stream and KataGo header, including human metadata.
/// Native KataGo additionally validates every tensor when the engine starts.
GoModelKind inspectGoModel(Uint8List bytes) {
  if (bytes.length < 16) throw const FormatException('模型文件不完整');
  if (ascii.decode(bytes.sublist(4, 8), allowInvalid: true) == 'TFL3') {
    final offset = ByteData.sublistView(bytes).getUint32(0, Endian.little);
    if (offset < 8 || offset >= bytes.length - 4) {
      throw const FormatException('TFLite 根表损坏');
    }
    return GoModelKind.tflite;
  }
  if (bytes[0] != 0x1f || bytes[1] != 0x8b) {
    throw const FormatException('模型不是 gzip 或 TFLite 文件');
  }
  final output = OutputMemoryStream();
  if (!const GZipDecoder().decodeStream(
    InputMemoryStream(bytes),
    output,
    verify: true,
  )) {
    throw const FormatException('gzip 模型损坏或下载未完成');
  }
  final decoded = output.getBytes();
  final trailer = ByteData.sublistView(bytes, bytes.length - 8);
  if (decoded.length != trailer.getUint32(4, Endian.little) ||
      getCrc32(decoded) != trailer.getUint32(0, Endian.little)) {
    throw const FormatException('gzip 模型校验失败');
  }
  final header = latin1
      .decode(decoded.take(2048).toList())
      .trimLeft()
      .split(RegExp(r'\s+'));
  if (header.length < 5 ||
      !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(header.first)) {
    throw const FormatException('缺少 KataGo 网络名称');
  }
  final version = int.tryParse(header[1]);
  if (version == null ||
      version < 3 ||
      version > 16 ||
      (int.tryParse(header[2]) ?? 0) <= 0 ||
      (int.tryParse(header[3]) ?? 0) <= 0) {
    throw const FormatException('无效或当前引擎不支持的 KataGo 模型版本');
  }
  if (version >= 13) {
    // ModelDesc reads seven positive postprocess multipliers before metadata.
    if (header.length < 12 ||
        header.skip(4).take(7).any((token) {
          final value = double.tryParse(token);
          return value == null || !value.isFinite || value <= 0;
        })) {
      throw const FormatException('无效或不完整的 KataGo 模型参数');
    }
  }
  if (version >= 15) {
    // v13 adds seven postprocess multipliers; v15 adds metadata encoder.
    final encoder = header.length > 11 ? int.tryParse(header[11]) : null;
    if (encoder != 0 && encoder != 1) {
      throw const FormatException('无效的 KataGo metadata encoder');
    }
    if (header.length < 20 ||
        header.skip(12).take(7).any((token) => int.tryParse(token) == null)) {
      throw const FormatException('不完整的 KataGo metadata 参数');
    }
    return encoder == 1 ? GoModelKind.human : GoModelKind.standard;
  }
  return GoModelKind.standard;
}

extension GoModelKindX on GoModelKind {
  String get label => switch (this) {
    GoModelKind.standard => '标准网络',
    GoModelKind.human => '人类棋风网络',
    GoModelKind.tflite => 'TFLite 网络',
  };
}

class GoModelInfo {
  final String id;
  final String name;
  final String fileName;
  final String sha256;
  final int bytes;
  final bool bundled;
  final GoModelKind kind;

  const GoModelInfo({
    required this.id,
    required this.name,
    required this.fileName,
    required this.sha256,
    required this.bytes,
    this.bundled = false,
    this.kind = GoModelKind.standard,
  });

  bool get isHumanModel => kind == GoModelKind.human;

  /// Whether this network format can be loaded by the selected KataGo backend.
  bool supportsBackend(GoEngineBackend backend) => switch (kind) {
    GoModelKind.standard =>
      backend == GoEngineBackend.cpu || backend == GoEngineBackend.opencl,
    GoModelKind.human =>
      backend == GoEngineBackend.cpu || backend == GoEngineBackend.opencl,
    GoModelKind.tflite => backend == GoEngineBackend.tflite,
  };

  String get compatibilityDescription => switch (kind) {
    GoModelKind.standard => 'CPU 或 OpenCL',
    GoModelKind.human => 'CPU 或 OpenCL（不能用于 TFLite）',
    GoModelKind.tflite => 'TFLite Mobile',
  };

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'fileName': fileName,
    'sha256': sha256,
    'bytes': bytes,
    'kind': kind.name,
  };

  factory GoModelInfo.fromJson(Map<String, Object?> json) => GoModelInfo(
    id: json['id']! as String,
    name: json['name']! as String,
    fileName: json['fileName']! as String,
    sha256: json['sha256']! as String,
    bytes: json['bytes']! as int,
    kind: GoModelKind.values.firstWhere(
      (value) => value.name == json['kind'],
      orElse: () => GoModelKind.standard,
    ),
  );
}

/// Validates the complete model/backend/human-style selection before startup.
class GoModelCompatibility {
  static void validate({
    required GoModelInfo model,
    required GoEngineProfile engine,
    GoModelInfo? humanModel,
    bool useBuiltinHumanStyle = false,
  }) {
    if (!model.supportsBackend(engine.backend)) {
      throw ArgumentError(
        '模型“${model.name}”只能运行在${model.compatibilityDescription}，'
        '当前引擎为 ${engine.backend.label}',
      );
    }
    if (model.isHumanModel && humanModel != null) {
      throw ArgumentError('人类棋风主模型不能再叠加独立 human model');
    }
    if (useBuiltinHumanStyle && !model.isHumanModel) {
      throw ArgumentError('所选主模型不是人类棋风网络');
    }
    if (useBuiltinHumanStyle && humanModel != null) {
      throw ArgumentError('主模型自带人类棋风时不能再配置独立 human model');
    }
    if (humanModel == null) return;
    if (!humanModel.isHumanModel) {
      throw ArgumentError('human model 必须标记为人类棋风网络');
    }
    if (engine.backend == GoEngineBackend.tflite) {
      throw ArgumentError('TFLite Mobile 暂不支持 human model');
    }
    if (!humanModel.supportsBackend(engine.backend)) {
      throw ArgumentError(
        'human model“${humanModel.name}”不能运行在 ${engine.backend.label}',
      );
    }
  }
}

class GoModelLibrary {
  static const bundledId = 'b6';
  static const _recordsKey = 'easyplay.katago_models';
  static const _activeKey = 'easyplay.katago_active_model';
  static const _b6Asset =
      'assets/katago/g170-b6c96-s175395328-d26788732.bin.gz';
  static const _b6Sha256 =
      'f5d32604e3675c480c7c8f6aa579a1ea857135628a0afccc8fa56330fbacd38d';

  static const bundledModel = GoModelInfo(
    id: bundledId,
    name: 'KataGo b6 小模型',
    fileName: 'g170-b6c96-s175395328-d26788732.bin.gz',
    sha256: _b6Sha256,
    bytes: 0,
    bundled: true,
    kind: GoModelKind.standard,
  );

  static Future<List<GoModelInfo>> available() async {
    if (kIsWeb) return const [bundledModel];
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_recordsKey) ?? const <String>[];
    final result = <GoModelInfo>[bundledModel];
    for (final raw in stored) {
      try {
        final value = GoModelInfo.fromJson(
          (jsonDecode(raw) as Map).cast<String, Object?>(),
        );
        if (value.id != bundledId) result.add(value);
      } catch (_) {
        // Ignore incomplete metadata from an interrupted earlier import.
      }
    }
    return result;
  }

  static Future<String> activeId() async {
    if (kIsWeb) return bundledId;
    final id = (await SharedPreferences.getInstance()).getString(_activeKey);
    final models = await available();
    return models.any((model) => model.id == id) ? id! : bundledId;
  }

  static Future<void> setActive(String id) async {
    if (kIsWeb && id != bundledId) {
      throw UnsupportedError('Web 端只支持应用内置的 KataGo 模型');
    }
    final models = await available();
    if (!models.any((model) => model.id == id)) {
      throw ArgumentError.value(id, 'id', 'KataGo 模型不存在');
    }
    await (await SharedPreferences.getInstance()).setString(_activeKey, id);
  }

  static Future<GoModelInfo> byId(String id) async =>
      (await available()).firstWhere(
        (model) => model.id == id,
        orElse: () => throw StateError('找不到 KataGo 模型：$id'),
      );

  static Future<Uint8List> load(String id) async {
    if (kIsWeb && id != bundledId) {
      throw UnsupportedError('Web 端只支持应用内置的 KataGo 模型');
    }
    if (id == bundledId) {
      final data = await rootBundle.load(_b6Asset);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      if (sha256.convert(bytes).toString() != _b6Sha256) {
        throw StateError('内置 KataGo 模型校验失败');
      }
      return bytes;
    }
    final model = (await available())
        .where((entry) => entry.id == id)
        .firstOrNull;
    if (model == null) throw StateError('找不到 KataGo 模型：$id');
    final bytes = await GoModelStorage.load(id);
    if (bytes == null || sha256.convert(bytes).toString() != model.sha256) {
      throw StateError('KataGo 模型文件缺失或校验失败：${model.name}');
    }
    return bytes;
  }

  static Future<GoModelInfo> info(String id) async {
    final model = (await available())
        .where((entry) => entry.id == id)
        .firstOrNull;
    if (model == null) throw StateError('找不到 KataGo 模型：$id');
    return model;
  }

  static Future<void> validateForEngine({
    required String id,
    required GoEngineBackend backend,
    bool humanModel = false,
  }) async {
    final model = await info(id);
    if (humanModel && model.kind != GoModelKind.human) {
      throw StateError('所选模型不是人类棋风网络');
    }
    if (backend == GoEngineBackend.tflite && model.kind != GoModelKind.tflite) {
      throw StateError('TFLite 后端必须使用 TFLite 模型');
    }
    if (backend != GoEngineBackend.tflite && model.kind == GoModelKind.tflite) {
      throw StateError('TFLite 模型只能使用 TFLite 后端');
    }
  }

  static Future<GoModelInfo> install({
    required String name,
    required String fileName,
    required Uint8List bytes,
    String? expectedSha256,
    GoModelKind kind = GoModelKind.standard,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Web 端只允许使用应用内置的 KataGo 模型');
    }
    final cleanName = name.trim();
    final cleanFileName = fileName.trim();
    if (cleanName.isEmpty) throw ArgumentError('请填写模型名称');
    final lowerFileName = cleanFileName.toLowerCase();
    final validExtension = kind == GoModelKind.tflite
        ? lowerFileName.endsWith('.tflite') || lowerFileName.endsWith('.lite')
        : lowerFileName.endsWith('.bin.gz') ||
              lowerFileName.endsWith('.txt.gz');
    if (!validExtension) {
      throw ArgumentError(
        kind == GoModelKind.tflite
            ? 'TFLite 模型应为 .tflite 或 .lite 文件'
            : 'KataGo 模型应为 .bin.gz 或 .txt.gz 文件',
      );
    }
    if (bytes.length < 1024 ||
        (kind != GoModelKind.tflite &&
            (bytes[0] != 0x1f || bytes[1] != 0x8b))) {
      throw ArgumentError(
        kind == GoModelKind.tflite
            ? '文件不是有效的 TFLite 模型'
            : '文件不是有效的 gzip KataGo 模型',
      );
    }
    final checksum = sha256.convert(bytes).toString();
    if (expectedSha256 != null &&
        expectedSha256.trim().isNotEmpty &&
        checksum.toLowerCase() != expectedSha256.trim().toLowerCase()) {
      throw StateError('模型 SHA-256 校验失败');
    }
    final detectedKind = await compute(inspectGoModel, bytes);
    if ((kind == GoModelKind.human && detectedKind != GoModelKind.human) ||
        (kind == GoModelKind.tflite) != (detectedKind == GoModelKind.tflite)) {
      throw ArgumentError('模型内容与所选类型不符：实际为 ${detectedKind.label}');
    }
    final info = GoModelInfo(
      id: checksum,
      name: cleanName,
      fileName: cleanFileName.split(RegExp(r'[/\\]')).last,
      sha256: checksum,
      bytes: bytes.length,
      kind: detectedKind,
    );
    await GoModelStorage.save(info.id, bytes);
    final prefs = await SharedPreferences.getInstance();
    final records = prefs.getStringList(_recordsKey) ?? <String>[];
    records.removeWhere((raw) {
      try {
        return (jsonDecode(raw) as Map)['id'] == info.id;
      } catch (_) {
        return false;
      }
    });
    records.add(jsonEncode(info.toJson()));
    await prefs.setStringList(_recordsKey, records);
    return info;
  }

  static Future<void> remove(String id) async {
    if (id == bundledId) throw ArgumentError('内置模型不能删除');
    final profiles = await GoEngineLibrary.available();
    final references = profiles
        .where((p) => p.modelId == id || p.humanModelId == id)
        .map((p) => p.name)
        .toList();
    if (references.isNotEmpty) {
      throw StateError('模型正在被引擎配置使用：${references.join('、')}，请先修改对应配置');
    }
    await GoModelStorage.delete(id);
    final prefs = await SharedPreferences.getInstance();
    final records = prefs.getStringList(_recordsKey) ?? <String>[];
    records.removeWhere((raw) {
      try {
        return (jsonDecode(raw) as Map)['id'] == id;
      } catch (_) {
        return false;
      }
    });
    await prefs.setStringList(_recordsKey, records);
    if (prefs.getString(_activeKey) == id) {
      await prefs.setString(_activeKey, bundledId);
    }
  }
}
