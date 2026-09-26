import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('GPL-3.0 许可证资源可加载且为完整官方原文', () async {
    final text = await rootBundle.loadString('assets/licenses/GPL-3.0.txt');
    expect(text, contains('GNU GENERAL PUBLIC LICENSE'));
    expect(text, contains('Version 3, 29 June 2007'));
    // 官方原文以 why-not-lgpl 链接收尾，确认没有被截断。
    expect(text, contains('why-not-lgpl.html'));
    expect(text.length, 35149);
  });

  test('KataGo 第三方组件许可证资源均被打包', () async {
    const assets = [
      'assets/katago/THIRD-PARTY-LICENSES/clblast/LICENSE',
      'assets/katago/THIRD-PARTY-LICENSES/filesystem-1.5.8/LICENSE',
      'assets/katago/THIRD-PARTY-LICENSES/half-2.2.0/LICENSE.txt',
      'assets/katago/THIRD-PARTY-LICENSES/httplib/LICENSE',
      'assets/katago/THIRD-PARTY-LICENSES/katagocoreml/LICENSE',
      'assets/katago/THIRD-PARTY-LICENSES/katagocoreml/NOTICE',
      'assets/katago/THIRD-PARTY-LICENSES/katagocoreml/vendor/deps/FP16/LICENSE',
      'assets/katago/THIRD-PARTY-LICENSES/katagocoreml/vendor/mlmodel/LICENSE.txt',
      'assets/katago/THIRD-PARTY-LICENSES/katagocoreml/vendor/mlmodel/format/LICENSE.txt',
      'assets/katago/THIRD-PARTY-LICENSES/katagocoreml/vendor/modelpackage/LICENSE.txt',
      'assets/katago/THIRD-PARTY-LICENSES/macos/LICENSE',
      'assets/katago/THIRD-PARTY-LICENSES/mozilla-cacerts/LICENSE',
      'assets/katago/THIRD-PARTY-LICENSES/tclap-1.2.5/COPYING',
    ];

    for (final asset in assets) {
      expect(await rootBundle.loadString(asset), isNotEmpty, reason: asset);
    }
  });
}
