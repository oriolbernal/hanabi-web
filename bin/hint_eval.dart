// Compares hint givers with the expert player in the player's seat, on the
// same decks, reporting each one's gain over the expert's hint rules.
//
//   dart run bin/hint_eval.dart [games] [seed] [--search=rounds] [--model=path ...]

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:hanabi/game/game.dart';
import 'package:hanabi/sim/expert.dart';
import 'package:hanabi/sim/hint_search.dart';
import 'package:hanabi/sim/rl_strategy.dart';
import 'package:hanabi/sim/simulation.dart';

void main(List<String> args) {
  final numbers = args.where((a) => !a.startsWith('--')).toList();
  final games = numbers.isNotEmpty ? int.parse(numbers[0]) : 2000;
  final seed = numbers.length > 1 ? int.parse(numbers[1]) : 20000;
  final strategies = <HintStrategy>[
    for (final a in args)
      if (a.startsWith('--model='))
        RlStrategy(
          jsonDecode(File(a.substring('--model='.length)).readAsStringSync()),
          name: File(a).uri.pathSegments.last.split('.').first,
        ),
    for (final a in args)
      if (a.startsWith('--search='))
        SearchHints(rounds: int.parse(a.substring('--search='.length))),
  ];
  const player = ExpertPlayer.tuned;

  List<int> scores(HintStrategy s) => [
    for (var i = 0; i < games; i++) playGame(s, player, seed + i).score,
  ];
  final base = scores(const ExpertHints());
  final baseMean = base.reduce((a, b) => a + b) / games;
  print('expert player, $games games from seed $seed\n');
  print('hints         mean   gain  ±95%   time');
  print('${'expert'.padRight(12)} ${baseMean.toStringAsFixed(2).padLeft(6)}');
  for (final s in strategies) {
    final watch = Stopwatch()..start();
    final result = scores(s);
    final diffs = [for (var i = 0; i < games; i++) result[i] - base[i]];
    final gain = diffs.reduce((a, b) => a + b) / games;
    final variance =
        diffs.fold(0.0, (acc, d) => acc + pow(d - gain, 2)) / games;
    print(
      '${s.name.padRight(12)} '
      '${(baseMean + gain).toStringAsFixed(2).padLeft(6)} '
      '${(gain >= 0 ? '+' : '') + gain.toStringAsFixed(2)} '
      '${(1.96 * sqrt(variance / games)).toStringAsFixed(2).padLeft(5)} '
      '${(watch.elapsedMilliseconds / 1000).toStringAsFixed(0).padLeft(5)}s',
    );
  }
}
