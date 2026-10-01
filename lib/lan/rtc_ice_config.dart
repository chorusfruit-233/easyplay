/// Public services are best effort; browser ICE gathers from all listed URLs.
/// List order does not force the browser to prefer a particular provider.
const rtcDomesticStunUrls = [
  'stun:stun.miwifi.com:3478',
  'stun:stun.hitv.com:3478',
];
const rtcInternationalStunUrls = [
  'stun:stun.cloudflare.com:3478',
  'stun:stun.nextcloud.com:443',
];

List<Map<String, Object?>> rtcStunServers(Iterable<String> urls) => [
  for (final url in urls) {'urls': url},
];

/// Accept one URI per line, deduplicate, and cap public-service fan-out.
List<Map<String, Object?>> parseRtcStunServers(String input) {
  final urls = input.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toSet();
  if (urls.isEmpty || urls.length > 4) {
    throw const FormatException('请输入 1–4 个 STUN 地址，每行一个');
  }
  final pattern = RegExp(
    r'^(stun|stuns):([a-zA-Z0-9](?:[a-zA-Z0-9.\-]*[a-zA-Z0-9])?|\[[a-fA-F0-9:]+\])(?::([0-9]{1,5}))?$',
  );
  for (final url in urls) {
    final match = pattern.firstMatch(url);
    final port = match?.group(3);
    if (url.length > 256 ||
        match == null ||
        (port != null && (int.parse(port) < 1 || int.parse(port) > 65535))) {
      throw const FormatException(
        'STUN 地址无效，例如 stun:stun.miwifi.com:3478；端口应为 1–65535',
      );
    }
  }
  return rtcStunServers(urls);
}
