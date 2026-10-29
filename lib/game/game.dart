import 'dart:math';

import 'card.dart';
import 'fireworks.dart';
import 'hint_strategy.dart';

export 'hint_strategy.dart';

const maxHints = 10;
const allowedErrors = 3;
const handSize = 5;
const numberDistribution = [3, 2, 2, 2, 1];

List<GameCard> buildDeck([Random? random]) {
  final cards = <GameCard>[
    for (final color in CardColor.piles)
      for (var n = 1; n <= 5; n++)
        for (var i = 0; i < numberDistribution[n - 1]; i++) GameCard(n, color),
    for (var n = 1; n <= 5; n++) GameCard(n, CardColor.joker),
  ];
  return cards..shuffle(random);
}

/// A hint reveals either a number or a color on every matching card in hand.
sealed class Hint {}

class NumberHint extends Hint {
  NumberHint(this.number);
  final int number;
  @override
  bool operator ==(Object other) =>
      other is NumberHint && other.number == number;
  @override
  int get hashCode => number.hashCode;
}

class ColorHint extends Hint {
  ColorHint(this.color);
  final CardColor color;
  @override
  bool operator ==(Object other) => other is ColorHint && other.color == color;
  @override
  int get hashCode => color.hashCode;
}

sealed class PlayResult {}

class PlaySuccess extends PlayResult {}

class PlayFailure extends PlayResult {
  PlayFailure(this.card);
  final GameCard card;
}

class Game {
  Game({
    Random? random,
    List<GameCard>? deck,
    this.strategy = const DummyStrategy(),
  }) : _deck = deck ?? buildDeck(random) {
    _draw(handSize);
  }

  final List<GameCard> _deck;
  final HintStrategy strategy;
  final List<GameCard> hand = [];
  final List<GameCard> discarded = [];
  final Fireworks fireworks = Fireworks();
  int hints = maxHints;
  int errors = allowedErrors;

  int get deckSize => _deck.length;
  int get score => fireworks.score;
  bool get isOver =>
      fireworks.victory || (_deck.isEmpty && hand.isEmpty) || errors == 0;

  /// Whether playing the card at [index] needs the player to pick a pile.
  bool needsTarget(int index) {
    final card = hand[index];
    return card.isJoker && card.number != 1;
  }

  PlayResult play(int index, {CardColor? target}) {
    final card = hand.removeAt(index)..reveal();
    _draw(1);
    if (fireworks.play(card, target: target)) return PlaySuccess();
    discarded.add(card);
    errors--;
    return PlayFailure(card);
  }

  GameCard discard(int index) {
    final card = hand.removeAt(index)..reveal();
    discarded.add(card);
    _draw(1);
    if (hints < maxHints) hints++;
    return card;
  }

  /// Hints that would reveal something new about the hand.
  List<Hint> get usefulHints {
    final result = <Hint>{};
    for (final card in hand) {
      if (!card.knownNumber) result.add(NumberHint(card.number));
      if (!card.knownColor) result.add(ColorHint(card.color));
    }
    return result.toList();
  }

  /// Asks the [strategy] for a hint and applies it. Returns null when there
  /// are no hint tokens left or nothing left to reveal.
  Hint? hint() {
    if (hints == 0) return null;
    final best = strategy.choose(this);
    if (best == null) return null;
    hints--;
    for (final card in hand) {
      switch (best) {
        case NumberHint(:final number) when card.number == number:
          card.knownNumber = true;
        case ColorHint(:final color) when card.color == color:
          card.knownColor = true;
        default:
      }
    }
    return best;
  }

  void _draw(int count) {
    for (var i = 0; i < count && _deck.isNotEmpty; i++) {
      hand.add(_deck.removeAt(0));
    }
  }
}
