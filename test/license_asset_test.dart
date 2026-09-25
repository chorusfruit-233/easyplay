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
}
