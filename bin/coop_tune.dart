// Tunes the co-op bots: every config plays the same decks, with seat 0
// either a bot like the others or a model of the person (hints whenever a
// token is left, plays only what it knows; see the move log).
//
//   dart run bin/coop_tune.dart [games]

// ignore_for_file: avoid_print

import 'dart:math';

import 'package:hanabi/game/coop.dart';
import 'package:hanabi/sim/coop_bot.dart';
import 'package:hanabi/sim/expert.dart';

const person = CoopBot(player: ExpertPlayer.human);

final configs = <String, CoopBot>{
  'current': const CoopBot(),
  'idle first': const CoopBot(idleFirst: true),
  'min 50': const CoopBot(minValue: 50),
  'min 100': const CoopBot(minValue: 100),
  'min 150': const CoopBot(minValue: 150),
  'min 100 idle 100': const CoopBot(minValue: 100, idleBonus: 100),
  'idle first, min 100 idle 100': const CoopBot(
    idleFirst: true,
    minValue: 100,
    idleBonus: 100,
  ),
  'idle first, min 150 idle 100': const CoopBot(
    idleFirst: true,
    minValue: 150,
    idleBonus: 100,
  ),
};

void main(List<String> args) {
  final games = args.isNotEmpty ? int.parse(args[0]) : 200;
  for (final players in [4, 3, 2]) {
    print(
      '\n$players players, $games games'
      '              all bots   with you: score  hints to you / each bot',
    );
    for (final MapEntry(key: name, value: bot) in configs.entries) {
      final (botScore, _) = run(bot, bot, players, games);
      final (score, per) = run(bot, person, players, games);
      final others = [for (var p = 1; p < players; p++) per[p]];
      print(
        '${name.padRight(30)} ${botScore.toStringAsFixed(2)}'
        '      ${score.toStringAsFixed(2)}  ${per[0].toStringAsFixed(1)} / '
        '${(others.reduce((a, b) => a + b) / others.length).toStringAsFixed(1)}',
      );
    }
  }
}

(double, List<double>) run(CoopBot bot, CoopBot seat0, int players, int games) {
  var total = 0;
  final hints = List.filled(players, 0);
  for (var g = 0; g < games; g++) {
    final game = CoopGame(players: players, random: Random(7000 + g));
    while (!game.isOver) {
      final m = (game.current == 0 ? seat0 : bot).decide(game);
      if (m is CoopHint && game.current != 0) hints[m.to]++;
      game.apply(m);
    }
    total += game.score;
  }
  return (total / games, [for (final h in hints) h / games]);
}
