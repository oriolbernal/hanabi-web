// Compares co-op bots on the same decks: the rules, the search and trained
// networks, with seat 0 a model of the person (or a bot, --bots).
//
//   dart run bin/coop_eval.dart [games] [players] [--search=rounds]
//       [--net=model.json ...] [--bots] [--seed=N]

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:hanabi/game/coop.dart';
import 'package:hanabi/sim/coop_bot.dart';
import 'package:hanabi/sim/coop_net.dart';
import 'package:hanabi/sim/selfplay_bot.dart';
import 'package:hanabi/sim/coop_search.dart';
import 'package:hanabi/sim/expert.dart';

void main(List<String> args) {
  final numbers = args.where((a) => !a.startsWith('--')).toList();
  final games = numbers.isNotEmpty ? int.parse(numbers[0]) : 200;
  final players = numbers.length > 1 ? int.parse(numbers[1]) : 4;
  final allBots = args.contains('--bots');
  final seed = int.parse(
    [
          for (final a in args)
            if (a.startsWith('--seed=')) a.substring(7),
        ].firstOrNull ??
        '9000',
  );
  final minPlay = double.parse(
    [
          for (final a in args)
            if (a.startsWith('--min-play=')) a.substring(11),
        ].firstOrNull ??
        '0.4',
  );
  final bots = <String, CoopMove Function(CoopGame)>{
    'rules': const CoopBot().decide,
    for (final a in args)
      if (a.startsWith('--search='))
        'search ${a.substring(9)}': CoopSearch(
          rounds: int.parse(a.substring(9)),
          person: allBots ? null : 0,
          minPlayChance: minPlay,
          rollout: args.contains('--rollout=person')
              ? const QuickPersonPolicy().decide
              : args.contains('--rollout=sharp')
              ? const SharpCoopPolicy().decide
              : null,
          random: Random(1),
        ).decide,
    for (final a in args)
      if (a.startsWith('--net='))
        File(a.substring(6)).uri.pathSegments.last.split('.').first: CoopNet(
          jsonDecode(File(a.substring(6)).readAsStringSync()),
          minPlayChance: minPlay,
        ).decide,
    for (final a in args)
      if (a.startsWith('--selfplay='))
        'SP ${File(a.substring(11)).uri.pathSegments.last.split('.').first}':
            SelfPlayBot(jsonDecode(File(a.substring(11)).readAsStringSync()))
                .decide,
  };
  const person = CoopBot(player: ExpertPlayer.human);
  print(
    '$players players, $games games from seed $seed, '
    '${allBots ? 'all bots' : 'seat 0 = person model'}\n',
  );
  print(
    'bot            mean   gain  ±95%   hints to seat 0   ms/move  bot misfires   25s',
  );
  List<int>? base;
  for (final MapEntry(key: name, value: bot) in bots.entries) {
    final scores = <int>[];
    var toYou = 0, moves = 0, misfires = 0;
    final watch = Stopwatch()..start();
    for (var g = 0; g < games; g++) {
      final game = CoopGame(players: players, random: Random(seed + g));
      while (!game.isOver) {
        final CoopMove move;
        if (game.current == 0 && !allBots) {
          move = person.decide(game);
        } else {
          move = bot(game);
          moves++;
        }
        if (move is CoopHint && move.to == 0 && game.current != 0) toYou++;
        final lives = game.errors;
        final byBot = game.current != 0 || allBots;
        game.apply(move);
        if (byBot && game.errors < lives) misfires++;
      }
      scores.add(game.score);
    }
    base ??= scores;
    final diffs = [for (var i = 0; i < games; i++) scores[i] - base[i]];
    final gain = diffs.reduce((a, b) => a + b) / games;
    final sd = sqrt(diffs.fold(0.0, (s, d) => s + pow(d - gain, 2)) / games);
    final mean = scores.reduce((a, b) => a + b) / games;
    print(
      '${name.padRight(12)} ${mean.toStringAsFixed(2).padLeft(6)} '
      '${(gain >= 0 ? '+' : '') + gain.toStringAsFixed(2)}  '
      '${(1.96 * sd / sqrt(games)).toStringAsFixed(2)}   '
      '${(toYou / games).toStringAsFixed(1).padLeft(10)}   '
      '${(watch.elapsedMilliseconds / max(1, moves)).toStringAsFixed(1).padLeft(10)}'
      '${(misfires / games).toStringAsFixed(2).padLeft(13)}'
      '${(100 * scores.where((s) => s == 25).length / games).toStringAsFixed(0).padLeft(5)}%',
    );
  }
}
