import 'dart:convert';

/// What one browser must tell the other to open a WebRTC data channel,
/// small enough for a QR code that a phone reads at a glance (about 200
/// characters instead of the 800 of the full SDP).
///
/// Only the fields a data channel needs travel: the ICE user name and
/// password, the DTLS certificate fingerprint, the DTLS role, the media id
/// and the UDP candidates. [sdp] rebuilds a description every browser
/// accepts from them.
///
/// As text: `H1o,<ufrag>,<pwd>,<fingerprint in base64>,<setup>,<mid>,<candidates>`
/// with `o` (offer) or `a` (answer) and the candidates as
/// `<ip> <port> <type> <priority>`, separated by `;`.
class SignalCode {
  SignalCode({
    required this.offer,
    required this.ufrag,
    required this.pwd,
    required this.fingerprint,
    required this.setup,
    required this.mid,
    required this.candidates,
  });

  /// Reads the fields from a full SDP; null when one is missing.
  static SignalCode? fromSdp(String sdp, {required bool offer}) {
    String? field(String name) {
      for (final line in LineSplitter.split(sdp)) {
        if (line.startsWith('a=$name:')) {
          return line.substring(name.length + 3).trim();
        }
      }
      return null;
    }

    final ufrag = field('ice-ufrag');
    final pwd = field('ice-pwd');
    final fp = field('fingerprint');
    final setup = field('setup');
    final mid = field('mid');
    if (ufrag == null || pwd == null || fp == null || setup == null) {
      return null;
    }
    if (mid == null || !fp.toLowerCase().startsWith('sha-256 ')) return null;
    final candidates = <String>[];
    for (final line in LineSplitter.split(sdp)) {
      if (!line.startsWith('a=candidate:')) continue;
      // foundation component transport priority address port typ type ...
      final parts = line.substring(12).split(' ');
      if (parts.length < 8 || parts[2].toLowerCase() != 'udp') continue;
      if (parts[1] != '1') continue;
      candidates.add('${parts[4]} ${parts[5]} ${parts[7]} ${parts[3]}');
    }
    final hex = fp.substring(8).split(':');
    return SignalCode(
      offer: offer,
      ufrag: ufrag,
      pwd: pwd,
      fingerprint: [for (final h in hex) int.parse(h, radix: 16)],
      setup: setup,
      mid: mid,
      candidates: candidates.take(6).toList(),
    );
  }

  /// Reads a code written by [text]; null when it is not one.
  static SignalCode? parse(String text) {
    final parts = text.trim().split(',');
    if (parts.length != 7 || !parts[0].startsWith('H1')) return null;
    if (parts[0] != 'H1o' && parts[0] != 'H1a') return null;
    try {
      final fingerprint = base64.decode(parts[3]);
      if (fingerprint.length != 32) return null;
      final candidates = parts[6].isEmpty ? <String>[] : parts[6].split(';');
      for (final c in candidates) {
        if (c.split(' ').length != 4) return null;
      }
      return SignalCode(
        offer: parts[0] == 'H1o',
        ufrag: parts[1],
        pwd: parts[2],
        fingerprint: fingerprint,
        setup: parts[4],
        mid: parts[5],
        candidates: candidates,
      );
    } on FormatException {
      return null;
    }
  }

  /// Whether it opens a connection (the host's) or answers one (a guest's).
  final bool offer;
  final String ufrag;
  final String pwd;

  /// SHA-256 of the DTLS certificate, 32 bytes.
  final List<int> fingerprint;
  final String setup;
  final String mid;

  /// `<ip> <port> <type> <priority>` each.
  final List<String> candidates;

  String get text => [
    offer ? 'H1o' : 'H1a',
    ufrag,
    pwd,
    base64.encode(fingerprint),
    setup,
    mid,
    candidates.join(';'),
  ].join(',');

  /// A session description with these fields, for a data channel only.
  String get sdp {
    final hex = [
      for (final b in fingerprint)
        b.toRadixString(16).padLeft(2, '0').toUpperCase(),
    ].join(':');
    var i = 0;
    return [
      'v=0',
      'o=- ${offer ? 1 : 2} 2 IN IP4 127.0.0.1',
      's=-',
      't=0 0',
      'a=group:BUNDLE $mid',
      'a=msid-semantic: WMS',
      'm=application 9 UDP/DTLS/SCTP webrtc-datachannel',
      'c=IN IP4 0.0.0.0',
      'a=ice-ufrag:$ufrag',
      'a=ice-pwd:$pwd',
      'a=ice-options:trickle',
      'a=fingerprint:sha-256 $hex',
      'a=setup:$setup',
      'a=mid:$mid',
      'a=sctp-port:5000',
      'a=max-message-size:262144',
      for (final c in candidates)
        switch (c.split(' ')) {
          [final ip, final port, final type, final priority] =>
            'a=candidate:${++i} 1 udp $priority $ip $port typ $type',
          _ => throw StateError('bad candidate $c'),
        },
      '',
    ].join('\r\n');
  }
}
