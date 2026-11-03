import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hanabi/game/card.dart';
import 'package:hanabi/game/coop.dart';
import 'package:hanabi/game/game.dart';
import 'package:hanabi/sim/simulated_player.dart';
import 'package:hanabi/ui/move_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'a game is one line: the deck dealt, then the moves and advice',
    () async {
      SharedPreferences.setMockInitialValues({});
      final deck = buildDeck(Random(5));
      final game = Game(deck: List.of(deck), strategy: const DummyStrategy());
      await MoveLog.startGame(deck, mode: 'ai');
      final hint = game.hint()!;
      await MoveLog.record(HintMove(), hint: hint, advice: DiscardMove(2));
      await MoveLog.record(PlayMove(1), target: CardColor.blue);
      game.play(1, target: CardColor.blue);
      await MoveLog.record(DiscardMove(0), advice: DiscardMove(0));

      final lines = (await MoveLog.export()).split('\n');
      expect(lines.length, 1);
      final entry = jsonDecode(lines.single) as Map<String, dynamic>;
      expect(entry['mode'], 'ai');
      expect(entry['deck'], deck.map((c) => c.toString()).join());
      expect((entry['deck'] as String).length, 2 * deck.length);
      expect(entry['moves'], [
        MoveLog.describe(HintMove(), hint: hint),
        'p1B',
        'd0',
      ]);
      expect(entry['advice'], ['d2', '', 'd0']);
      expect(await MoveLog.length, 1);
    },
  );

  test('moves are described compactly', () {
    expect(MoveLog.describe(PlayMove(3)), 'p3');
    expect(MoveLog.describe(PlayMove(3), target: CardColor.red), 'p3R');
    expect(MoveLog.describe(DiscardMove(0)), 'd0');
    expect(MoveLog.describe(HintMove()), 'h');
    expect(MoveLog.describe(HintMove(), hint: NumberHint(5)), 'h5');
    expect(
      MoveLog.describe(HintMove(), hint: ColorHint(CardColor.joker)),
      'h*',
    );
  });

  test('a co-op game is logged with every player\'s move', () async {
    SharedPreferences.setMockInitialValues({});
    final deck = buildDeck(Random(7));
    await MoveLog.startGame(deck, mode: 'coop3');
    await MoveLog.recordCoop(CoopHint(2, NumberHint(5)));
    await MoveLog.recordCoop(CoopHint(0, ColorHint(CardColor.red)));
    await MoveLog.recordCoop(CoopPlay(3, target: CardColor.blue));
    await MoveLog.recordCoop(CoopDiscard(1));
    final lines = (await MoveLog.export()).split('\n');
    final entry = jsonDecode(lines.last) as Map<String, dynamic>;
    expect(entry['mode'], 'coop3');
    expect(entry['moves'], ['h2:5', 'h0:R', 'p3B', 'd1']);
  });
}
