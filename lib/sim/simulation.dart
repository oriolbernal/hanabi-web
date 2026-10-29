import 'dart:math';

import '../game/card.dart';
import '../game/game.dart';
import 'simulated_player.dart';

class GameResult {
  GameResult(this.score, this.errorsLeft, this.turns, this.hints);
  final int score;
  final int errorsLeft;
  final int turns;
  final HintStats hints;

  bool get won => score == 25;
  bool get burnedOut => errorsLeft == 0;
}

/// Plays one full game. The same [seed] always deals the same deck, so
/// strategies can be compared on identical games.
GameResult playGame(HintStrategy strategy, SimulatedPlayer player, int seed) {
  final game = Game(random: Random(seed), strategy: strategy);
  final hints = HintStats();
  final turns = playOut(game, player, stats: hints);
  return GameResult(game.score, game.errors, turns, hints);
}

/// How useful the hints of one game were, as a person would judge them.
class HintStats {
  int given = 0;

  /// Hints after which the player could safely play or discard a card it
  /// could not before.
  int actionable = 0;
}

/// Lets [player] finish [game]. Returns the number of turns played.
int playOut(Game game, SimulatedPlayer player, {HintStats? stats}) {
  var turns = 0;
  while (!game.isOver) {
    turns++;
    switch (player.decide(game)) {
      case PlayMove(:final index):
        game.play(index, target: _jokerTarget(game, index));
      case DiscardMove(:final index):
        game.discard(index);
      case HintMove():
        final before = stats == null ? 0 : safeActions(game);
        if (game.hint() == null) {
          game.discard(0);
        } else if (stats != null) {
          stats.given++;
          if (safeActions(game) > before) stats.actionable++;
        }
    }
  }
  return turns;
}

/// The UI asks the human where to put a 2-5 joker; the simulated player
/// takes the first pile it fits on.
CardColor? _jokerTarget(Game game, int index) {
  if (!game.needsTarget(index)) return null;
  final card = game.hand[index];
  return CardColor.piles.firstWhere(
    (c) => game.fireworks.fits(card, c),
    orElse: () => CardColor.red,
  );
}

class BenchmarkReport {
  BenchmarkReport(this.strategy, this.player, this.results);

  final String strategy;
  final String player;
  final List<GameResult> results;

  double get mean => results.fold(0, (s, r) => s + r.score) / results.length;

  double get stdDev {
    final m = mean;
    final variance =
        results.fold(0.0, (s, r) => s + pow(r.score - m, 2)) / results.length;
    return sqrt(variance);
  }

  /// Half-width of the 95% confidence interval of [mean].
  double get margin => 1.96 * stdDev / sqrt(results.length);

  double _rate(bool Function(GameResult) test) =>
      results.where(test).length / results.length;

  double get hintsPerGame =>
      results.fold(0, (s, r) => s + r.hints.given) / results.length;

  /// Share of all hints that let the player act right away.
  double get actionableRate =>
      results.fold(0, (s, r) => s + r.hints.actionable) /
      results.fold(0, (s, r) => s + r.hints.given);

  double get winRate => _rate((r) => r.won);
  double get burnOutRate => _rate((r) => r.burnedOut);

  /// How many games ended with each score, 0..25.
  List<int> get histogram {
    final h = List.filled(26, 0);
    for (final r in results) {
      h[r.score]++;
    }
    return h;
  }
}

BenchmarkReport benchmark(
  HintStrategy strategy,
  SimulatedPlayer player, {
  int games = 10000,
  int seed = 0,
}) {
  return BenchmarkReport(strategy.name, player.name, [
    for (var i = 0; i < games; i++) playGame(strategy, player, seed + i),
  ]);
}
