import 'package:flutter_test/flutter_test.dart';
import 'package:hanabi/game/card.dart';
import 'package:hanabi/game/game.dart';
import 'package:hanabi/sim/rl_strategy.dart';
import 'package:hanabi/sim/simulated_player.dart';
import 'package:hanabi/sim/simulation.dart';
import 'package:hanabi/sim/smart_strategies.dart';

void main() {
  test('same seed plays the same game', () {
    final a = playGame(const DummyStrategy(), const CarefulPlayer(), 42);
    final b = playGame(const DummyStrategy(), const CarefulPlayer(), 42);
    expect((a.score, a.turns), (b.score, b.turns));
  });

  test('careful player only plays cards it is sure about', () {
    final r = benchmark(
      const DummyStrategy(),
      const CarefulPlayer(),
      games: 200,
    );
    expect(r.burnOutRate, 0);
    expect(r.results.every((g) => g.errorsLeft == allowedErrors), isTrue);
  });

  test('a known 1 is playable on an empty board', () {
    final game = Game(
      deck: [for (var i = 0; i < 5; i++) GameCard(1, CardColor.red)],
    );
    game.hand.first.knownNumber = true;
    final move = const CarefulPlayer().decide(game);
    expect(move, isA<PlayMove>());
  });

  test('a card whose pile is complete is useless', () {
    final game = Game(
      deck: [
        GameCard(1, CardColor.red),
        for (var i = 0; i < 4; i++) GameCard(4, CardColor.blue),
      ],
    );
    game.fireworks.play(GameCard(1, CardColor.red));
    game.hand.first.reveal();
    expect(PlayerView(game).surelyUseless(0), isTrue);
  });

  test('dummy beats random', () {
    const player = CarefulPlayer();
    final dummy = benchmark(const DummyStrategy(), player, games: 500);
    final random = benchmark(RandomStrategy(), player, games: 500);
    expect(dummy.mean, greaterThan(random.mean));
  });

  test('a copied game is independent of the original', () {
    final game = Game();
    final copy = Game.copy(game)..applyHint(NumberHint(game.hand.first.number));
    copy.discard(0);
    expect(game.hand.first.knownNumber, isFalse);
    expect(game.discarded, isEmpty);
    expect(game.hand.length, handSize);
  });

  test('lookahead beats dummy', () {
    const player = CarefulPlayer();
    final dummy = benchmark(const DummyStrategy(), player, games: 500);
    final lookahead = benchmark(const LookaheadStrategy(), player, games: 500);
    expect(lookahead.mean, greaterThan(dummy.mean));
  });

  test('observation has the size the policy expects', () {
    expect(encodeObservation(Game()).length, observationSize);
  });

  test('rl strategy only picks useful hints', () {
    // A network that always prefers the last action (joker hint).
    final weights = {
      'layers': [
        {
          'w': [List.filled(observationSize, 0.0)],
          'b': [1.0],
        },
        {
          'w': [
            for (var a = 0; a < actionCount; a++) [a.toDouble()],
          ],
          'b': List.filled(actionCount, 0.0),
        },
      ],
    };
    final game = Game();
    final hint = RlStrategy(weights).choose(game)!;
    expect(game.usefulHints, contains(hint));
  });

  test('playFirst hints a 1 on an empty board when the hand has one', () {
    // A network that always prefers color hints.
    final weights = {
      'features': 'v1',
      'layers': [
        {
          'w': [List.filled(observationSize, 0.0)],
          'b': [1.0],
        },
        {
          'w': [
            for (var a = 0; a < actionCount; a++) [a < 5 ? -1.0 : 1.0],
          ],
          'b': List.filled(actionCount, 0.0),
        },
      ],
    };
    final game = Game(
      deck: [
        GameCard(2, CardColor.green),
        GameCard(1, CardColor.green),
        GameCard(4, CardColor.green),
        GameCard(3, CardColor.red),
        GameCard(5, CardColor.blue),
      ],
    );
    expect(RlStrategy(weights).choose(game), isA<ColorHint>());
    expect(RlStrategy(weights, playFirst: true).choose(game), NumberHint(1));
  });

  test('two known 1s: 100% each, then 13/15 after one is played', () {
    final game = Game(
      deck: [
        GameCard(1, CardColor.red),
        GameCard(1, CardColor.blue),
        GameCard(4, CardColor.green),
        GameCard(3, CardColor.white),
        GameCard(5, CardColor.yellow),
        GameCard(2, CardColor.green),
      ],
    )..applyHint(NumberHint(1));
    expect(PlayerView(game).playProbability(0), 1);
    expect(PlayerView(game).playProbability(1), 1);

    game.play(0); // the red 1
    final other = game.hand.indexWhere((c) => c.number == 1);
    // Red: 2 copies left; green, blue, yellow, white: 3 each; joker: 1.
    expect(PlayerView(game).playProbability(other), closeTo(13 / 15, 1e-9));
  });

  test('a bold player plays risky cards a careful one would not', () {
    final bold = playerProfiles.last;
    final careful = benchmark(
      const DummyStrategy(),
      const CarefulPlayer(),
      games: 300,
    );
    final risky = benchmark(const DummyStrategy(), bold, games: 300);
    expect(careful.results.every((r) => r.errorsLeft == allowedErrors), isTrue);
    expect(risky.results.any((r) => r.errorsLeft < allowedErrors), isTrue);
  });

  test('a hint rules out that color on the cards it does not touch', () {
    final game = Game(
      deck: [
        GameCard(3, CardColor.red),
        GameCard(4, CardColor.blue),
        GameCard(1, CardColor.green),
        GameCard(2, CardColor.green),
        GameCard(5, CardColor.green),
      ],
    )..applyHint(ColorHint(CardColor.green));
    expect(game.hand[0].notColors, {CardColor.green});
    expect(game.hand[1].notColors, {CardColor.green});
    expect(game.hand[2].knownColor, isTrue);
    final view = PlayerView(game);
    expect(view.candidates(0).any((c) => c.$2 == CardColor.green), isFalse);
  });

  test('ruling out four numbers reveals the fifth', () {
    final card = GameCard(5, CardColor.red);
    for (final n in [1, 2, 3, 4]) {
      card.ruleOutNumber(n);
    }
    expect(card.knownNumber, isTrue);
  });

  test(
    'max score: a joker covers one lost 5, a second lost 5 costs a point',
    () {
      final game = Game(
        deck: [for (var i = 0; i < 10; i++) GameCard(1, CardColor.red)],
      );
      expect(game.maxScore(), 25);
      game.discarded.add(GameCard(5, CardColor.red));
      expect(game.maxScore(), 25);
      expect(game.discardLoss(GameCard(5, CardColor.blue)), 1);
      game.discarded.add(GameCard(5, CardColor.blue));
      expect(game.maxScore(), 24);
    },
  );

  test(
    'losing both 4s of a color caps that pile at 3 unless the joker helps',
    () {
      final game = Game(
        deck: [for (var i = 0; i < 10; i++) GameCard(1, CardColor.red)],
      );
      game.discarded.addAll([
        GameCard(4, CardColor.green),
        GameCard(4, CardColor.green),
      ]);
      expect(game.maxScore(), 25); // the joker 4 fills the gap
      game.discarded.add(GameCard(4, CardColor.joker));
      expect(game.maxScore(), 23); // green stops at 3
    },
  );

  test('playFirst prefers "it is a 1" (likely playable) over "it is red"', () {
    // A network that always prefers color hints.
    final weights = {
      'features': 'v1',
      'layers': [
        {
          'w': [List.filled(observationSize, 0.0)],
          'b': [1.0],
        },
        {
          'w': [
            for (var a = 0; a < actionCount; a++) [a < 5 ? -1.0 : 1.0],
          ],
          'b': List.filled(actionCount, 0.0),
        },
      ],
    };
    final game = Game(
      deck: [
        GameCard(1, CardColor.green),
        GameCard(1, CardColor.red),
        GameCard(4, CardColor.blue),
        GameCard(3, CardColor.white),
        GameCard(5, CardColor.yellow),
        GameCard(2, CardColor.yellow),
      ],
    );
    game.play(0); // green 1 is on the table: a 1 is no longer surely playable
    expect(RlStrategy(weights, playFirst: true).choose(game), NumberHint(1));
  });
}
