import 'dart:convert';

import 'package:easyplay/go_model_catalog.dart';
import 'package:easyplay/go_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Serves a canned katagotraining reply, or fails, without touching the network.
class _FakeClient extends http.BaseClient {
  final int status;
  final String body;
  final Object? throwOnSend;
  _FakeClient({this.status = 200, this.body = '{}', this.throwOnSend});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (throwOnSend != null) throw throwOnSend!;
    final bytes = utf8.encode(body);
    return http.StreamedResponse(Stream.value(bytes), status);
  }
}

void main() {
  test('every runtime entry has a pinned fallback', () {
    for (final entry in GoModelCatalog.entries()) {
      if (entry.isRemote) {
        expect(
          GoModelCatalog.fallbackFor(entry),
          isNotNull,
          reason: '${entry.id} 需要快照兜底，否则离线时该行不可用',
        );
      }
    }
  });

  test('pinned entries carry a URL, and retired ones carry none', () {
    for (final entry in GoModelCatalog.entries()) {
      if (entry.isRemote) {
        expect(entry.endpoint, isNotNull);
        expect(entry.url, isNull);
      } else if (entry.url == null) {
        // No URL and no endpoint means upstream retired it; the row must show
        // as unavailable rather than failing after a tap.
        expect(entry.endpoint, isNull);
        expect(entry.description, contains('下架'));
      } else {
        expect(entry.bytes, isNotNull, reason: '${entry.id} 缺少体积');
      }
    }
  });

  test('the human entry is typed as a human network', () {
    final human = GoModelCatalog.entries().firstWhere(
      (e) => e.id == 'human-b18',
    );
    expect(human.kind, GoModelKind.human);
    expect(GoModelCatalog.kindOf(human), GoModelKind.human);
  });

  test('resolve reads the file, size and checksum from the API', () async {
    final entry = GoModelCatalog.entries().firstWhere((e) => e.id == 'latest');
    final client = _FakeClient(
      body: jsonEncode({
        'name': 'kata1-tf2-b10c384-s2941M-d5872M',
        'model_file':
            'https://media.katagotraining.org/uploaded/networks/models/'
            'kata1/kata1-tf2-b10c384-s2941M-d5872M.bin.gz',
        'model_file_bytes': 38271564,
        'model_file_sha256': 'abc123',
      }),
    );

    final resolved = await GoModelCatalog.resolve(entry, client: client);
    expect(resolved.name, 'kata1-tf2-b10c384-s2941M-d5872M');
    expect(resolved.bytes, 38271564);
    // The API does report a checksum, so runtime entries are verified as
    // strictly as pinned ones.
    expect(resolved.sha256, 'abc123');
    expect(resolved.url.path, endsWith('.bin.gz'));
  });

  test('resolve rejects a malformed payload instead of guessing', () async {
    final entry = GoModelCatalog.entries().firstWhere(
      (e) => e.id == 'strongest',
    );
    await expectLater(
      GoModelCatalog.resolve(
        entry,
        client: _FakeClient(body: jsonEncode({'name': 'x'})),
      ),
      throwsFormatException,
    );
    await expectLater(
      GoModelCatalog.resolve(entry, client: _FakeClient(body: '[]')),
      throwsFormatException,
    );
  });

  test('resolve surfaces HTTP failures so callers can fall back', () async {
    final entry = GoModelCatalog.entries().firstWhere((e) => e.id == 'latest');
    await expectLater(
      GoModelCatalog.resolve(entry, client: _FakeClient(status: 503)),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      GoModelCatalog.resolve(
        entry,
        client: _FakeClient(throwOnSend: const SocketExceptionStub()),
      ),
      throwsA(isA<SocketExceptionStub>()),
    );
  });

  test(
    'availability marks installed, downloadable and lookup-only rows',
    () async {
      final entries = GoModelCatalog.entries();
      const b10 = GoModelInfo(
        id: 'x',
        name: 'kata1-tf2-b10c384-s2941M-d5872M',
        fileName: 'kata1-tf2-b10c384-s2941M-d5872M.bin.gz',
        sha256: 'a',
        bytes: 1,
        bundled: false,
        kind: GoModelKind.standard,
      );

      final latest = entries.firstWhere((e) => e.id == 'latest');
      expect(
        await GoModelCatalog.availability(latest, const []),
        GoModelAvailability.needsLookup,
      );

      final pinned = entries.firstWhere((e) => e.id == 'b10c384');
      expect(
        await GoModelCatalog.availability(pinned, const []),
        GoModelAvailability.downloadable,
      );
      expect(
        await GoModelCatalog.availability(pinned, const [b10]),
        GoModelAvailability.installed,
      );

      final retired = entries.firstWhere((e) => e.id == 'old-10-block');
      expect(
        await GoModelCatalog.availability(retired, const []),
        GoModelAvailability.unavailable,
      );
    },
  );
}

/// Stands in for a transport error without importing dart:io (the catalogue is
/// also compiled for web).
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
  @override
  String toString() => 'SocketExceptionStub: 网络不可达';
}
