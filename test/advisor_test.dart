import 'package:flutter_test/flutter_test.dart';
import 'package:hanabi/game/game.dart';
import 'package:hanabi/sim/simulated_player.dart';
import 'package:hanabi/ui/advisor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('advisor loads and suggests a legal move with odds per card', () async {
    final agent = await loadAdvisor;
    final game = Game();
    final advice = Advice(game, agent);
    expect(advice.odds.length, game.hand.length);
    for (final o in advice.odds) {
      expect(o.play, inInclusiveRange(0, 1));
      expect(o.discardLoss, greaterThanOrEqualTo(0));
    }
    // Nothing is known at the start: asking for a hint is the sensible move.
    expect(advice.move, isA<HintMove>());
  });
}
