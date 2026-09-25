import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'go_model_storage.dart';

class GoModelInfo {
  final String id;
  final String name;
  final String fileName;
  final String sha256;
  final int bytes;
  final bool bundled;

  const GoModelInfo({
    required this.id,
    required this.name,
    required this.fileName,
    required this.sha256,
    required this.bytes,
    this.bundled = false,
  });

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'fileName': fileName,
    'sha256': sha256,
    'bytes': bytes,
  };

  factory GoModelInfo.fromJson(Map<String, Object?> json) => GoModelInfo(
    id: json['id']! as String,
    name: json['name']! as String,
    fileName: json['fileName']! as String,
    sha256: json['sha256']! as String,
    bytes: json['bytes']! as int,
  );
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
  );

  static Future<List<GoModelInfo>> available() async {
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
    final id = (await SharedPreferences.getInstance()).getString(_activeKey);
    final models = await available();
    return models.any((model) => model.id == id) ? id! : bundledId;
  }

  static Future<void> setActive(String id) async {
    final models = await available();
    if (!models.any((model) => model.id == id)) {
      throw ArgumentError.value(id, 'id', 'KataGo 模型不存在');
    }
    await (await SharedPreferences.getInstance()).setString(_activeKey, id);
  }

  static Future<Uint8List> load(String id) async {
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

  static Future<GoModelInfo> install({
    required String name,
    required String fileName,
    required Uint8List bytes,
    String? expectedSha256,
  }) async {
    final cleanName = name.trim();
    final cleanFileName = fileName.trim();
    if (cleanName.isEmpty) throw ArgumentError('请填写模型名称');
    if (!cleanFileName.toLowerCase().endsWith('.gz')) {
      throw ArgumentError('KataGo 模型应为 .bin.gz 或 .txt.gz 文件');
    }
    if (bytes.length < 1024 || bytes[0] != 0x1f || bytes[1] != 0x8b) {
      throw ArgumentError('文件不是有效的 gzip KataGo 模型');
    }
    final checksum = sha256.convert(bytes).toString();
    if (expectedSha256 != null &&
        expectedSha256.trim().isNotEmpty &&
        checksum.toLowerCase() != expectedSha256.trim().toLowerCase()) {
      throw StateError('模型 SHA-256 校验失败');
    }
    final info = GoModelInfo(
      id: checksum,
      name: cleanName,
      fileName: cleanFileName.split(RegExp(r'[/\\]')).last,
      sha256: checksum,
      bytes: bytes.length,
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
