import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hanabi/game/card.dart';
import 'package:hanabi/game/game.dart';
import 'package:hanabi/sim/simulated_player.dart';
import 'package:hanabi/ui/move_log.dart';

void main() {
  test('a move is encoded with what the person saw', () {
    final game = Game(random: Random(3), strategy: const DummyStrategy());
    game.hint();
    final hinted = game.hand.indexWhere((c) => c.knownNumber || c.knownColor);
    final entry = MoveLog.encode(
      game,
      PlayMove(hinted),
      advice: HintMove(),
      mode: 'search',
    );
    expect(entry['move'], 'play $hinted');
    expect(entry['advice'], 'hint');
    expect(entry['mode'], 'search');
    expect(entry['hints'], 9);
    expect(entry['lives'], 3);
    expect(entry['deck'], game.deckSize);
    expect((entry['piles'] as List).length, CardColor.piles.length);
    final hand = entry['hand'] as List;
    expect(hand.length, handSize);
    final card = hand[hinted] as Map;
    expect(card['card'], game.hand[hinted].toString());
    expect(card['knownNumber'] || card['knownColor'], isTrue);
  });
}
