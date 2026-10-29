// Writes reference turns for the Python player agent observation to match.
//
//   dart run bin/export_player_parity.dart [games]
//
// Games use the bold profile and dummy hints; every turn records the player
// observation, the move taken and what the exported agent would do there.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:hanabi/game/game.dart';
import 'package:hanabi/sim/player_policy.dart';
import 'package:hanabi/sim/simulated_player.dart';

void main(List<String> args) {
  final games = args.isNotEmpty ? int.parse(args[0]) : 200;
  final player = playerProfiles.last;
  final agent = PlayerPolicy(
    jsonDecode(File('assets/models/player_policy.json').readAsStringSync()),
  );
  final out = <Map<String, Object>>[];
  for (var seed = 0; seed < games; seed++) {
    final deck = buildDeck(Random(seed));
    final game = Game(deck: [for (final c in deck) c.copy()]);
    final turns = <Map<String, Object>>[];
    while (!game.isOver) {
      final obs = encodePlayerObservation(game);
      final move = player.decide(game);
      final action = switch (move) {
        PlayMove(:final index) => index,
        DiscardMove(:final index) => handSize + index,
        HintMove() => askAction,
      };
      final suggested = switch (agent.decide(game)) {
        PlayMove(:final index) => index,
        DiscardMove(:final index) => handSize + index,
        HintMove() => askAction,
      };
      turns.add({'obs': obs, 'action': action, 'agent': suggested});
      switch (move) {
        case PlayMove(:final index):
          game.play(
            index,
            target: game.needsTarget(index)
                ? bestJokerTarget(game, index)
                : null,
          );
        case DiscardMove(:final index):
          game.discard(index);
        case HintMove():
          if (game.hint() == null) game.discard(0);
      }
    }
    out.add({
      'deck': [
        for (final c in deck) [c.number, c.color.index],
      ],
      'score': game.score,
      'turns': turns,
    });
  }
  final file = File('rl/fixtures/player_parity.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(out));
  stdout.writeln('Wrote $games games to ${file.path}');
}
