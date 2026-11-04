import 'dart:async';

/// A two-way channel of text messages to one other player, in order and
/// reliable while open: a WebRTC data channel in the app ([PeerLink]), a
/// pair of streams in tests ([LocalLink.pair]).
abstract class Link {
  Stream<String> get messages;

  /// Completes when messages can be sent.
  Future<void> get opened;

  /// Completes when either side closes or the connection is lost.
  Future<void> get closed;
  bool get isOpen;
  void send(String message);
  void close();
}

/// Both ends of a link inside one program.
class LocalLink implements Link {
  LocalLink._();

  static (LocalLink, LocalLink) pair() {
    final a = LocalLink._(), b = LocalLink._();
    a._other = b;
    b._other = a;
    a._opened.complete();
    b._opened.complete();
    return (a, b);
  }

  late LocalLink _other;
  final _messages = StreamController<String>.broadcast(sync: false);
  final _opened = Completer<void>();
  final _closed = Completer<void>();

  @override
  Stream<String> get messages => _messages.stream;
  @override
  Future<void> get opened => _opened.future;
  @override
  Future<void> get closed => _closed.future;
  @override
  bool get isOpen => !_closed.isCompleted;

  @override
  void send(String message) {
    if (isOpen && _other.isOpen) _other._messages.add(message);
  }

  @override
  void close() {
    if (_closed.isCompleted) return;
    _closed.complete();
    unawaited(_messages.close());
    _other.close();
  }
}
