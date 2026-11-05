import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hanabi/game/coop.dart';
import 'package:hanabi/sim/selfplay_bot.dart';

/// The self-play bot must see exactly what it saw in training: the Dart
/// encoding against the Python one (rl/export_selfplay_parity.py), turn by
/// turn, on the reference games.
void main() {
  final fixture = File('rl/fixtures/selfplay_obs.json');

  test('observations and legal moves match the training encoding', () {
    if (!fixture.existsSync()) {
      markTestSkipped('run rl/export_selfplay_parity.py first');
      return;
    }
    final games = jsonDecode(fixture.readAsStringSync()) as List;
    var checked = 0;
    for (final g in games.cast<Map<String, dynamic>>()) {
      final game = CoopGame(
        players: g['players'] as int,
        deck: parseDeck(g['deck'] as String),
      );
      final moves = (g['moves'] as List).cast<String>();
      final steps = (g['steps'] as List).cast<Map<String, dynamic>>();
      for (var t = 0; t < moves.length; t++) {
        final o = SelfPlayBot.observe(game);
        final expected = List<double>.filled(SelfPlayBot.obsSize, 0);
        final idx = (steps[t]['i'] as List).cast<int>();
        final val = (steps[t]['v'] as List).cast<num>();
        for (var k = 0; k < idx.length; k++) {
          expected[idx[k]] = val[k].toDouble();
        }
        for (var i = 0; i < SelfPlayBot.obsSize; i++) {
          expect(
            o[i],
            closeTo(expected[i], 1e-5),
            reason: 'move $t, feature $i',
          );
        }
        final mask = SelfPlayBot.legal(game);
        expect(
          [
            for (var a = 0; a < mask.length; a++)
              if (mask[a]) a,
          ],
          (steps[t]['mask'] as List).cast<int>(),
          reason: 'move $t',
        );
        game.apply(CoopMove.parse(moves[t]));
        checked++;
      }
    }
    expect(checked, greaterThan(1000));
  });

  test('the shipped model plays legal moves to the end', () {
    final model = File('assets/models/coop_selfplay.json');
    final bot = SelfPlayBot(
      jsonDecode(model.readAsStringSync()) as Map<String, dynamic>,
    );
    for (var players = 2; players <= 4; players++) {
      final game = CoopGame(
        players: players,
        deck: parseDeck(
          '1R1G1B1Y1W2R2G2B2Y2W3R3G3B3Y3W4R4G4B4Y4W5R5G5B5Y5W1R1G1B1Y1W2R2G2B2Y2W3R3G3B3Y3W4R4G4B4Y4W1R1G1B1Y1W1*2*3*4*5*',
        ),
      );
      while (!game.isOver) {
        final move = bot.decide(game);
        expect(game.isLegal(move), isTrue);
        game.apply(move);
      }
    }
  });
}
