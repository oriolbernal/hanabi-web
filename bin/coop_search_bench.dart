// Co-op bots that search against the rule bots, on the same decks, with
// seat 0 a model of the person (or a bot of the same kind with --bots).
//
//   dart run bin/coop_search_bench.dart [games] [players] [rounds] [--bots]

// ignore_for_file: avoid_print

import 'dart:math';

import 'package:hanabi/game/coop.dart';
import 'package:hanabi/sim/coop_bot.dart';
import 'package:hanabi/sim/coop_search.dart';
import 'package:hanabi/sim/expert.dart';

void main(List<String> args) {
  final numbers = args.where((a) => !a.startsWith('--')).toList();
  final games = numbers.isNotEmpty ? int.parse(numbers[0]) : 40;
  final players = numbers.length > 1 ? int.parse(numbers[1]) : 4;
  final rounds = numbers.length > 2 ? int.parse(numbers[2]) : 24;
  final allBots = args.contains('--bots');
  const person = CoopBot(player: ExpertPlayer.human);
  const rules = CoopBot();
  final search = CoopSearch(rounds: rounds, random: Random(1));
  final diffs = <int>[];
  var rulesTotal = 0, searchTotal = 0;
  final watch = Stopwatch()..start();
  var decisions = 0;
  final toYou = [0, 0];
  for (var g = 0; g < games; g++) {
    int play(CoopMove Function(CoopGame) bot, int which) {
      final game = CoopGame(players: players, random: Random(9000 + g));
      while (!game.isOver) {
        final move = game.current == 0 && !allBots
            ? person.decide(game)
            : bot(game);
        if (move is CoopHint && move.to == 0 && game.current != 0) {
          toYou[which]++;
        }
        game.apply(move);
      }
      return game.score;
    }

    final a = play(rules.decide, 0);
    final b = play((game) {
      decisions++;
      return search.decide(game);
    }, 1);
    rulesTotal += a;
    searchTotal += b;
    diffs.add(b - a);
  }
  final gain = diffs.reduce((x, y) => x + y) / games;
  final sd = sqrt(diffs.fold(0.0, (s, d) => s + pow(d - gain, 2)) / games);
  print(
    '$players players, $games games, $rounds rounds'
    '${allBots ? ', all bots' : ', seat 0 = person model'}: '
    'rules ${(rulesTotal / games).toStringAsFixed(2)}, '
    'search ${(searchTotal / games).toStringAsFixed(2)} '
    '(${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(2)} ±${(1.96 * sd / sqrt(games)).toStringAsFixed(2)}), '
    '${(watch.elapsedMilliseconds / decisions).toStringAsFixed(0)} ms per search move, '
    'hints to seat 0: ${(toYou[0] / games).toStringAsFixed(1)} -> ${(toYou[1] / games).toStringAsFixed(1)}',
  );
}
