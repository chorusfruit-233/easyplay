import 'package:easyplay/lan/rtc_ice_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('custom STUN supports multiple providers, ports and IPv6', () {
    final servers = parseRtcStunServers(
      'stun:example.cn:3478\nstuns:example.org:5349\nstun:[2001:db8::1]:3478\nstun:example.cn:3478',
    );
    expect(servers.length, 3);
    expect(servers.last['urls'], 'stun:[2001:db8::1]:3478');
  });
  test('rejects malformed, empty, credential and excessive STUN input', () {
    for (final input in [
      '',
      'https://example.com',
      'turn:example.com',
      'stun:',
      'stun:user:password@example.com',
      'stun:example.com:0',
      'stun:example.com:65536',
      'stun:example.com/path',
      'stun:one stun:two stun:three stun:four stun:five',
    ]) {
      expect(
        () => parseRtcStunServers(input),
        throwsFormatException,
        reason: input,
      );
    }
  });
}
