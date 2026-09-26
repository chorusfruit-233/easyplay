import 'dart:convert';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:easyplay/go_engine_profiles.dart';
import 'package:easyplay/go_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Only the model envelope and header are inspected here. Tensor validation is
// KataGo's responsibility when it loads a model; these are not playable models.
Uint8List modelEnvelope({
  int version = 15,
  int metadataEncoder = 0,
  String name = 'katago-test-network',
  String prefix = '',
}) {
  final random = Random(38);
  return GZipEncoder().encodeBytes([
    ...ascii.encode(
      '$prefix$name\n$version\n22\n19\n'
      '${version >= 13 ? '20\n20\n20\n20\n40\n0.25\n30\n' : ''}'
      '${version >= 15 ? '$metadataEncoder\n0\n0\n0\n0\n0\n0\n0\n' : ''}'
      'trunk\n',
    ),
    ...List<int>.generate(4096, (_) => random.nextInt(256)),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const standard = GoModelInfo(
    id: 'standard',
    name: 'standard',
    fileName: 'model.bin.gz',
    sha256: 'a',
    bytes: 1024,
  );
  const human = GoModelInfo(
    id: 'human',
    name: 'human',
    fileName: 'human.txt.gz',
    sha256: 'b',
    bytes: 1024,
    kind: GoModelKind.human,
  );
  const tflite = GoModelInfo(
    id: 'tflite',
    name: 'tflite',
    fileName: 'model.tflite',
    sha256: 'c',
    bytes: 1024,
    kind: GoModelKind.tflite,
  );

  test('checks model/backend compatibility', () {
    GoModelCompatibility.validate(
      model: standard,
      engine: GoEngineProfile.builtIn,
    );
    expect(
      () => GoModelCompatibility.validate(
        model: standard,
        engine: const GoEngineProfile(
          id: 'tflite',
          name: 'TFLite',
          backend: GoEngineBackend.tflite,
        ),
      ),
      throwsArgumentError,
    );
    GoModelCompatibility.validate(
      model: tflite,
      engine: const GoEngineProfile(
        id: 'tflite',
        name: 'TFLite',
        backend: GoEngineBackend.tflite,
      ),
    );
  });

  test('requires a human network and rejects TFLite human style', () {
    GoModelCompatibility.validate(
      model: standard,
      engine: GoEngineProfile.builtIn,
      humanModel: human,
    );
    expect(
      () => GoModelCompatibility.validate(
        model: standard,
        engine: GoEngineProfile.builtIn,
        humanModel: standard,
      ),
      throwsArgumentError,
    );
    expect(
      () => GoModelCompatibility.validate(
        model: tflite,
        engine: const GoEngineProfile(
          id: 'tflite',
          name: 'TFLite',
          backend: GoEngineBackend.tflite,
        ),
        humanModel: human,
      ),
      throwsArgumentError,
    );
  });

  test('recognizes human metadata rather than a model name or extension', () {
    expect(
      inspectGoModel(modelEnvelope(metadataEncoder: 1)),
      GoModelKind.human,
    );
    expect(
      inspectGoModel(modelEnvelope(name: 'b18-human-but-no-metadata')),
      GoModelKind.standard,
    );
    expect(inspectGoModel(modelEnvelope(version: 8)), GoModelKind.standard);
    expect(
      inspectGoModel(modelEnvelope(version: 16, metadataEncoder: 1)),
      GoModelKind.human,
    );
    expect(
      inspectGoModel(modelEnvelope(prefix: '\n  \t')),
      GoModelKind.standard,
    );
  });

  test('rejects truncated gzip payloads and missing trailers', () {
    final bytes = modelEnvelope(metadataEncoder: 1);
    for (final cut in [1, 4, 8, bytes.length ~/ 2]) {
      expect(
        () =>
            inspectGoModel(Uint8List.sublistView(bytes, 0, bytes.length - cut)),
        throwsFormatException,
        reason: 'truncated $cut bytes',
      );
    }
  });

  test('rejects gzip checksum or uncompressed size corruption', () {
    final bytes = modelEnvelope();
    for (final offset in [bytes.length - 8, bytes.length - 4]) {
      final damaged = Uint8List.fromList(bytes);
      damaged[offset] ^= 0x01;
      expect(() => inspectGoModel(damaged), throwsFormatException);
    }
  });

  test('rejects a valid gzip file that is not a KataGo network', () {
    final bytes = GZipEncoder().encodeBytes(
      ascii.encode('<html>Not a model</html>'),
    );
    expect(() => inspectGoModel(bytes), throwsFormatException);
  });

  test('rejects unknown metadata and incomplete postprocess fields', () {
    expect(
      () => inspectGoModel(modelEnvelope(metadataEncoder: 2)),
      throwsFormatException,
    );
    for (final text in [
      'network\n15\n22\n19\n',
      'network\n15\n22\n19\n20\n20\n20\n20\n40\n0.25\n30\n1\n',
      'network\n13\n22\n19\n20\n20\nNaN\n20\n40\n0.25\n30\ntrunk\n',
    ]) {
      expect(
        () => inspectGoModel(GZipEncoder().encodeBytes(ascii.encode(text))),
        throwsFormatException,
      );
    }
  });

  test('rejects importing a standard network as a human network', () async {
    await expectLater(
      GoModelLibrary.install(
        name: 'Human label on a standard network',
        fileName: 'human.bin.gz',
        bytes: modelEnvelope(),
        kind: GoModelKind.human,
      ),
      throwsArgumentError,
    );
  });

  test('import preserves txt.gz format and detected human kind', () async {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('easyplay/katago');
    final writes = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          writes.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final bytes = modelEnvelope(metadataEncoder: 1);
    final installed = await GoModelLibrary.install(
      name: 'Human network',
      fileName: '/downloads/human.txt.gz',
      bytes: bytes,
    );
    expect(installed.fileName, 'human.txt.gz');
    expect(installed.kind, GoModelKind.human);
    expect(writes.single.method, 'storeModel');
    expect((writes.single.arguments as Map)['model'], bytes);
    expect((await GoModelLibrary.info(installed.id)).kind, GoModelKind.human);
  });
}
