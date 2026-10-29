// Plays many games with each hint strategy and compares their scores.
//
//   dart run bin/benchmark.dart [games] [seed]
//
// Monte Carlo is far slower, so it plays at most [mcGames] games.

// ignore_for_file: avoid_print

import 'dart:math';

import 'package:hanabi/game/game.dart';
import 'package:hanabi/sim/simulated_player.dart';
import 'package:hanabi/sim/simulation.dart';
import 'package:hanabi/sim/smart_strategies.dart';

const mcGames = 300;

void main(List<String> args) {
  final games = args.isNotEmpty ? int.parse(args[0]) : 10000;
  final seed = args.length > 1 ? int.parse(args[1]) : 0;
  const player = CarefulPlayer();

  final strategies = <(HintStrategy, int)>[
    (RandomStrategy(Random(seed)), games),
    (const DummyStrategy(), games),
    (const LookaheadStrategy(), games),
    (MonteCarloStrategy(random: Random(seed)), min(games, mcGames)),
  ];

  print('player: ${player.name}, seed: $seed\n');
  print('strategy     games   mean  ±95%    std   wins  burned  time');
  for (final (strategy, n) in strategies) {
    final watch = Stopwatch()..start();
    final r = benchmark(strategy, player, games: n, seed: seed);
    print(
      '${r.strategy.padRight(11)} '
      '${'$n'.padLeft(6)} '
      '${r.mean.toStringAsFixed(2).padLeft(6)} '
      '${r.margin.toStringAsFixed(2).padLeft(5)} '
      '${r.stdDev.toStringAsFixed(2).padLeft(6)} '
      '${_pct(r.winRate).padLeft(6)} '
      '${_pct(r.burnOutRate).padLeft(7)} '
      '${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1).padLeft(5)}s',
    );
  }
}

String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';
