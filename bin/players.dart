// Mean score of every hint strategy against every simulated player profile.
//
//   dart run bin/players.dart [games] [--model=path ...]

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:hanabi/game/game.dart';
import 'package:hanabi/sim/player_policy.dart';
import 'package:hanabi/sim/rl_strategy.dart';
import 'package:hanabi/sim/simulated_player.dart';
import 'package:hanabi/sim/simulation.dart';
import 'package:hanabi/sim/smart_strategies.dart';

void main(List<String> args) {
  final numbers = args.where((a) => !a.startsWith('--')).toList();
  final games = numbers.isNotEmpty ? int.parse(numbers[0]) : 3000;
  final models = [
    for (final a in args)
      if (a.startsWith('--model=')) a.substring('--model='.length),
  ];
  if (models.isEmpty) models.add('assets/models/hint_policy.json');
  final strategies = <HintStrategy>[
    const DummyStrategy(),
    const LookaheadStrategy(),
    for (final path in models)
      RlStrategy(
        jsonDecode(File(path).readAsStringSync()),
        name: models.length > 1
            ? File(path).uri.pathSegments.last.split('.').first
            : 'rl+rule',
        playFirst: true,
      ),
  ];

  final players = [
    ...playerProfiles,
    if (File('assets/models/player_policy.json').existsSync())
      PlayerPolicy(
        jsonDecode(File('assets/models/player_policy.json').readAsStringSync()),
        noWastedDiscards: true,
        safeDiscardMargin: PlayerPolicy.appSafeDiscardMargin,
      ),
  ];

  print('$games games each. Cells: mean score (burned out %)\n');
  print('strategy    ${[for (final p in players) p.name.padLeft(15)].join()}');
  for (final s in strategies) {
    final cells = [
      for (final p in players)
        () {
          final r = benchmark(s, p, games: games);
          final burned = (r.burnOutRate * 100).toStringAsFixed(0);
          return '${r.mean.toStringAsFixed(2)} (${burned.padLeft(2)}%)'.padLeft(
            15,
          );
        }(),
    ];
    print('${s.name.padRight(13)} ${cells.join()}');
  }
}
