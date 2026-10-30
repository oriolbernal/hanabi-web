import 'dart:math';

import '../game/game.dart';
import 'expert.dart';
import 'simulated_player.dart';
import 'simulation.dart';

/// Finds the best hint by trying them all. It sees the real cards, as the
/// hint giver does: for each useful hint it plays the rest of the game many
/// times, the deck shuffled each time (its order is unknown), with [player]
/// in the player's seat, and keeps the hint with the best average final
/// score. Every hint is tried on the same shuffles, so they compare fairly.
///
/// Over 400 simulated games with the expert player it scores 21.5 with 24
/// games per hint, against 19.5 for the expert's own hint rules.
class HintSearch {
  HintSearch({
    this.player = ExpertPlayer.tuned,
    this.laterHints = const ExpertHints(),
    Random? random,
  }) : _random = random ?? Random();

  /// Plays the imagined games.
  final SimulatedPlayer player;

  /// Gives the later hints inside the imagined games.
  final HintStrategy laterHints;
  final Random _random;

  /// Average final score of each useful hint after [rounds] games each.
  List<(Hint, double)> evaluate(Game game, {int rounds = 24}) {
    final search = _Search(this, game);
    for (var r = 0; r < rounds; r++) {
      search.round();
    }
    return search.results();
  }

  Hint? best(Game game, {int rounds = 24}) =>
      _best(evaluate(game, rounds: rounds));

  /// Like [best], but stops after about [budget] (and at least [minRounds]
  /// games per hint), pausing between games so the screen stays responsive.
  Future<Hint?> bestWithin(
    Game game,
    Duration budget, {
    int minRounds = 4,
    int maxRounds = 200,
  }) async {
    final search = _Search(this, game);
    final clock = Stopwatch()..start();
    for (var r = 0; r < maxRounds; r++) {
      if (r >= minRounds && clock.elapsed >= budget) break;
      search.round();
      await Future<void>.delayed(Duration.zero);
    }
    return _best(search.results());
  }

  static Hint? _best(List<(Hint, double)> scored) =>
      scored.isEmpty ? null : scored.reduce((a, b) => b.$2 > a.$2 ? b : a).$1;
}

class _Search {
  _Search(this.owner, this.game)
    : hints = game.usefulHints,
      totals = List.filled(game.usefulHints.length, 0);

  final HintSearch owner;
  final Game game;
  final List<Hint> hints;
  final List<double> totals;
  int rounds = 0;

  /// One more imagined game per hint, all on the same shuffle.
  void round() {
    if (hints.length < 2) return;
    final seed = owner._random.nextInt(1 << 30);
    for (var h = 0; h < hints.length; h++) {
      final g = Game.copy(
        game,
        random: Random(seed),
        strategy: owner.laterHints,
      )..giveHint(hints[h]);
      playOut(g, owner.player);
      totals[h] += g.score;
    }
    rounds++;
  }

  List<(Hint, double)> results() => [
    for (var h = 0; h < hints.length; h++)
      (hints[h], rounds == 0 ? 0 : totals[h] / rounds),
  ];
}

/// The game's hint giver backed by [HintSearch]. The app asks
/// [chooseWithin] with a time budget; simulations use [choose].
class SearchHints extends HintStrategy {
  SearchHints({HintSearch? search, this.rounds = 24})
    : search = search ?? HintSearch();

  final HintSearch search;

  /// Games per hint when there is no time budget.
  final int rounds;

  @override
  String get name => 'search';

  @override
  Hint? choose(Game game) => search.best(game, rounds: rounds);

  Future<Hint?> chooseWithin(Game game, Duration budget) =>
      search.bestWithin(game, budget);
}
