import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class _LicenseEntry {
  final String name;
  final String asset;
  const _LicenseEntry(this.name, this.asset);
}

const _licenseEntries = <_LicenseEntry>[
  _LicenseEntry('EasyPlay（本项目）', 'assets/licenses/GPL-3.0.txt'),
  _LicenseEntry('KataGo', 'assets/katago/KATAGO-LICENSE.txt'),
  _LicenseEntry('KataGo 神经网络模型', 'assets/katago/MODEL-LICENSE.txt'),
  _LicenseEntry('Eigen', 'assets/katago/EIGEN-LICENSE.txt'),
  _LicenseEntry('Apache License 2.0', 'assets/katago/COPYING.APACHE'),
  _LicenseEntry('BSD License', 'assets/katago/COPYING.BSD'),
  _LicenseEntry('GPL License', 'assets/katago/COPYING.GPL'),
  _LicenseEntry('LGPL License', 'assets/katago/COPYING.LGPL'),
  _LicenseEntry('Minpack License', 'assets/katago/COPYING.MINPACK'),
  _LicenseEntry('MPL 2.0', 'assets/katago/COPYING.MPL2'),
  _LicenseEntry('第三方组件许可证说明', 'assets/katago/COPYING.README'),
  _LicenseEntry(
    'clblast',
    'assets/katago/THIRD-PARTY-LICENSES/clblast/LICENSE',
  ),
  _LicenseEntry(
    'filesystem',
    'assets/katago/THIRD-PARTY-LICENSES/filesystem-1.5.8/LICENSE',
  ),
  _LicenseEntry(
    'half',
    'assets/katago/THIRD-PARTY-LICENSES/half-2.2.0/LICENSE.txt',
  ),
  _LicenseEntry(
    'cpp-httplib',
    'assets/katago/THIRD-PARTY-LICENSES/httplib/LICENSE',
  ),
  _LicenseEntry(
    'tclap',
    'assets/katago/THIRD-PARTY-LICENSES/tclap-1.2.5/COPYING',
  ),
  _LicenseEntry(
    'KataGo CoreML',
    'assets/katago/THIRD-PARTY-LICENSES/katagocoreml/LICENSE',
  ),
  _LicenseEntry(
    'KataGo CoreML NOTICE',
    'assets/katago/THIRD-PARTY-LICENSES/katagocoreml/NOTICE',
  ),
  _LicenseEntry(
    'macOS components',
    'assets/katago/THIRD-PARTY-LICENSES/macos/LICENSE',
  ),
  _LicenseEntry(
    'Mozilla CA certificates',
    'assets/katago/THIRD-PARTY-LICENSES/mozilla-cacerts/LICENSE',
  ),
];

class AboutLicensesPage extends StatelessWidget {
  const AboutLicensesPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('关于与许可证')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.blur_on)),
            title: const Text('EasyPlay'),
            subtitle: const Text('围棋 · 本地对局\nGPL-3.0 授权，使用 KataGo 及多个开源组件'),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '开源许可证',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 8),
        ..._licenseEntries.map(
          (entry) => Card(
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(entry.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _LicenseTextPage(entry: entry),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () =>
              showLicensePage(context: context, applicationName: 'EasyPlay'),
          icon: const Icon(Icons.article_outlined),
          label: const Text('查看 Flutter 依赖许可证'),
        ),
      ],
    ),
  );
}

class _LicenseTextPage extends StatelessWidget {
  final _LicenseEntry entry;
  const _LicenseTextPage({required this.entry});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(entry.name)),
    body: FutureBuilder<String>(
      future: rootBundle.loadString(entry.asset),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('许可证文件读取失败'));
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return SelectionArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SelectableText(
              snapshot.data!,
              style: const TextStyle(fontFamily: 'monospace', height: 1.45),
            ),
          ),
        );
      },
    ),
  );
}
