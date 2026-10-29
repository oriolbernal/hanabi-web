// Plays many games with each hint strategy and compares their scores.
//
//   dart run bin/benchmark.dart [games] [seed] [--fast] [--model=path ...]
//
// Monte Carlo is far slower, so it plays at most [mcGames] games; --fast
// skips it. The rl strategy is included once rl/export.py has run.

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:hanabi/game/game.dart';
import 'package:hanabi/sim/rl_strategy.dart';
import 'package:hanabi/sim/simulated_player.dart';
import 'package:hanabi/sim/simulation.dart';
import 'package:hanabi/sim/smart_strategies.dart';

const mcGames = 300;

void main(List<String> args) {
  final numbers = args.where((a) => !a.startsWith('--')).toList();
  final games = numbers.isNotEmpty ? int.parse(numbers[0]) : 10000;
  final seed = numbers.length > 1 ? int.parse(numbers[1]) : 0;
  const player = CarefulPlayer();

  final strategies = <(HintStrategy, int)>[
    (RandomStrategy(Random(seed)), games),
    (const DummyStrategy(), games),
    (const LookaheadStrategy(), games),
    (MonteCarloStrategy(random: Random(seed)), min(games, mcGames)),
  ];

  final models = [
    for (final a in args)
      if (a.startsWith('--model=')) a.substring('--model='.length),
  ];
  if (models.isEmpty) models.add('assets/models/hint_policy.json');
  for (final path in models) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final policy = RlStrategy(
      jsonDecode(file.readAsStringSync()),
      name: models.length > 1
          ? file.uri.pathSegments.last.split('.').first
          : 'rl',
    );
    strategies.add((policy, games));
    strategies.add((
      RlStrategy(
        jsonDecode(file.readAsStringSync()),
        name: '${policy.name}+rule',
        playFirst: true,
      ),
      games,
    ));
  }
  if (args.contains('--fast')) {
    strategies.removeWhere((s) => s.$1 is MonteCarloStrategy);
  }

  print('player: ${player.name}, seed: $seed\n');
  print('strategy     games   mean  ±95%    std  hints  act.%  time');
  for (final (strategy, n) in strategies) {
    final watch = Stopwatch()..start();
    final r = benchmark(strategy, player, games: n, seed: seed);
    print(
      '${r.strategy.padRight(11).substring(0, 11)} '
      '${'$n'.padLeft(6)} '
      '${r.mean.toStringAsFixed(2).padLeft(6)} '
      '${r.margin.toStringAsFixed(2).padLeft(5)} '
      '${r.stdDev.toStringAsFixed(2).padLeft(6)} '
      '${r.hintsPerGame.toStringAsFixed(1).padLeft(6)} '
      '${_pct(r.actionableRate).padLeft(6)} '
      '${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1).padLeft(5)}s',
    );
  }
}

String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';
