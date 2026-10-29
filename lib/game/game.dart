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
  }) : _deck = deck ?? buildDeck(random),
       fireworks = Fireworks() {
    _draw(handSize);
  }

  /// An independent copy for simulations. With [random], the cards left in
  /// the deck are reshuffled: whoever simulates cannot know their order.
  Game.copy(Game other, {Random? random, HintStrategy? strategy})
    : _deck = [for (final c in other._deck) c.copy()],
      strategy = strategy ?? other.strategy,
      fireworks = Fireworks.copy(other.fireworks),
      hints = other.hints,
      errors = other.errors {
    hand.addAll([for (final c in other.hand) c.copy()]);
    discarded.addAll(other.discarded);
    if (random != null) _deck.shuffle(random);
  }

  final List<GameCard> _deck;
  final HintStrategy strategy;
  final List<GameCard> hand = [];
  final List<GameCard> discarded = [];
  final Fireworks fireworks;
  int hints = maxHints;
  int errors = allowedErrors;

  int get deckSize => _deck.length;

  /// Copies of (number, color) not yet discarded: played or still to come.
  int remaining(int number, CardColor color) {
    final total = color == CardColor.joker ? 1 : numberDistribution[number - 1];
    return total -
        discarded.where((c) => c.number == number && c.color == color).length;
  }

  /// Highest score still reachable if every card left were played in the
  /// right order, as if [lost] were discarded too. Each joker not yet used
  /// can fill the gap left by one lost card of its number, on any pile.
  int maxScore({List<GameCard> lost = const []}) {
    bool gone(int n, CardColor c) {
      final total = c == CardColor.joker ? 1 : numberDistribution[n - 1];
      bool same(GameCard x) => x.number == n && x.color == c;
      return discarded.where(same).length + lost.where(same).length >= total;
    }

    final usedJokers = {
      for (final c in CardColor.piles)
        for (final card in fireworks.pile(c))
          if (card.isJoker) card.number,
    };
    final jokers = [
      for (var n = 1; n <= 5; n++)
        if (!usedJokers.contains(n) && !gone(n, CardColor.joker)) n,
    ];
    final tops = [
      for (final c in CardColor.piles) fireworks.top(c)?.number ?? 0,
    ];
    final gaps = [
      for (var p = 0; p < tops.length; p++)
        {
          for (var n = tops[p] + 1; n <= 5; n++)
            if (gone(n, CardColor.piles[p])) n,
        },
    ];

    int heights(List<Set<int>> g) {
      var sum = 0;
      for (var p = 0; p < g.length; p++) {
        sum += g[p].isEmpty ? 5 : g[p].reduce(min) - 1;
      }
      return sum;
    }

    // Try every way of giving each joker to a pile it would help.
    int best(int j, List<Set<int>> g) {
      if (j == jokers.length) return heights(g);
      var result = best(j + 1, g);
      for (var p = 0; p < g.length; p++) {
        if (!g[p].contains(jokers[j])) continue;
        final filled = [...g];
        filled[p] = {...g[p]}..remove(jokers[j]);
        result = max(result, best(j + 1, filled));
      }
      return result;
    }

    return best(0, gaps);
  }

  /// Points of [maxScore] lost if [card] were thrown away.
  int discardLoss(GameCard card) => maxScore() - maxScore(lost: [card]);

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
    applyHint(best);
    return best;
  }

  /// Reveals [hint] on the hand without spending a token.
  void applyHint(Hint hint) {
    for (final card in hand) {
      switch (hint) {
        case NumberHint(:final number) when card.number == number:
          card.knownNumber = true;
        case NumberHint(:final number):
          card.ruleOutNumber(number);
        case ColorHint(:final color) when card.color == color:
          card.knownColor = true;
        case ColorHint(:final color):
          card.ruleOutColor(color);
      }
    }
  }

  void _draw(int count) {
    for (var i = 0; i < count && _deck.isNotEmpty; i++) {
      hand.add(_deck.removeAt(0));
    }
  }
}
