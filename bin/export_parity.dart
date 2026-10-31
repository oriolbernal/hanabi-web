// Writes reference games for the Python port to reproduce exactly.
//
//   dart run bin/export_parity.dart [games]
//
// For each seed: the dealt deck, and at every hint the (v3) observation the
// policy would see and the hint the dummy strategy gave, plus final score.
// Seeds rotate through the simulated player profiles.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:hanabi/game/game.dart';
import 'package:hanabi/sim/expert.dart';
import 'package:hanabi/sim/rl_strategy.dart';
import 'package:hanabi/sim/simulated_player.dart';
import 'package:hanabi/sim/simulation.dart';

class _Recorder extends HintStrategy {
  final steps = <Map<String, Object>>[];

  @override
  String get name => 'recorder';

  @override
  Hint? choose(Game game) {
    final hint = const DummyStrategy().choose(game);
    if (hint != null) {
      steps.add({
        'obs': encodeObservationV3(game),
        'action': hintToAction(hint),
      });
    }
    return hint;
  }
}

void main(List<String> args) {
  final games = args.isNotEmpty ? int.parse(args[0]) : 1000;
  final out = [for (var seed = 0; seed < games; seed++) _record(seed)];
  final file = File('rl/fixtures/parity.json')..createSync(recursive: true);
  file.writeAsStringSync(jsonEncode(out));
  stdout.writeln('Wrote $games games to ${file.path}');
}

Map<String, Object> _record(int seed) {
  final deck = buildDeck(Random(seed));
  const players = [...playerProfiles, ExpertPlayer.tuned, ExpertPlayer.human];
  final player = players[seed % players.length];
  final recorder = _Recorder();
  final game = Game(deck: [for (final c in deck) c.copy()], strategy: recorder);
  final turns = playOut(game, player);
  return {
    'player': player.name,
    'deck': [
      for (final c in deck) [c.number, c.color.index],
    ],
    'score': game.score,
    'turns': turns,
    'steps': recorder.steps,
  };
}
