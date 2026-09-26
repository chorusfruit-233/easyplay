import 'dart:convert';

import 'package:http/http.dart' as http;

import 'go_models.dart';

/// Where a catalogue entry's bytes come from.
enum GoModelSource {
  /// A pinned release: the URL, size and checksum are fixed in the app.
  pinned,

  /// Resolved at runtime from katagotraining.org (the "latest" / "strongest"
  /// entries). The API reports a checksum, so these are still verified.
  remote,
}

/// One row of the Download Models screen.
class GoModelCatalogEntry {
  final String id;
  final String displayName;
  final String description;
  final GoModelKind kind;
  final GoModelSource source;

  /// Present for [GoModelSource.pinned].
  final Uri? url;
  final int? bytes;
  final String? sha256;

  /// Present for [GoModelSource.remote]: the API endpoint that reports the
  /// current network.
  final Uri? endpoint;

  const GoModelCatalogEntry({
    required this.id,
    required this.displayName,
    required this.description,
    required this.kind,
    required this.source,
    this.url,
    this.bytes,
    this.sha256,
    this.endpoint,
  });

  bool get isRemote => source == GoModelSource.remote;
}

/// A resolved, downloadable model: everything needed to fetch and verify it.
class GoModelDownload {
  final String name;
  final Uri url;
  final int? bytes;
  final String? sha256;
  const GoModelDownload({
    required this.name,
    required this.url,
    this.bytes,
    this.sha256,
  });
}

/// Verdict for one entry, as shown in the list.
enum GoModelAvailability {
  /// Bundled with the app, or already present in the model library.
  installed,

  /// Not present, and its download target is known.
  downloadable,

  /// A runtime lookup is needed before it can be offered.
  needsLookup,

  /// The pinned upstream file is gone (the mirror returns 403 for retired
  /// networks), so the row must not offer a download.
  unavailable,
}

/// The download catalogue.
///
/// Mirrors the reference product: pinned historical networks plus two runtime
/// entries ("latest" and "strongest") resolved from katagotraining.org, with a
/// pinned snapshot used when the lookup fails so the rows stay usable offline.
class GoModelCatalog {
  static const bundledId = 'b6';

  /// Pinned fallbacks for the two runtime entries. Used when the API cannot be
  /// reached, which is why the reference product labels them "(old)".
  static final _latestFallback = GoModelDownload(
    name: 'kata1-tf2-b10c384-s2941M-d5872M',
    url: Uri.parse(
      'https://media.katagotraining.org/uploaded/networks/models/kata1/'
      'kata1-tf2-b10c384-s2941M-d5872M.bin.gz',
    ),
    bytes: 38271564,
    sha256: '8015d49bdf45854c94e5f9e22b2b70e8738d3e56a6edca730e5b82509998a5b5',
  );

  static final _strongestFallback = GoModelDownload(
    name: 'kata1-b18c384nbt-s9996604416-d4316597426',
    url: Uri.parse(
      'https://media.katagotraining.org/uploaded/networks/models/kata1/'
      'kata1-b18c384nbt-s9996604416-d4316597426.bin.gz',
    ),
    bytes: 97898094,
    sha256: null,
  );

  /// The human-style network. Loaded through `-human-model`, so it is a
  /// separate kind rather than another main-model choice.
  static final humanModel = GoModelDownload(
    name: 'b18c384nbt-humanv0',
    url: Uri.parse(
      'https://github.com/lightvector/KataGo/releases/download/v1.15.0/'
      'b18c384nbt-humanv0.bin.gz',
    ),
    bytes: 99066230,
    sha256: null,
  );

  /// Retired networks on the media mirror answer 403, so they are listed as
  /// unavailable rather than offered and then failing.
  static const _retiredNote = '上游已下架，无法下载';

  static List<GoModelCatalogEntry> entries() => [
    GoModelCatalogEntry(
      id: 'latest',
      displayName: '最新',
      description: 'katagotraining 当前最新训练网络',
      kind: GoModelKind.standard,
      source: GoModelSource.remote,
      endpoint: Uri.parse(
        'https://katagotraining.org/api/networks/newest_training/',
      ),
    ),
    GoModelCatalogEntry(
      id: 'strongest',
      displayName: '最强',
      description: 'katagotraining 当前最强网络',
      kind: GoModelKind.standard,
      source: GoModelSource.remote,
      endpoint: Uri.parse(
        'https://katagotraining.org/api/networks/get_strongest/',
      ),
    ),
    GoModelCatalogEntry(
      id: 'b10c384',
      displayName: '推荐的新 b10c384 模型',
      description: '体积与棋力折中，CPU 也能跑',
      kind: GoModelKind.standard,
      source: GoModelSource.pinned,
      url: _latestFallback.url,
      bytes: _latestFallback.bytes,
      sha256: _latestFallback.sha256,
    ),
    GoModelCatalogEntry(
      id: 'b18c384nbt',
      displayName: '旧 b18 模型',
      description: '更大的卷积网络，需要 OpenCL 才有速度',
      kind: GoModelKind.standard,
      source: GoModelSource.pinned,
      url: _strongestFallback.url,
      bytes: _strongestFallback.bytes,
    ),
    GoModelCatalogEntry(
      id: 'human-b18',
      displayName: '人类棋风 b18 模型',
      description: '配合 humanSLProfile 使用，需要 OpenCL',
      kind: GoModelKind.human,
      source: GoModelSource.pinned,
      url: humanModel.url,
      bytes: humanModel.bytes,
    ),
    GoModelCatalogEntry(
      id: 'old-10-block',
      displayName: '旧 10 block 模型',
      description: _retiredNote,
      kind: GoModelKind.standard,
      source: GoModelSource.pinned,
    ),
    GoModelCatalogEntry(
      id: 'old-15-block',
      displayName: '旧 15 block 模型',
      description: _retiredNote,
      kind: GoModelKind.standard,
      source: GoModelSource.pinned,
    ),
  ];

  /// Resolves a runtime entry against katagotraining.org.
  ///
  /// The API reports `model_file`, `model_file_bytes` and `model_file_sha256`,
  /// so runtime entries are verified with the same strength as pinned ones.
  /// Throws when the lookup fails; callers fall back to the pinned snapshot.
  static Future<GoModelDownload> resolve(
    GoModelCatalogEntry entry, {
    http.Client? client,
  }) async {
    final endpoint = entry.endpoint;
    if (endpoint == null) {
      throw ArgumentError('Entry ${entry.id} has no endpoint');
    }
    final c = client ?? http.Client();
    final response = await c.get(endpoint);
    if (response.statusCode != 200) {
      throw StateError('${entry.displayName} 查询失败：HTTP ${response.statusCode}');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map<String, Object?>) {
      throw const FormatException('katagotraining 返回格式异常');
    }
    final file = body['model_file'];
    final name = body['name'];
    if (file is! String || name is! String) {
      throw const FormatException('katagotraining 返回缺少 model_file 或 name');
    }
    final bytes = body['model_file_bytes'];
    final sha = body['model_file_sha256'];
    return GoModelDownload(
      name: name,
      url: Uri.parse(file),
      bytes: bytes is int ? bytes : null,
      sha256: sha is String && sha.isNotEmpty ? sha : null,
    );
  }

  /// Name a pinned entry is recorded under once installed. The download step
  /// derives it from the URL's file name, so the library lookup must agree.
  static String downloadNameFor(GoModelCatalogEntry entry) {
    final pinned = entry.url;
    if (pinned != null && pinned.pathSegments.isNotEmpty) {
      final file = pinned.pathSegments.last;
      return file.endsWith('.bin.gz')
          ? file.substring(0, file.length - '.bin.gz'.length)
          : file;
    }
    return fallbackFor(entry)?.name ?? entry.id;
  }

  /// Pinned snapshot for an entry, used when [resolve] fails.
  static GoModelDownload? fallbackFor(GoModelCatalogEntry entry) =>
      switch (entry.id) {
        'latest' => _latestFallback,
        'strongest' => _strongestFallback,
        _ => null,
      };

  /// Whether the entry's bytes are already in the model library.
  static Future<GoModelAvailability> availability(
    GoModelCatalogEntry entry,
    List<GoModelInfo> installed,
  ) async {
    if (entry.id == 'latest' || entry.id == 'strongest') {
      return GoModelAvailability.needsLookup;
    }
    if (entry.url == null) return GoModelAvailability.unavailable;
    // The install step records the network name from the API payload, which for
    // a pinned entry is its file name. Matching on the entry id would never hit.
    final target = downloadNameFor(entry);
    return installed.any((m) => m.name == target)
        ? GoModelAvailability.installed
        : GoModelAvailability.downloadable;
  }

  /// Kind to record for an entry, used to reject a mismatched download before
  /// it reaches the engine.
  static GoModelKind kindOf(GoModelCatalogEntry entry) => switch (entry.id) {
    'human-b18' => GoModelKind.human,
    _ => entry.kind,
  };
}
