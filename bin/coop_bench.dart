// Cooperative games played only by bots, every seat a [CoopBot].
//
//   dart run bin/coop_bench.dart [games] [seed]

// ignore_for_file: avoid_print

import 'dart:math';

import 'package:hanabi/game/coop.dart';
import 'package:hanabi/sim/coop_bot.dart';

void main(List<String> args) {
  final games = args.isNotEmpty ? int.parse(args[0]) : 300;
  final seed = args.length > 1 ? int.parse(args[1]) : 0;
  const bot = CoopBot();
  print('players  mean  ±95%  perfect  lives lost  turns');
  for (var players = 2; players <= maxPlayers; players++) {
    final scores = <int>[];
    var perfect = 0, burned = 0, turns = 0;
    for (var g = 0; g < games; g++) {
      final game = CoopGame(players: players, random: Random(seed + g));
      while (!game.isOver) {
        game.apply(bot.decide(game));
        turns++;
      }
      scores.add(game.score);
      if (game.score == 25) perfect++;
      if (game.errors == 0) burned++;
    }
    final mean = scores.reduce((a, b) => a + b) / games;
    final sd = sqrt(scores.fold(0.0, (s, x) => s + pow(x - mean, 2)) / games);
    print(
      '${'$players'.padLeft(7)}  ${mean.toStringAsFixed(2)}  '
      '${(1.96 * sd / sqrt(games)).toStringAsFixed(2)}  '
      '${'${(100 * perfect / games).round()}%'.padLeft(7)}  '
      '${'${(100 * burned / games).round()}%'.padLeft(10)}  '
      '${(turns / games).toStringAsFixed(0).padLeft(5)}',
    );
  }
}
