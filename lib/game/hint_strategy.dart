import 'dart:math';

import 'game.dart';

/// Decides which hint to give when the player asks for one.
///
/// Strategies may look at the whole game, including the real cards in hand:
/// they play the role of the partner who can see your cards.
abstract class HintStrategy {
  const HintStrategy();

  String get name;

  /// Returns the hint to give, or null if there is nothing left to reveal.
  Hint? choose(Game game);
}

/// The original rule from the console version: score each unrevealed
/// attribute by how many cards share it, with a bonus for cards that are
/// playable right now.
class DummyStrategy extends HintStrategy {
  const DummyStrategy();

  @override
  String get name => 'dummy';

  @override
  Hint? choose(Game game) {
    final playable = game.fireworks.playableCards();
    final scores = <Hint, int>{};
    void bump(Hint h) => scores[h] = (scores[h] ?? 0) + 1;

    for (final card in game.hand) {
      final isPlayable = playable.any(card.sameAs);
      if (!card.knownNumber) {
        bump(NumberHint(card.number));
        if (isPlayable) bump(NumberHint(card.number));
      }
      if (!card.knownColor) {
        bump(ColorHint(card.color));
        if (isPlayable) bump(ColorHint(card.color));
      }
    }
    if (scores.isEmpty) return null;
    return scores.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }
}

/// Picks any hint that reveals something. A floor for the benchmark: every
/// other strategy should beat it.
class RandomStrategy extends HintStrategy {
  RandomStrategy([Random? random]) : _random = random ?? Random();

  final Random _random;

  @override
  String get name => 'random';

  @override
  Hint? choose(Game game) {
    final options = game.usefulHints;
    return options.isEmpty ? null : options[_random.nextInt(options.length)];
  }
}
