import 'dart:math';

import 'card.dart';
import 'fireworks.dart';
import 'game.dart';

/// The most players a cooperative game takes.
const maxPlayers = 4;

/// What a player does on their turn in a cooperative game.
///
/// As text (move log, online games): `p3` plays card 3 (a joker above 1
/// adds its pile, `p3B`), `d0` discards card 0, `h2:5` / `h1:R` tells
/// player 2 about the 5s / player 1 about the reds.
sealed class CoopMove {
  CoopMove();

  /// Reads a move written by [text]; throws [FormatException] on anything
  /// else.
  factory CoopMove.parse(String text) {
    CardColor color(String symbol) => CardColor.values.firstWhere(
      (c) => c.symbol == symbol,
      orElse: () => throw FormatException('no color $symbol'),
    );
    final match = RegExp(
      r'^(?:p(\d)([RGBYW])?|d(\d)|h(\d):(?:([1-5])|([RGBYW*])))$',
    ).firstMatch(text);
    if (match == null) throw FormatException('not a move: $text');
    if (match[1] != null) {
      return CoopPlay(
        int.parse(match[1]!),
        target: match[2] == null ? null : color(match[2]!),
      );
    }
    if (match[3] != null) return CoopDiscard(int.parse(match[3]!));
    final to = int.parse(match[4]!);
    return CoopHint(
      to,
      match[5] != null
          ? NumberHint(int.parse(match[5]!))
          : ColorHint(color(match[6]!)),
    );
  }

  String get text => switch (this) {
    CoopPlay(:final index, :final target) => 'p$index${target?.symbol ?? ''}',
    CoopDiscard(:final index) => 'd$index',
    CoopHint(:final to, hint: NumberHint(:final number)) => 'h$to:$number',
    CoopHint(:final to, hint: ColorHint(:final color)) =>
      'h$to:${color.symbol}',
  };
}

/// The last hint a player received since their own last turn: who gave
/// it, which positions it touched and which position was the chop (the
/// oldest card no hint had touched) just before it. People read a hint by
/// its focus ([focus]): the chop if the hint touched it, else the newest
/// card it touched.
class ReceivedHint {
  ReceivedHint(this.giver, this.hint, this.touched, this.chop);

  final int giver;
  final Hint hint;
  final List<int> touched;
  final int chop;

  int get focus =>
      touched.contains(chop) ? chop : touched.reduce((a, b) => a > b ? a : b);
}

/// What a player did on their last turn, as the others remember it: the
/// slot they played or discarded (and whether a play fitted), or the hint
/// they gave and to whom.
class LastMove {
  LastMove.play(this.slot, {required this.fits})
    : kind = 'p',
      to = -1,
      hint = null;
  LastMove.discard(this.slot) : kind = 'd', to = -1, hint = null, fits = true;
  LastMove.hint(this.to, Hint this.hint) : kind = 'h', slot = -1, fits = true;

  /// 'p', 'd' or 'h'.
  final String kind;
  final int slot;
  final int to;
  final Hint? hint;
  final bool fits;
}

/// A deck as text, two characters a card (`1R`, `3*`), and back.
String deckText(List<GameCard> deck) => deck.map((c) => '$c').join();

List<GameCard> parseDeck(String text) {
  if (text.length.isOdd) throw const FormatException('odd deck text');
  return [
    for (var i = 0; i < text.length; i += 2)
      GameCard(
        int.parse(text[i]),
        CardColor.values.firstWhere(
          (c) => c.symbol == text[i + 1],
          orElse: () => throw FormatException('no color ${text[i + 1]}'),
        ),
      ),
  ];
}

class CoopPlay extends CoopMove {
  CoopPlay(this.index, {this.target});
  final int index;

  /// For a 2-5 joker: the pile it goes to.
  final CardColor? target;
}

class CoopDiscard extends CoopMove {
  CoopDiscard(this.index);
  final int index;
}

class CoopHint extends CoopMove {
  CoopHint(this.to, this.hint);

  /// The player who receives the hint.
  final int to;
  final Hint hint;
}

/// Hanabi for 2-4 players who take turns, with this app's cards (jokers
/// included), hint tokens, lives and five cards in every hand. Nobody sees their own hand, everyone
/// sees the others'. On a turn a player plays a card, discards one (winning
/// a hint token back) or spends a token to tell another player which of
/// their cards have one number or one color. When the deck runs out, play
/// goes on, as in the solitaire, until every hand is empty; a player with
/// no cards left is skipped.
class CoopGame {
  CoopGame({
    required this.players,
    Random? random,
    List<GameCard>? deck,
    int first = 0,
  }) : assert(players >= 2 && players <= maxPlayers),
       assert(first >= 0 && first < players),
       _deck = deck ?? buildDeck(random),
       current = first,
       fireworks = Fireworks() {
    for (var p = 0; p < players; p++) {
      received.add(null);
      lastMoves.add(null);
      hands.add([]);
      for (var i = 0; i < handSize; i++) {
        _draw(p);
      }
    }
  }

  /// An independent copy, to imagine how the game goes on.
  CoopGame.copy(CoopGame other)
    : players = other.players,
      _deck = [for (final c in other._deck) c.copy()],
      fireworks = Fireworks.copy(other.fireworks),
      hints = other.hints,
      errors = other.errors,
      current = other.current {
    received.addAll(other.received);
    lastMoves.addAll(other.lastMoves);
    for (final hand in other.hands) {
      hands.add([for (final c in hand) c.copy()]);
    }
    discarded.addAll(other.discarded);
  }

  /// The game as [player] could imagine it: their own cards, which they
  /// cannot see, drawn again from the cards they cannot see (deck and own
  /// hand) so that every hint they got still holds, and the deck shuffled.
  factory CoopGame.imagined(CoopGame other, int player, Random random) {
    final game = CoopGame.copy(other);
    final hand = game.hands[player];
    final unseen = [...game._deck, ...hand]..shuffle(random);
    bool fits(GameCard known, GameCard c) =>
        (known.knownNumber
            ? c.number == known.number
            : !known.notNumbers.contains(c.number)) &&
        (known.knownColor
            ? c.color == known.color
            : !known.notColors.contains(c.color));
    // The most constrained cards pick first.
    final order = [for (var i = 0; i < hand.length; i++) i]
      ..sort(
        (a, b) => unseen
            .where((c) => fits(hand[a], c))
            .length
            .compareTo(unseen.where((c) => fits(hand[b], c)).length),
      );
    for (var attempt = 0; attempt < 20; attempt++) {
      final pool = List.of(unseen);
      final drawn = List<GameCard?>.filled(hand.length, null);
      var ok = true;
      for (final i in order) {
        final j = pool.indexWhere((c) => fits(hand[i], c));
        if (j < 0) {
          ok = false;
          break;
        }
        final c = pool.removeAt(j);
        drawn[i] = GameCard(c.number, c.color)
          ..knownNumber = hand[i].knownNumber
          ..knownColor = hand[i].knownColor
          ..notNumbers.addAll(hand[i].notNumbers)
          ..notColors.addAll(hand[i].notColors);
      }
      if (ok) {
        for (var i = 0; i < hand.length; i++) {
          hand[i] = drawn[i]!;
        }
        game._deck
          ..clear()
          ..addAll(pool);
        return game;
      }
      unseen.shuffle(random);
    }
    // Rarely nothing fits on the first tries: keep the real cards.
    game._deck.shuffle(random);
    return game;
  }

  final int players;
  final List<GameCard> _deck;
  final List<List<GameCard>> hands = [];
  final List<GameCard> discarded = [];
  final Fireworks fireworks;

  /// Per player, the last hint received since their own last turn.
  final List<ReceivedHint?> received = [];

  /// Per player, their last move.
  final List<LastMove?> lastMoves = [];
  int hints = maxHints;
  int errors = allowedErrors;

  /// Whose turn it is; player 0 is the person. The cards are dealt from
  /// player 0 on, whoever plays first.
  int current;

  /// Cards per hand: five, whatever the number of players.
  int get handSize => 5;

  int get deckSize => _deck.length;
  int get score => fireworks.score;
  bool get isOver =>
      fireworks.victory || errors == 0 || hands.every((h) => h.isEmpty);

  /// Whether playing the card at [index] of the current hand needs a pile.
  bool needsTarget(int index) {
    final card = hands[current][index];
    return card.isJoker && card.number != 1;
  }

  /// The highest score still reachable, as in the solitaire.
  int maxScore() => viewFor(current).maxScore();

  /// The game as [player] sees it: their own hand (whose cards only the
  /// hints reveal), the table and every other hand.
  Game viewFor(int player) => Game.view(
    hand: hands[player],
    deck: _deck,
    discarded: discarded,
    fireworks: fireworks,
    hints: hints,
    errors: errors,
    inSight: [
      for (var p = 0; p < players; p++)
        if (p != player) ...hands[p],
    ],
  );

  /// Hints [player] could receive that reveal something new; each one
  /// touches at least one card, as the rules require.
  List<Hint> hintsFor(int player) {
    final result = <Hint>{};
    for (final card in hands[player]) {
      if (!card.knownNumber) result.add(NumberHint(card.number));
      if (!card.knownColor) result.add(ColorHint(card.color));
    }
    return result.toList();
  }

  /// The current player plays the card at [index].
  PlayResult play(int index, {CardColor? target}) {
    final hand = hands[current];
    final card = hand.removeAt(index)..reveal();
    _draw(current);
    final PlayResult result;
    if (fireworks.play(card, target: target)) {
      result = PlaySuccess();
    } else {
      discarded.add(card);
      errors--;
      result = PlayFailure(card);
    }
    lastMoves[current] = LastMove.play(index, fits: result is PlaySuccess);
    _endTurn();
    return result;
  }

  /// The current player throws away the card at [index].
  GameCard discard(int index) {
    final card = hands[current].removeAt(index)..reveal();
    discarded.add(card);
    _draw(current);
    if (hints < maxHints) hints++;
    lastMoves[current] = LastMove.discard(index);
    _endTurn();
    return card;
  }

  /// The current player tells player [to] about [hint]; returns the cards
  /// it points at.
  List<GameCard> hint(int to, Hint hint) {
    assert(to != current && hints > 0);
    hints--;
    final touched = <GameCard>[];
    final chop = hands[to].indexWhere((c) => !c.knownNumber && !c.knownColor);
    for (final card in hands[to]) {
      switch (hint) {
        case NumberHint(:final number) when card.number == number:
          card.knownNumber = true;
          touched.add(card);
        case NumberHint(:final number):
          card.ruleOutNumber(number);
        case ColorHint(:final color) when card.color == color:
          card.knownColor = true;
          touched.add(card);
        case ColorHint(:final color):
          card.ruleOutColor(color);
      }
    }
    received[to] = ReceivedHint(current, hint, [
      for (var i = 0; i < hands[to].length; i++)
        if (touched.contains(hands[to][i])) i,
    ], chop);
    lastMoves[current] = LastMove.hint(to, hint);
    _endTurn();
    return touched;
  }

  /// Whether the current player may make [move]: a card they hold, a pile
  /// for a joker above 1 (and none otherwise), a hint token and a hint that
  /// touches a card of another player.
  bool isLegal(CoopMove move) {
    if (isOver) return false;
    final hand = hands[current];
    switch (move) {
      case CoopPlay(:final index, :final target):
        if (index < 0 || index >= hand.length) return false;
        return needsTarget(index) == (target != null);
      case CoopDiscard(:final index):
        return index >= 0 && index < hand.length;
      case CoopHint(:final to, :final hint):
        if (to == current || to < 0 || to >= players || hints == 0) {
          return false;
        }
        return hands[to].any(
          (c) => switch (hint) {
            NumberHint(:final number) => c.number == number,
            ColorHint(:final color) => c.color == color,
          },
        );
    }
  }

  /// Applies any [move] for the current player.
  void apply(CoopMove move) {
    switch (move) {
      case CoopPlay(:final index, :final target):
        play(index, target: target);
      case CoopDiscard(:final index):
        discard(index);
      case CoopHint(:final to, :final hint):
        this.hint(to, hint);
    }
  }

  void _draw(int player) {
    if (_deck.isNotEmpty) hands[player].add(_deck.removeAt(0));
  }

  void _endTurn() {
    if (hands.isNotEmpty) received[current] = null;
    if (isOver) return;
    do {
      current = (current + 1) % players;
    } while (hands[current].isEmpty);
  }
}
