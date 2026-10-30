import 'package:flutter_test/flutter_test.dart';
import 'package:hanabi/game/card.dart';
import 'package:hanabi/game/game.dart';
import 'package:hanabi/ui/game_screen.dart';

void main() {
  test('a red card cannot be a 4 once both red 4s are discarded', () {
    final hand = [
      GameCard(2, CardColor.red),
      GameCard(3, CardColor.green),
      GameCard(1, CardColor.blue),
      GameCard(5, CardColor.white),
      GameCard(2, CardColor.yellow),
    ];
    final fours = [GameCard(4, CardColor.red), GameCard(4, CardColor.red)];
    final rest = buildDeck();
    for (final c in [...hand, ...fours]) {
      rest.removeAt(rest.indexWhere((d) => d.sameAs(c)));
    }
    final game = Game(deck: [...hand, ...rest])..discarded.addAll(fours);
    game.applyHint(ColorHint(CardColor.red));

    final possible = possibleCards(game);
    expect(possible[0].numbers, [1, 2, 3, 5]);
    expect(possible[0].colors, [CardColor.red]);
    // Hints alone said nothing about the numbers of the other cards.
    expect(possible[1].numbers, [1, 2, 3, 4, 5]);
    expect(possible[1].colors, isNot(contains(CardColor.red)));
  });
}
