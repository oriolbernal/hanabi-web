import 'package:flutter_test/flutter_test.dart';
import 'package:hanabi/game/card.dart';
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

  test(
    'discards a known 3 rather than an unknown card that may be a 5',
    () async {
      // Reported from a real game: blue 1 played, a yellow 2 and a white 4
      // discarded, cards 1 and 3 known to be 3s. The unknown card 4 was the
      // only blue 5; losing it costs no points yet, but spends the joker 5.
      final hand = [
        GameCard(3, CardColor.red),
        GameCard(4, CardColor.green),
        GameCard(3, CardColor.green),
        GameCard(5, CardColor.blue),
        GameCard(2, CardColor.white),
      ];
      final gone = [
        GameCard(1, CardColor.blue),
        GameCard(2, CardColor.yellow),
        GameCard(4, CardColor.white),
      ];
      final rest = buildDeck();
      for (final c in [...hand, ...gone]) {
        rest.removeAt(rest.indexWhere((d) => d.sameAs(c)));
      }
      final game = Game(deck: [...hand, ...rest])
        ..hints = 4
        ..discarded.addAll(gone.skip(1));
      game.fireworks.play(gone[0]);
      game.applyHint(NumberHint(3));

      final view = PlayerView(game);
      expect(view.expectedDiscardLoss(3), 0);
      expect(
        view.expectedDiscardRisk(3),
        greaterThan(view.expectedDiscardRisk(0)),
      );

      final move = Advice(game, await loadAdvisor).move;
      expect(move, isA<DiscardMove>());
      expect([0, 2], contains((move as DiscardMove).index));
    },
  );
}
