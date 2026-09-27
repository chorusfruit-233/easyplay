class LanEndpoint {
  const LanEndpoint({required this.host, required this.port, this.players = 0});
  final String host;
  final int port;
  final int players;
  String get address => '$host:$port';
}

class LanSubnet {
  static Set<String> candidates(
    Iterable<({String name, String address})> interfaces,
  ) {
    final result = <String>{};
    for (final interface in interfaces) {
      if (RegExp(
        r'^(tun|tap|wg|tailscale|utun|ppp|clash)',
        caseSensitive: false,
      ).hasMatch(interface.name)) {
        continue;
      }
      result.addAll(hosts(interface.address, 24));
    }
    return result;
  }

  static List<String> hosts(String address, int prefixLength) =>
      _hosts(address, prefixLength);

  static List<String> _hosts(String address, int prefixLength) {
    if (prefixLength < 0 || prefixLength > 32) {
      throw ArgumentError.value(prefixLength, 'prefixLength');
    }
    final octets = address.split('.').map(int.tryParse).toList();
    if (octets.length != 4 ||
        octets.any((v) => v == null || v < 0 || v > 255)) {
      throw const FormatException('无效的 IPv4 地址');
    }
    final ip = octets.fold<int>(0, (v, o) => (v << 8) | o!);
    final mask = prefixLength == 0
        ? 0
        : (0xffffffff << (32 - prefixLength)) & 0xffffffff;
    final network = ip & mask;
    final count = 1 << (32 - prefixLength);
    final first = prefixLength >= 31 ? 0 : 1;
    final last = prefixLength >= 31 ? count - 1 : count - 2;
    return [
      for (var offset = first; offset <= last; offset++)
        [
          24,
          16,
          8,
          0,
        ].map((shift) => (network + offset) >> shift & 255).join('.'),
    ];
  }
}

Future<List<LanEndpoint>> scanLan({
  Duration timeout = const Duration(milliseconds: 250),
  int port = 8080,
  int concurrency = 64,
}) async => const [];

Future<List<LanEndpoint>> scanLanTargets(
  Iterable<String> addresses, {
  Duration timeout = const Duration(milliseconds: 250),
  int port = 8080,
  int concurrency = 64,
}) async => const [];
