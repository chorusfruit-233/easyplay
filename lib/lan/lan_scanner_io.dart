import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'lan_ports.dart';
import 'lan_protocol.dart';

class LanEndpoint {
  const LanEndpoint({
    required this.host,
    required this.port,
    this.players = 0,
    this.game = 'go',
    this.variant,
  });
  final String host;
  final int port;
  final int players;
  final String game;
  final String? variant;
  String get address => '$host:$port';
}

class LanSubnet {
  /// Ignore virtual tunnels; scanning a VPN's /24 is slow and cannot find a
  /// Wi-Fi room. Manual entry remains available for unusual network layouts.
  static Set<String> candidates(
    Iterable<({String name, String address})> interfaces,
  ) {
    final hosts = <String>{};
    for (final interface in interfaces) {
      if (RegExp(
        r'^(tun|tap|wg|tailscale|utun|ppp|clash)',
        caseSensitive: false,
      ).hasMatch(interface.name)) {
        continue;
      }
      hosts.addAll(LanSubnet.hosts(interface.address, 24));
    }
    return hosts;
  }

  static List<String> hosts(String address, int prefixLength) {
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
  int port = lanDefaultPort,
  int concurrency = 128,
}) async {
  final interfaces = <({String name, String address})>[];
  for (final interface in await NetworkInterface.list(
    includeLoopback: false,
    includeLinkLocal: false,
  )) {
    for (final address in interface.addresses.where(
      (a) => a.type == InternetAddressType.IPv4,
    )) {
      interfaces.add((name: interface.name, address: address.address));
    }
  }
  return scanLanTargets(
    LanSubnet.candidates(interfaces),
    timeout: timeout,
    ports: lanDiscoveryPorts(port),
    concurrency: concurrency,
  );
}

/// Also used by tests with a fixed host set, independent of the machine's NICs.
Future<List<LanEndpoint>> scanLanTargets(
  Iterable<String> addresses, {
  Duration timeout = const Duration(milliseconds: 250),
  int port = lanDefaultPort,
  Iterable<int>? ports,
  int concurrency = 64,
}) async {
  if (concurrency < 1) throw ArgumentError.value(concurrency, 'concurrency');
  final scanPorts = (ports ?? [port]).toSet().toList();
  if (scanPorts.any((candidate) => candidate < 1 || candidate > 65535)) {
    throw ArgumentError.value(scanPorts, 'ports');
  }
  final results = <LanEndpoint>[];
  final queue = [
    for (final address in addresses.toSet())
      for (final candidate in scanPorts) (host: address, port: candidate),
  ];
  var cursor = 0;
  Future<void> worker() async {
    while (true) {
      final index = cursor++;
      if (index >= queue.length) return;
      final target = queue[index];
      final endpoint = await _probe(target.host, target.port, timeout);
      if (endpoint != null) results.add(endpoint);
    }
  }

  await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
  results.sort((a, b) => a.address.compareTo(b.address));
  return results;
}

Future<LanEndpoint?> _probe(String host, int port, Duration timeout) async {
  Socket? socket;
  try {
    socket = await Socket.connect(host, port, timeout: timeout);
    socket.write(
      'GET /easyplay/probe HTTP/1.1\r\nHost: $host\r\nConnection: close\r\n\r\n',
    );
    await socket.flush();
    final bytes = await socket
        .fold<List<int>>([], (all, chunk) {
          if (all.length + chunk.length > 4096) {
            throw const FormatException('探针响应过大');
          }
          return all..addAll(chunk);
        })
        .timeout(timeout);
    final response = utf8.decode(bytes, allowMalformed: true);
    final body = response.split('\r\n\r\n').skip(1).join('\r\n\r\n');
    if (!response.startsWith('HTTP/1.1 200') &&
        !response.startsWith('HTTP/1.0 200')) {
      return null;
    }
    final json = jsonDecode(body);
    if (json is! Map || json['app'] != 'easyplay') return null;
    if (json['game'] == 'xiangqi') {
      LanMessage.validateXiangqiConfig(Map<String, Object?>.from(json));
    }
    if (json['game'] == 'gomoku') {
      if (json['version'] != lanProtocolVersion) return null;
      LanMessage.validateGomokuConfig(Map<String, Object?>.from(json));
    }
    return LanEndpoint(
      host: host,
      port: port,
      players: json['players'] is int ? json['players'] as int : 0,
      game: json['game'] is String ? json['game'] as String : 'go',
      variant: json['variant'] is String ? json['variant'] as String : null,
    );
  } catch (_) {
    return null;
  } finally {
    await socket?.close();
  }
}
