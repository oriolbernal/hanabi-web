import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hanabi/game/card.dart';
import 'package:hanabi/game/game.dart';
import 'package:hanabi/sim/simulated_player.dart';
import 'package:hanabi/ui/move_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the state is kept as it was before the move, not after', () async {
    SharedPreferences.setMockInitialValues({});
    final game = Game(random: Random(5), strategy: const DummyStrategy());
    final future = MoveLog.record(game, DiscardMove(0), mode: 'ai');
    game.discard(0); // The screen moves on without waiting for the log.
    await future;
    final line = (await MoveLog.export()).split('\n').last;
    expect(line, contains('"hints":10'));
    expect(line, contains('"discarded":[]'));
  });

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
