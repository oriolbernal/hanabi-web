import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart';

import 'link.dart';
import 'signal_code.dart';

/// A WebRTC data channel to one other player's browser, set up by hand: the
/// host's offer and the guest's answer travel as short texts ([SignalCode]),
/// shown as QR codes or pasted, so no server is needed. The only outside
/// help is Google's public STUN server, which tells each browser its public
/// address. Traffic between the two browsers is always encrypted (DTLS).
class PeerLink implements Link {
  PeerLink._(this._pc) {
    _pc.onconnectionstatechange = ((Event _) {
      final state = _pc.connectionState;
      if (state == 'failed' || state == 'closed') close();
    }).toJS;
  }

  final RTCPeerConnection _pc;
  RTCDataChannel? _channel;
  final _messages = StreamController<String>.broadcast();
  final _opened = Completer<void>();
  final _closed = Completer<void>();

  static RTCPeerConnection _connection() => RTCPeerConnection(
    RTCConfiguration(
      iceServers: [RTCIceServer(urls: 'stun:stun.l.google.com:19302'.toJS)]
          .toJS,
    ),
  );

  /// The host's side: a new link and the code to show the guest.
  static Future<(PeerLink, String)> offer() async {
    final pc = _connection();
    final link = PeerLink._(pc);
    link._attach(pc.createDataChannel('hanabi'));
    final offer = (await pc.createOffer().toDart)!;
    await pc
        .setLocalDescription(
          RTCLocalSessionDescriptionInit(type: offer.type, sdp: offer.sdp),
        )
        .toDart;
    return (link, await link._code(offer: true));
  }

  /// The guest's side: from the host's code, a link and the code to show
  /// back. Throws [FormatException] when [code] is not a host's code.
  static Future<(PeerLink, String)> answer(String code) async {
    final signal = SignalCode.parse(code);
    if (signal == null || !signal.offer) {
      throw const FormatException('not an offer');
    }
    final pc = _connection();
    final link = PeerLink._(pc);
    pc.ondatachannel = ((RTCDataChannelEvent e) => link._attach(
      e.channel,
    )).toJS;
    await pc
        .setRemoteDescription(
          RTCSessionDescriptionInit(type: 'offer', sdp: signal.sdp),
        )
        .toDart;
    final answer = (await pc.createAnswer().toDart)!;
    await pc
        .setLocalDescription(
          RTCLocalSessionDescriptionInit(type: answer.type, sdp: answer.sdp),
        )
        .toDart;
    return (link, await link._code(offer: false));
  }

  /// The host's side, with the guest's code. Throws [FormatException] when
  /// [code] is not a guest's code.
  Future<void> accept(String code) async {
    final signal = SignalCode.parse(code);
    if (signal == null || signal.offer) {
      throw const FormatException('not an answer');
    }
    await _pc
        .setRemoteDescription(
          RTCSessionDescriptionInit(type: 'answer', sdp: signal.sdp),
        )
        .toDart;
  }

  /// Waits for the candidates (at most 3 s: the STUN answer can be slow),
  /// then shortens the description.
  Future<String> _code({required bool offer}) async {
    if (_pc.iceGatheringState != 'complete') {
      final done = Completer<void>();
      _pc.onicegatheringstatechange = ((Event _) {
        if (_pc.iceGatheringState == 'complete' && !done.isCompleted) {
          done.complete();
        }
      }).toJS;
      await done.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    }
    final sdp = _pc.localDescription!.sdp;
    final code = SignalCode.fromSdp(sdp, offer: offer);
    if (code == null) throw StateError('unexpected description: $sdp');
    return code.text;
  }

  void _attach(RTCDataChannel channel) {
    _channel = channel;
    channel.onopen = ((Event _) {
      if (!_opened.isCompleted) _opened.complete();
    }).toJS;
    channel.onclose = ((Event _) => close()).toJS;
    channel.onmessage = ((MessageEvent e) {
      final data = e.data;
      if (data.isA<JSString>()) _messages.add((data as JSString).toDart);
    }).toJS;
  }

  @override
  Stream<String> get messages => _messages.stream;

  @override
  Future<void> get opened => _opened.future;

  @override
  Future<void> get closed => _closed.future;

  @override
  bool get isOpen => _channel?.readyState == 'open';

  @override
  void send(String message) {
    if (isOpen) _channel!.send(message.toJS);
  }

  @override
  void close() {
    if (_closed.isCompleted) return;
    _channel?.close();
    _pc.close();
    _closed.complete();
    unawaited(_messages.close());
  }
}
