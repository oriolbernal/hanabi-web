import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../game/coop.dart';
import '../net/online.dart';
import '../net/peer.dart';
import '../net/signal_code.dart';
import 'coop_screen.dart';
import 'palette.dart';
import 'settings.dart';
import 'strings.dart';

/// The host's room: how many play, which seats are friends and which are
/// bots, an invitation per friend (a QR code each way) and the button that
/// starts the game, whenever the host decides everyone is in.
class HostRoomScreen extends StatefulWidget {
  const HostRoomScreen({super.key});

  @override
  State<HostRoomScreen> createState() => _HostRoomScreenState();
}

class _HostRoomScreenState extends State<HostRoomScreen> {
  final _host = HostSession(Settings.playerName.value);
  late final StreamSubscription<void> _changes;

  /// Seats that wait for a friend, and the code inviting each one.
  final Set<int> _friends = {};
  final Map<int, String> _offers = {};
  final Map<int, PeerLink> _links = {};

  /// Seats whose friend's code is being read or connected.
  final Set<int> _connecting = {};

  @override
  void initState() {
    super.initState();
    _host.players = 2;
    _changes = _host.changes.listen((_) {
      if (!mounted) return;
      setState(() {
        // A friend who left: their seat goes back to a bot.
        for (final s in [..._friends]) {
          if (_links.containsKey(s) && !_host.guests.containsKey(s)) {
            _setBot(s);
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _changes.cancel();
    _host.close();
    super.dispose();
  }

  void _setPlayers(int n) => setState(() {
    for (var s = n; s < maxPlayers; s++) {
      _setBot(s);
    }
    _host.players = n;
    _host.sendLobby();
  });

  void _setBot(int seat) {
    _friends.remove(seat);
    _offers.remove(seat);
    _links.remove(seat);
    _connecting.remove(seat);
    if (_host.guests.containsKey(seat)) _host.free(seat);
  }

  Future<void> _invite(int seat) async {
    setState(() => _friends.add(seat));
    try {
      final (link, code) = await PeerLink.offer();
      if (!mounted || !_friends.contains(seat)) {
        link.close();
        return;
      }
      _host.seat(seat, link);
      setState(() {
        _links[seat] = link;
        _offers[seat] = code;
      });
    } on Object {
      if (mounted) _toast(tr.connectionFailed);
    }
  }

  Future<void> _readAnswer(int seat) async {
    final code = await readCode(context, title: tr.scanAnswer);
    final link = _links[seat];
    if (code == null || link == null || !mounted) return;
    setState(() => _connecting.add(seat));
    try {
      await link.accept(code);
      await link.opened.timeout(const Duration(seconds: 20));
      if (mounted) setState(() => _offers.remove(seat));
    } on FormatException {
      _toast(tr.notACode);
    } on Object {
      _toast(tr.connectionFailed);
      // A fresh invitation: the old one cannot be answered again.
      _setBot(seat);
      await _invite(seat);
    } finally {
      if (mounted) setState(() => _connecting.remove(seat));
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _start() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CoopScreen(players: _host.players, host: _host),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final anyGuest = _host.guests.isNotEmpty;
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, title: Text(tr.room)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(tr.playersHeader, style: headerStyle),
                const SizedBox(height: 8),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    for (var n = 2; n <= maxPlayers; n++)
                      ButtonSegment(value: n, label: Text('$n')),
                  ],
                  selected: {_host.players},
                  // Guests keep their seats: fewer players would drop one.
                  onSelectionChanged: (s) {
                    if (anyGuest && s.first < _host.players) return;
                    _setPlayers(s.first);
                  },
                ),
                const SizedBox(height: 16),
                _seatTile(
                  leading: const Icon(Icons.person),
                  title: '${_host.name} (${tr.you.toLowerCase()})',
                ),
                for (var s = 1; s < _host.players; s++) _seat(s),
                const SizedBox(height: 16),
                Text(
                  tr.keepAwake,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: textMuted, fontSize: 13),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _start,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      tr.startGame,
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr.startHelp,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _seat(int seat) {
    final guest = _host.guests[seat];
    final friend = _friends.contains(seat);
    final kind = SegmentedButton<bool>(
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: [
        ButtonSegment(value: false, label: Text(tr.seatBot)),
        ButtonSegment(value: true, label: Text(tr.seatFriend)),
      ],
      selected: {friend},
      onSelectionChanged: (s) => s.first
          ? _invite(seat)
          : setState(() {
              _setBot(seat);
              _host.sendLobby();
            }),
    );
    if (guest != null && guest.joined) {
      return _seatTile(
        leading: const Icon(Icons.check_circle, color: Colors.greenAccent),
        title: guest.name!,
        trailing: kind,
      );
    }
    if (!friend) {
      return _seatTile(
        leading: const Icon(Icons.smart_toy_outlined),
        title: botName(seat),
        trailing: kind,
      );
    }
    final offer = _offers[seat];
    return Column(
      children: [
        _seatTile(
          leading: const Icon(Icons.hourglass_empty),
          title: tr.waitingAnswer,
          trailing: kind,
        ),
        if (offer == null || _connecting.contains(seat))
          const Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          )
        else ...[
          Text(
            tr.inviteHelp,
            textAlign: TextAlign.center,
            style: const TextStyle(color: textMuted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          CodeCard(code: offer),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => _readAnswer(seat),
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(tr.scanAnswer),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _seatTile({
    required Widget leading,
    required String title,
    Widget? trailing,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        leading,
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// A guest's way in: read the host's code, show the answer, then wait in
/// the room until the host starts the game.
class JoinRoomScreen extends StatefulWidget {
  const JoinRoomScreen({super.key});

  @override
  State<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends State<JoinRoomScreen> {
  GuestSession? _guest;
  String? _answer;
  bool _working = false;
  bool _inGame = false;
  StreamSubscription<HostMessage>? _messages;

  @override
  void dispose() {
    _messages?.cancel();
    if (!_inGame) _guest?.close();
    super.dispose();
  }

  Future<void> _readOffer() async {
    final code = await readCode(context, title: tr.scanCode);
    if (code == null || !mounted) return;
    setState(() => _working = true);
    try {
      final (link, answer) = await PeerLink.answer(code);
      final guest = GuestSession(link, Settings.playerName.value);
      _messages = guest.messages.listen(_onMessage);
      link.closed.then((_) => _onClosed());
      setState(() {
        _guest = guest;
        _answer = answer;
      });
    } on FormatException {
      _toast(tr.notACode);
    } on Object {
      _toast(tr.connectionFailed);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _onMessage(HostMessage message) {
    if (!mounted) return;
    setState(() {});
    if (message is StartGame && !_inGame) _play();
  }

  Future<void> _play() async {
    final guest = _guest!;
    _inGame = true;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => CoopScreen(players: 2, guest: guest)),
    );
    _inGame = false;
    if (!mounted) return;
    // Left the game on their own (the link closes as the game screen goes,
    // before or after this): back to the menu.
    if (guest.leftByChoice) {
      Navigator.pop(context);
    } else {
      setState(() {});
    }
  }

  Future<void> _onClosed() async {
    if (!mounted || _inGame) return;
    if (_guest?.leftByChoice ?? false) {
      Navigator.pop(context);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: surface,
        content: Text(tr.hostLeft),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr.ok),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final guest = _guest;
    final table = guest?.table;
    final List<Widget> children;
    if (guest == null) {
      children = [
        Text(
          tr.joinHelp,
          textAlign: TextAlign.center,
          style: const TextStyle(color: textMuted),
        ),
        const SizedBox(height: 16),
        if (_working)
          const Center(child: CircularProgressIndicator())
        else
          FilledButton.icon(
            onPressed: _readOffer,
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(tr.scanCode),
          ),
      ];
    } else if (table == null) {
      children = [
        Text(
          tr.answerHelp,
          textAlign: TextAlign.center,
          style: const TextStyle(color: textMuted),
        ),
        const SizedBox(height: 12),
        CodeCard(code: _answer!),
        const SizedBox(height: 12),
        Text(
          tr.connecting,
          textAlign: TextAlign.center,
          style: const TextStyle(color: textMuted),
        ),
      ];
    } else {
      children = [
        Text(tr.playersHeader, style: headerStyle),
        const SizedBox(height: 8),
        for (var s = 0; s < table.players; s++)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  table.bots.contains(s)
                      ? Icons.smart_toy_outlined
                      : Icons.person,
                ),
                const SizedBox(width: 12),
                Text(
                  s == guest.seat
                      ? '${table.names[s]} (${tr.you.toLowerCase()})'
                      : table.names[s],
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 12),
        Text(
          tr.waitingHost,
          textAlign: TextAlign.center,
          style: const TextStyle(color: textMuted),
        ),
        const SizedBox(height: 12),
        Text(
          tr.keepAwake,
          textAlign: TextAlign.center,
          style: const TextStyle(color: textMuted, fontSize: 13),
        ),
      ];
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(tr.joinRoom),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

const headerStyle = TextStyle(
  color: textMuted,
  fontSize: 12,
  letterSpacing: 2,
  fontWeight: FontWeight.w600,
);

/// A connection code as a QR code, with a button to copy it as text for
/// friends who are not in the same room.
class CodeCard extends StatelessWidget {
  const CodeCard({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(8),
            child: QrImageView(
              data: code,
              size: 240,
              backgroundColor: Colors.white,
              semanticsLabel: tr.copyCode,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: code));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(tr.codeCopied)));
          },
          icon: const Icon(Icons.copy),
          label: Text(tr.copyCode),
        ),
      ],
    );
  }
}

/// Reads a connection code with the camera, or pasted as text; null if
/// cancelled.
Future<String?> readCode(BuildContext context, {required String title}) =>
    Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => _CodeReader(title: title)),
    );

class _CodeReader extends StatefulWidget {
  const _CodeReader({required this.title});

  final String title;

  @override
  State<_CodeReader> createState() => _CodeReaderState();
}

class _CodeReaderState extends State<_CodeReader> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  final _pasted = TextEditingController();
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _pasted.dispose();
    super.dispose();
  }

  void _finish(String text) {
    if (_done) return;
    if (SignalCode.parse(text) == null) {
      setState(() => _error = tr.notACode);
      return;
    }
    _done = true;
    Navigator.pop(context, text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.title),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  tr.pointCamera,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: textMuted),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: MobileScanner(
                      controller: _controller,
                      onDetect: (capture) {
                        for (final b in capture.barcodes) {
                          final text = b.rawValue;
                          if (text != null) _finish(text);
                        }
                      },
                      errorBuilder: (context, error) => ColoredBox(
                        color: surface,
                        child: Center(
                          child: Icon(
                            Icons.no_photography_outlined,
                            size: 48,
                            color: textMuted.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _pasted,
                  decoration: InputDecoration(
                    labelText: tr.pasteCode,
                    errorText: _error,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.check),
                      onPressed: () => _finish(_pasted.text),
                    ),
                  ),
                  onSubmitted: _finish,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
