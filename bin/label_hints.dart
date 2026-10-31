// Writes training data for rl/distill.py: plays games where the hint
// search gives every hint and the expert plays, and records, for each hint
// asked, what the hint giver saw and the average score each hint led to.
//
//   dart run bin/label_hints.dart <from seed> <to seed> <rounds> <out.jsonl>
//       [features=v4] [hints.json]
//
// One JSON object per line: "o" the observation, "m" the legal hints as
// 11 bits, "v" the average final score after each hint (0 when illegal).
// With a network file, that network gives the hints the games follow (the
// search only labels them): the data then covers the states the network
// gets itself into, as in DAgger.

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:hanabi/game/game.dart';
import 'package:hanabi/sim/expert.dart';
import 'package:hanabi/sim/hint_search.dart';
import 'package:hanabi/sim/rl_strategy.dart';
import 'package:hanabi/sim/simulation.dart';

String _f(double x) => x == 0 ? '0' : x.toStringAsFixed(4);

class _Recording extends HintStrategy {
  _Recording(this.search, this.rounds, this.out, this.encode, this.driver);
  final HintSearch search;
  final int rounds;
  final List<double> Function(Game) encode;

  /// Gives the hints the game follows, when not the search itself.
  final HintStrategy? driver;

  /// Written synchronously, so the file grows while the games run.
  final RandomAccessFile out;
  int written = 0;

  @override
  String get name => 'recording';

  @override
  Hint? choose(Game game) {
    final scored = search.evaluate(game, rounds: rounds);
    if (scored.isEmpty) return null;
    // With a single legal hint there is nothing to choose, or to learn.
    if (scored.length == 1) return scored.single.$1;
    final values = List.filled(actionCount, 0.0);
    final legal = List.filled(actionCount, 0);
    for (final (hint, value) in scored) {
      values[hintToAction(hint)] = value;
      legal[hintToAction(hint)] = 1;
    }
    out.writeStringSync(
      '${jsonEncode({
        'o': [for (final x in encode(game)) _f(x)].join(' '),
        'm': legal.join(''),
        'v': [for (final v in values) _f(v)].join(' '),
      })}\n',
    );
    written++;
    return driver?.choose(game) ??
        scored.reduce((a, b) => b.$2 > a.$2 ? b : a).$1;
  }
}

void main(List<String> args) {
  final from = int.parse(args[0]), to = int.parse(args[1]);
  final out = File(args[3]).openSync(mode: FileMode.append);
  final features = args.length > 4 ? args[4] : 'v4';
  final hints = _Recording(
    HintSearch(random: Random(from)),
    int.parse(args[2]),
    out,
    switch (features) {
      'v3' => encodeObservationV3,
      'v4' => encodeObservationV4,
      _ => throw ArgumentError('unknown feature set $features'),
    },
    args.length > 5
        ? RlStrategy(jsonDecode(File(args[5]).readAsStringSync()))
        : null,
  );
  final watch = Stopwatch()..start();
  var total = 0;
  for (var seed = from; seed < to; seed++) {
    final game = Game(random: Random(seed), strategy: hints);
    playOut(game, ExpertPlayer.tuned);
    total += game.score;
    if ((seed - from) % 50 == 49) {
      print('${seed - from + 1} games, ${hints.written} hints');
    }
  }
  out.closeSync();
  print(
    'seeds $from-$to: mean ${(total / (to - from)).toStringAsFixed(2)}, '
    '${hints.written} hints, ${(watch.elapsed.inSeconds / (to - from)).toStringAsFixed(1)} s/game',
  );
}
