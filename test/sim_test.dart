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
}
