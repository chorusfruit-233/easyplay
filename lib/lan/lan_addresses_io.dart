import 'dart:io';

const lanCanHost = true;

Future<List<String>> lanLocalAddresses() async {
  final addresses = <({String name, String address})>[];
  for (final network in await NetworkInterface.list(
    includeLoopback: false,
    includeLinkLocal: false,
  )) {
    for (final address in network.addresses) {
      if (address.type == InternetAddressType.IPv4) {
        addresses.add((name: network.name, address: address.address));
      }
    }
  }
  int rank(({String name, String address}) item) {
    final name = item.name.toLowerCase();
    if (name.startsWith('wlan') ||
        name.startsWith('wifi') ||
        name.startsWith('ap')) {
      return 0;
    }
    if (name.startsWith('eth') || name.startsWith('en')) return 1;
    if (RegExp(r'^(tun|tap|wg|tailscale|utun|ppp|clash)').hasMatch(name)) {
      return 3;
    }
    return 2;
  }

  addresses.sort((a, b) => rank(a).compareTo(rank(b)));
  return addresses.map((item) => item.address).toSet().toList();
}
