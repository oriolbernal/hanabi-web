// Writes training data for rl/coop_distill.py: co-op games where every bot
// seat is driven by the search (or by a network, --net=, as in DAgger) and,
// at each bot move, the search's average final score for each candidate.
// In even-seeded games seat 0 is the model of the person and is not
// labelled, so the bots also learn to play next to someone like you.
//
//   dart run bin/coop_label.dart <from seed> <to seed> <rounds> <out.jsonl>
//       [--net=model.json] [--rollout-net] [--players=2,3,4] [--person]
//
// --person puts the model of the person in seat 0 in every game.
//
// One JSON line per move: "s" the state features, "c" the features of each
// candidate, "v" the search's value of each candidate.

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:hanabi/game/coop.dart';
import 'package:hanabi/sim/coop_bot.dart';
import 'package:hanabi/sim/coop_features.dart';
import 'package:hanabi/sim/coop_net.dart';
import 'package:hanabi/sim/coop_search.dart';
import 'package:hanabi/sim/expert.dart';

String _f(double x) => x == 0 ? '0' : x.toStringAsFixed(4);

void main(List<String> args) {
  final from = int.parse(args[0]), to = int.parse(args[1]);
  final rounds = int.parse(args[2]);
  final out = File(args[3]).openSync(mode: FileMode.append);
  String? opt(String name) => [
    for (final a in args)
      if (a.startsWith('--$name=')) a.substring(name.length + 3),
  ].firstOrNull;
  final netPath = opt('net');
  final net = netPath == null
      ? null
      : CoopNet(jsonDecode(File(netPath).readAsStringSync()));
  final playerCounts = (opt('players') ?? '2,3,4')
      .split(',')
      .map(int.parse)
      .toList();
  final random = Random(from);
  // In games with the person, the imagined games play their seat the way
  // the person does (QuickPersonPolicy).
  CoopSearch searchFor(bool withPerson) => CoopSearch(
    rounds: rounds,
    random: random,
    person: withPerson ? 0 : null,
    rollout: args.contains('--rollout-net') && net != null ? net.decide : null,
  );
  const person = CoopBot(player: ExpertPlayer.human);
  var lines = 0, total = 0;
  final watch = Stopwatch()..start();
  for (var seed = from; seed < to; seed++) {
    final players = playerCounts[seed % playerCounts.length];
    final game = CoopGame(players: players, random: Random(seed));
    final withPerson = seed.isEven || args.contains('--person');
    final search = searchFor(withPerson);
    while (!game.isOver) {
      if (game.current == 0 && withPerson) {
        game.apply(person.decide(game));
        continue;
      }
      final scored = search.evaluate(game);
      if (scored.length > 1) {
        final f = CoopFeatures(game);
        out.writeStringSync(
          '${jsonEncode({
            's': [for (final x in f.state) _f(x)].join(' '),
            'c': [
              for (final (m, _) in scored) [for (final x in f.move(m)) _f(x)].join(' '),
            ],
            'v': [for (final (_, v) in scored) _f(v)].join(' '),
          })}\n',
        );
        lines++;
      }
      var best = 0;
      for (var m = 1; m < scored.length; m++) {
        if (scored[m].$2 > scored[best].$2) best = m;
      }
      game.apply(
        net != null
            ? net.decide(game)
            : CoopSearch.withTarget(game, scored[best].$1),
      );
    }
    total += game.score;
    if ((seed - from) % 50 == 49) {
      print(
        '${seed - from + 1} games, $lines moves, mean ${(total / (seed - from + 1)).toStringAsFixed(2)}, '
        '${watch.elapsed.inSeconds}s',
      );
    }
  }
  out.closeSync();
  print(
    'done: ${to - from} games, $lines moves, mean ${(total / (to - from)).toStringAsFixed(2)}',
  );
}
