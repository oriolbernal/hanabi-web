import 'package:flutter_test/flutter_test.dart';
import 'package:hanabi/game/card.dart';
import 'package:hanabi/game/fireworks.dart';
import 'package:hanabi/game/game.dart';

GameCard c(int n, CardColor color) => GameCard(n, color);

void main() {
  group('Fireworks', () {
    test('fits', () {
      final f = Fireworks();
      expect(f.fits(c(1, CardColor.red), CardColor.red), isTrue);
      expect(f.fits(c(2, CardColor.red), CardColor.red), isFalse);
      f.play(c(1, CardColor.red));
      expect(f.fits(c(1, CardColor.red), CardColor.red), isFalse);
      expect(f.fits(c(2, CardColor.joker), CardColor.red), isTrue);
    });

    test('full game reaches victory and 25 points', () {
      final f = Fireworks();
      for (final color in CardColor.piles) {
        expect(f.victory, isFalse);
        expect(f.play(c(2, color)), isFalse);
        for (var n = 1; n <= 5; n++) {
          expect(f.play(c(n, color)), isTrue);
        }
      }
      expect(f.victory, isTrue);
      expect(f.score, 25);
    });

    test('joker 1 moves to let a 2 of an empty color be played', () {
      final f = Fireworks();
      expect(f.play(c(1, CardColor.joker)), isTrue);
      expect(f.top(CardColor.red)!.isJoker, isTrue);
      expect(f.play(c(2, CardColor.blue)), isTrue);
      expect(f.top(CardColor.red), isNull);
      expect(f.pile(CardColor.blue).first.isJoker, isTrue);
    });

    test('joker 1 steps aside for the real 1', () {
      final f = Fireworks();
      f.play(c(1, CardColor.joker));
      expect(f.play(c(1, CardColor.red)), isTrue);
      expect(f.top(CardColor.red)!.color, CardColor.red);
      expect(f.top(CardColor.green)!.isJoker, isTrue);
    });

    test('joker is fixed once a card is played on top', () {
      final f = Fireworks();
      f.play(c(1, CardColor.joker));
      f.play(c(2, CardColor.red));
      expect(f.floatingJoker, isNull);
      expect(f.play(c(2, CardColor.blue)), isFalse);
    });

    test('higher jokers go on the chosen pile', () {
      final f = Fireworks();
      f.play(c(1, CardColor.green));
      expect(f.play(c(2, CardColor.joker), target: CardColor.red), isFalse);
      expect(f.play(c(2, CardColor.joker), target: CardColor.green), isTrue);
      expect(f.score, 2);
    });
  });

  group('Game', () {
    test('deck has 55 cards and a hand of 5 is dealt', () {
      expect(buildDeck().length, 55);
      final g = Game();
      expect(g.hand.length, handSize);
      expect(g.deckSize, 50);
      expect(g.isOver, isFalse);
    });

    test('misplay costs a life and goes to discards', () {
      final g = Game(
        deck: [
          c(3, CardColor.red),
          for (var i = 0; i < 9; i++) c(5, CardColor.white),
        ],
      );
      final r = g.play(0);
      expect(r, isA<PlayFailure>());
      expect(g.errors, allowedErrors - 1);
      expect(g.discarded.single.number, 3);
      expect(g.hand.length, handSize);
    });

    test('discard returns a hint token, capped at max', () {
      final g = Game();
      g.discard(0);
      expect(g.hints, maxHints);
      g.hint();
      g.discard(0);
      expect(g.hints, maxHints);
    });

    test('hint prefers playable cards and reveals them', () {
      final g = Game(
        deck: [
          c(1, CardColor.red),
          c(4, CardColor.green),
          c(1, CardColor.blue),
          c(4, CardColor.white),
          c(3, CardColor.yellow),
        ],
      );
      final h = g.hint();
      expect(h, NumberHint(1));
      expect(g.hints, maxHints - 1);
      expect(g.hand.where((x) => x.knownNumber).map((x) => x.number), [1, 1]);
    });

    test('game ends when hand and deck are empty', () {
      final g = Game(deck: [c(1, CardColor.red)]);
      g.play(0);
      expect(g.isOver, isTrue);
      expect(g.score, 1);
    });
  });
}
