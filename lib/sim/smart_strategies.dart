import 'dart:math';

import '../game/card.dart';
import '../game/game.dart';
import 'simulated_player.dart';
import 'simulation.dart';

/// Tries every useful hint on a copy of the game and scores the position
/// right after it with hand-written rules.
class LookaheadStrategy extends HintStrategy {
  const LookaheadStrategy({
    this.playableWeight = 10,
    this.uselessWeight = 2,
    this.riskWeight = 1,
    this.knowledgeWeight = 0.1,
    this.progressWeight = 3,
  });

  final double playableWeight;
  final double uselessWeight;
  final double riskWeight;
  final double knowledgeWeight;

  /// Credit per revealed attribute on a card that is really playable but the
  /// player cannot be sure of yet: most plays need two hints.
  final double progressWeight;

  @override
  String get name => 'lookahead';

  @override
  Hint? choose(Game game) {
    Hint? best;
    var bestValue = double.negativeInfinity;
    for (final hint in game.usefulHints) {
      final value = evaluate(Game.copy(game)..applyHint(hint));
      if (value > bestValue) {
        best = hint;
        bestValue = value;
      }
    }
    return best;
  }

  /// Higher is better for the player.
  double evaluate(Game game) {
    final view = PlayerView(game);
    final playable = <int>{};
    var useless = 0;
    var knowledge = 0;
    var progress = 0;
    final reallyPlayable = game.fireworks.playableCards();
    for (var i = 0; i < game.hand.length; i++) {
      final card = game.hand[i];
      if (view.surelyPlayable(i)) {
        playable.add(card.number * 10 + card.color.index);
      } else if (reallyPlayable.any(card.sameAs)) {
        if (card.knownNumber) progress++;
        if (card.knownColor) progress++;
      }
      if (view.surelyUseless(i)) useless++;
      if (card.knownNumber) knowledge++;
      if (card.knownColor) knowledge++;
    }

    // The card the player throws away when stuck: losing a last copy caps
    // the score for the rest of the game.
    var risk = 0.0;
    for (var i = 0; i < game.hand.length; i++) {
      if (view.surelyPlayable(i) || view.maybeValuable(i)) continue;
      if (isCritical(game, game.hand[i])) risk = 1;
      break;
    }

    return playableWeight * playable.length +
        uselessWeight * useless -
        riskWeight * risk +
        knowledgeWeight * knowledge +
        progressWeight * progress;
  }

  /// Still needed and no other copy left.
  static bool isCritical(Game game, GameCard card) {
    final f = game.fireworks;
    final piles = card.isJoker ? CardColor.piles : [card.color];
    final dead = piles.every((c) => (f.top(c)?.number ?? 0) >= card.number);
    return !dead && game.remaining(card.number, card.color) == 1;
  }
}

/// For every useful hint, plays the rest of the game [rollouts] times on
/// copies with the deck reshuffled, and keeps the hint with the best average
/// final score. Assumes the human plays like [player].
class MonteCarloStrategy extends HintStrategy {
  MonteCarloStrategy({
    this.rollouts = 8,
    this.player = const CarefulPlayer(),
    this.rolloutStrategy = const LookaheadStrategy(),
    Random? random,
  }) : _random = random ?? Random();

  final int rollouts;
  final SimulatedPlayer player;

  /// Hints given later inside each simulated game.
  final HintStrategy rolloutStrategy;
  final Random _random;

  @override
  String get name => 'montecarlo';

  @override
  Hint? choose(Game game) {
    final options = game.usefulHints;
    if (options.length <= 1) return options.firstOrNull;
    Hint? best;
    var bestTotal = -1;
    for (final hint in options) {
      var total = 0;
      for (var i = 0; i < rollouts; i++) {
        final sim = Game.copy(game, random: _random, strategy: rolloutStrategy)
          ..hints -= 1
          ..applyHint(hint);
        playOut(sim, player);
        total += sim.score;
      }
      if (total > bestTotal) {
        best = hint;
        bestTotal = total;
      }
    }
    return best;
  }
}
