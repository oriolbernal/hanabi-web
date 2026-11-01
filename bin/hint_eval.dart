// Compares hint givers with the expert player in the player's seat, on the
// same decks, reporting each one's gain over the expert's hint rules.
//
//   dart run bin/hint_eval.dart [games] [seed] [--player=human] [--search=rounds]
//       [--model=path ...] [--playfirst] [--margin=0.3,1] [--chance=0.7]
//
// --playfirst only allows, among hints that give the player a likely play,
// the best one; --margin=X lets such a hint win when the network values it
// within X points of its favourite (one strategy per listed margin). The
// "likely play" means a chance of at least --chance (default 0.5) of fitting
// a card. The last columns: share of hints after which the player could
// safely play or discard something new, and share of the states where some
// hint gave a likely play in which the hint given did (first the first hint
// of each game, then all).

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
  final player = args.contains('--player=human')
      ? ExpertPlayer.human
      : ExpertPlayer.tuned;
  final margins = [
    for (final a in args)
      if (a.startsWith('--margin='))
        ...a.substring('--margin='.length).split(',').map(double.parse),
  ];
  final chance = [
    for (final a in args)
      if (a.startsWith('--chance=')) double.parse(a.substring('--chance='.length)),
  ].firstOrNull ?? 0.5;
  final strategies = <HintStrategy>[
    for (final a in args)
      if (a.startsWith('--model=')) ...[
        for (final margin in margins.isEmpty ? [0.0] : margins)
          RlStrategy(
            jsonDecode(File(a.substring('--model='.length)).readAsStringSync()),
            name:
                File(a).uri.pathSegments.last.split('.').first +
                (margin > 0 ? ' m$margin' : ''),
            playFirst: args.contains('--playfirst'),
            playMargin: margin,
            playChance: chance,
          ),
      ],
    // The search simulates the same player it is evaluated with.
    for (final a in args)
      if (a.startsWith('--search='))
        SearchHints(
          search: HintSearch(
            player: player,
            playMargin: margins.firstOrNull ?? 0,
            playChance: chance,
          ),
          rounds: int.parse(a.substring('--search='.length)),
        ),
  ];

  List<GameResult> run(HintStrategy s) => [
    for (var i = 0; i < games; i++) playGame(s, player, seed + i),
  ];
  String legible(Counting c) =>
      ' ${(100 * c.firstTaken / c.firstPossible).toStringAsFixed(0)}%'
              .padLeft(5) +
      ' ${(100 * c.taken / c.possible).toStringAsFixed(0)}%'.padLeft(5);
  String actionable(List<GameResult> results) {
    final given = results.fold(0, (n, r) => n + r.hints.given);
    final useful = results.fold(0, (n, r) => n + r.hints.actionable);
    return '${(100 * useful / given).toStringAsFixed(0)}%'.padLeft(5);
  }

  final baseCounting = Counting(const ExpertHints(), chance);
  final baseResults = run(baseCounting);
  final base = [for (final r in baseResults) r.score];
  final baseMean = base.reduce((a, b) => a + b) / games;
  print('${player.name} player, $games games from seed $seed\n');
  print('hints         mean   gain  ±95%   time  actionable  likely 1st/all');
  print(
    '${'expert'.padRight(12)} ${baseMean.toStringAsFixed(2).padLeft(6)}'
    '${''.padLeft(19)}${actionable(baseResults)}${legible(baseCounting)}',
  );
  for (final s in strategies) {
    final watch = Stopwatch()..start();
    final counting = Counting(s, chance);
    final results = run(counting);
    final result = [for (final r in results) r.score];
    final diffs = [for (var i = 0; i < games; i++) result[i] - base[i]];
    final gain = diffs.reduce((a, b) => a + b) / games;
    final variance =
        diffs.fold(0.0, (acc, d) => acc + pow(d - gain, 2)) / games;
    print(
      '${s.name.padRight(12)} '
      '${(baseMean + gain).toStringAsFixed(2).padLeft(6)} '
      '${(gain >= 0 ? '+' : '') + gain.toStringAsFixed(2)} '
      '${(1.96 * sqrt(variance / games)).toStringAsFixed(2).padLeft(5)} '
      '${(watch.elapsedMilliseconds / 1000).toStringAsFixed(0).padLeft(5)}s'
      '${actionable(results)}${legible(counting)}',
    );
  }
}

/// Counts, around [inner], the states where some hint gave a likely play
/// and whether the hint given was one of those.
class Counting extends HintStrategy {
  Counting(this.inner, this.chance);
  final HintStrategy inner;
  final double chance;
  int possible = 0, taken = 0, firstPossible = 0, firstTaken = 0;

  @override
  String get name => inner.name;

  @override
  Hint? choose(Game game) {
    final hint = inner.choose(game);
    if (hint == null) return null;
    final chances = {
      for (final h in game.usefulHints)
        hintToAction(h): RlStrategy.playChanceAfter(game, hintToAction(h)),
    };
    final top = chances.values.reduce(max);
    if (top >= chance && top > RlStrategy.playChanceAfter(game, null) + 1e-9) {
      final first =
          game.hints == 10 &&
          game.score == 0 &&
          game.discarded.isEmpty &&
          game.hand.every((c) => !c.knownNumber && !c.knownColor);
      possible++;
      if (first) firstPossible++;
      if (chances[hintToAction(hint)]! >= top - 1e-9) {
        taken++;
        if (first) firstTaken++;
      }
    }
    return hint;
  }
}
