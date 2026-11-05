import 'dart:async';
import 'dart:convert';

import '../game/card.dart';
import '../game/coop.dart';
import 'link.dart';

/// A bot's name by its seat (1 to 3), the same on every phone.
String botName(int seat) => const ['Aiko', 'Ren', 'Sora'][seat - 1];

/// Who sits where: everyone's name and which seats the bots take.
class Seating {
  Seating({required this.players, required this.names, required this.bots});

  final int players;

  /// One per seat; seat 0 is the host.
  final List<String> names;
  final Set<int> bots;

  Map<String, dynamic> toJson() => {
    'players': players,
    'names': names,
    'bots': bots.toList()..sort(),
  };

  static Seating fromJson(Map<String, dynamic> json) {
    final players = json['players'] as int;
    final names = (json['names'] as List).cast<String>();
    final bots = (json['bots'] as List).cast<int>().toSet();
    if (players < 2 || players > maxPlayers || names.length != players) {
      throw const FormatException('bad table');
    }
    if (bots.any((s) => s <= 0 || s >= players)) {
      throw const FormatException('bad bots');
    }
    return Seating(players: players, names: names, bots: bots);
  }
}

/// What the host tells a guest.
sealed class HostMessage {
  static HostMessage parse(String text) {
    final json = jsonDecode(text) as Map<String, dynamic>;
    return switch (json['t']) {
      'welcome' => Welcome(json['seat'] as int),
      'lobby' => LobbyUpdate(Seating.fromJson(json)),
      'start' => StartGame(
        Seating.fromJson(json),
        parseDeck(json['deck'] as String),
        first: json['first'] as int? ?? 0,
      ),
      'move' => MoveMade(json['n'] as int, CoopMove.parse(json['m'] as String)),
      'bot' => BotTakesOver(json['seat'] as int),
      _ => throw FormatException('unknown message ${json['t']}'),
    };
  }
}

/// The guest's seat.
class Welcome extends HostMessage {
  Welcome(this.seat);
  final int seat;
}

/// Who is in the room while the host prepares the game, or after it.
class LobbyUpdate extends HostMessage {
  LobbyUpdate(this.table);
  final Seating table;
}

/// A new game: who sits where and the deck, in the order it is dealt.
class StartGame extends HostMessage {
  StartGame(this.table, this.deck, {this.first = 0});
  final Seating table;
  final List<GameCard> deck;

  /// The seat that plays first.
  final int first;
}

/// Move number [n] of the game (0 is the first), whoever made it.
class MoveMade extends HostMessage {
  MoveMade(this.n, this.move);
  final int n;
  final CoopMove move;
}

/// A guest left; a bot plays their seat from now on.
class BotTakesOver extends HostMessage {
  BotTakesOver(this.seat);
  final int seat;
}

/// A guest at the host's table: their link and, once they said hello,
/// their name.
class GuestSeat {
  GuestSeat(this.link);
  final Link link;
  String? name;

  bool get joined => name != null;
}

/// A move a guest sent: theirs, as move number [n] of the game.
typedef GuestMove = ({int seat, int n, CoopMove move});

/// The host's room. The host sits in seat 0 and decides everything: who
/// sits where, the deck, the order of the moves (each one is checked and
/// sent to every guest) and the bots' moves, which run on the host's
/// phone. Guests only send their own moves.
class HostSession {
  HostSession(this.name);

  /// The host's name.
  final String name;

  /// Players at the table, host and bots included.
  int players = 2;

  /// Guests by seat (1 to 3), including those still being invited.
  final Map<int, GuestSeat> guests = {};

  /// Seats the host wants a person in; the others take bots.
  final Set<int> invited = {};

  final _changes = StreamController<void>.broadcast();
  final _moves = StreamController<GuestMove>.broadcast();
  final _left = StreamController<int>.broadcast();

  /// Something in the room changed: a guest joined or left.
  Stream<void> get changes => _changes.stream;

  /// Moves sent by guests, unchecked.
  Stream<GuestMove> get moves => _moves.stream;

  /// Seats whose guest left.
  Stream<int> get left => _left.stream;

  bool _playing = false;

  /// Seats a guest is sitting in.
  Iterable<int> get joined =>
      guests.entries.where((e) => e.value.joined).map((e) => e.key);

  /// Who sits where now: guests who joined, bots everywhere else.
  Seating get table => Seating(
    players: players,
    names: [
      name,
      for (var s = 1; s < players; s++) guests[s]?.name ?? botName(s),
    ],
    bots: {
      for (var s = 1; s < players; s++)
        if (!(guests[s]?.joined ?? false)) s,
    },
  );

  /// Puts [link] in [seat], replacing whoever was invited there.
  void seat(int seat, Link link) {
    guests.remove(seat)?.link.close();
    final guest = GuestSeat(link);
    guests[seat] = guest;
    link.messages.listen((text) => _onMessage(seat, guest, text));
    link.closed.then((_) {
      if (guests[seat] != guest) return;
      guests.remove(seat);
      if (guest.joined) {
        if (_playing) _broadcast({'t': 'bot', 'seat': seat});
        _left.add(seat);
        if (!_playing) sendLobby();
      }
      _changes.add(null);
    });
  }

  /// Drops the guest or invitation in [seat].
  void free(int seat) {
    guests.remove(seat)?.link.close();
    sendLobby();
    _changes.add(null);
  }

  void _onMessage(int seat, GuestSeat guest, String text) {
    try {
      final json = jsonDecode(text) as Map<String, dynamic>;
      switch (json['t']) {
        case 'hello':
          final name = switch (json['name']) {
            final String n => n.trim(),
            _ => '',
          };
          guest.name = name.isEmpty
              ? '?'
              : name.substring(0, name.length.clamp(0, 16));
          guest.link.send(jsonEncode({'t': 'welcome', 'seat': seat}));
          sendLobby();
          _changes.add(null);
        case 'move':
          _moves.add((
            seat: seat,
            n: json['n'] as int,
            move: CoopMove.parse(json['m'] as String),
          ));
      }
    } on Object {
      // A garbled or hostile message changes nothing.
    }
  }

  void _broadcast(Map<String, dynamic> message) {
    final text = jsonEncode(message);
    for (final s in joined) {
      guests[s]!.link.send(text);
    }
  }

  /// Tells the guests who is in the room; also how they learn that the
  /// host left a game and is back in the room.
  void sendLobby() {
    _playing = false;
    _broadcast({'t': 'lobby', ...table.toJson()});
  }

  /// Starts a game with [deck], [first] playing first; returns who sits
  /// where.
  Seating start(List<GameCard> deck, {int first = 0}) {
    _playing = true;
    final t = table;
    _broadcast({
      't': 'start',
      ...t.toJson(),
      'deck': deckText(deck),
      'first': first,
    });
    return t;
  }

  /// Sends move number [n] of the game to every guest.
  void sendMove(int n, CoopMove move) =>
      _broadcast({'t': 'move', 'n': n, 'm': move.text});

  void close() {
    for (final g in guests.values) {
      g.link.close();
    }
    guests.clear();
    _changes.close();
    _moves.close();
    _left.close();
  }
}

/// A guest's side of the room: one link to the host.
class GuestSession {
  GuestSession(this.link, this.name) {
    link.messages.listen(_onMessage);
    link.opened.then(
      (_) => link.send(jsonEncode({'t': 'hello', 'name': name})),
    );
  }

  final Link link;
  final String name;

  /// This guest's seat, once the host has said so.
  int? seat;

  /// The latest room and game the host announced, and the moves of that
  /// game so far.
  Seating? table;
  StartGame? game;
  final List<CoopMove> moves = [];

  final _messages = StreamController<HostMessage>.broadcast();

  /// Everything the host says, in order.
  Stream<HostMessage> get messages => _messages.stream;

  Future<void> get closed => link.closed;

  void _onMessage(String text) {
    final HostMessage message;
    try {
      message = HostMessage.parse(text);
    } on Object {
      return;
    }
    switch (message) {
      case Welcome(seat: final s):
        seat = s;
      case LobbyUpdate(table: final t):
        table = t;
        game = null;
        moves.clear();
      case StartGame():
        table = message.table;
        game = message;
        moves.clear();
      case MoveMade(:final n, :final move):
        if (n != moves.length) return;
        moves.add(move);
      case BotTakesOver(seat: final s):
        game?.table.bots.add(s);
    }
    _messages.add(message);
  }

  /// Sends this guest's move, as move number [n] of the game.
  void sendMove(int n, CoopMove move) =>
      link.send(jsonEncode({'t': 'move', 'n': n, 'm': move.text}));

  /// Whether this guest left, rather than the host closing the room.
  bool leftByChoice = false;

  void close() {
    leftByChoice = true;
    link.close();
    _messages.close();
  }
}
