// Plays many games with each hint strategy and compares their scores.
//
//   dart run bin/benchmark.dart [games] [seed]

// ignore_for_file: avoid_print

import 'dart:math';

import 'package:hanabi/game/game.dart';
import 'package:hanabi/sim/simulated_player.dart';
import 'package:hanabi/sim/simulation.dart';

void main(List<String> args) {
  final games = args.isNotEmpty ? int.parse(args[0]) : 10000;
  final seed = args.length > 1 ? int.parse(args[1]) : 0;

  final strategies = <HintStrategy>[
    RandomStrategy(Random(seed)),
    const DummyStrategy(),
  ];
  const player = CarefulPlayer();

  print('$games games per strategy, player: ${player.name}, seed: $seed\n');
  print('strategy   mean   ±std   wins  burned out  time');
  for (final strategy in strategies) {
    final watch = Stopwatch()..start();
    final r = benchmark(strategy, player, games: games, seed: seed);
    print(
      '${r.strategy.padRight(9)} '
      '${r.mean.toStringAsFixed(2).padLeft(5)} '
      '${r.stdDev.toStringAsFixed(2).padLeft(6)} '
      '${_pct(r.winRate).padLeft(5)} '
      '${_pct(r.burnOutRate).padLeft(11)} '
      '${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1).padLeft(5)}s',
    );
  }

  print('\nScore distribution (dummy):');
  final h = benchmark(
    const DummyStrategy(),
    player,
    games: games,
    seed: seed,
  ).histogram;
  final top = h.reduce(max);
  for (var s = 0; s <= 25; s++) {
    if (h[s] == 0) continue;
    final bar = '█' * (h[s] * 40 ~/ top);
    print('${'$s'.padLeft(3)} ${'${h[s]}'.padLeft(5)} $bar');
  }
}

String _pct(double v) => '${(v * 100).toStringAsFixed(2)}%';
