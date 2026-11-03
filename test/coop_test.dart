import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hanabi/game/card.dart';
import 'package:hanabi/game/coop.dart';
import 'package:hanabi/game/game.dart';
import 'package:hanabi/sim/coop_bot.dart';
import 'package:hanabi/sim/simulated_player.dart';

void main() {
  test('hands of five, or four with four players', () {
    for (final (players, size) in [(2, 5), (3, 5), (4, 4)]) {
      final game = CoopGame(players: players, random: Random(1));
      expect(game.hands.length, players);
      expect(game.hands.every((h) => h.length == size), isTrue);
      expect(game.deckSize, 55 - players * size);
    }
  });

  test('turns go round, and a hint marks only the receiver\'s cards', () {
    final game = CoopGame(players: 3, random: Random(2));
    final card = game.hands[1].first;
    final touched = game.hint(1, NumberHint(card.number));
    expect(touched, contains(card));
    expect(card.knownNumber, isTrue);
    expect(game.hands[0].every((c) => !c.knownNumber), isTrue);
    expect(game.hints, maxHints - 1);
    expect(game.current, 1);
    game.discard(0);
    expect(game.current, 2);
    expect(game.hints, maxHints);
  });

  test('a player sees the other hands but not their own', () {
    final game = CoopGame(players: 2, random: Random(3));
    final view = game.viewFor(0);
    expect(view.hand.map((c) => '$c'), game.hands[0].map((c) => '$c'));
    expect(view.inSight.map((c) => '$c'), game.hands[1].map((c) => '$c'));
    // Seeing a card rules it out of their own hand when all copies show.
    final pv = PlayerView(view);
    expect(pv.candidates(0), isNotEmpty);
  });

  test('when the deck runs out, everyone plays once more', () {
    final game = CoopGame(players: 3, random: Random(4));
    while (game.deckSize > 0) {
      game.discard(0);
    }
    final last = (game.current + 2) % 3; // who drew the last card
    expect(game.turnsLeft, 3);
    expect(game.isOver, isFalse);
    final seen = <int>[];
    while (!game.isOver) {
      seen.add(game.current);
      game.discard(0);
    }
    expect(seen.length, 3);
    expect(seen.last, last);
  });

  test('bots finish their games with a sensible score', () {
    const bot = CoopBot();
    for (var players = 2; players <= maxPlayers; players++) {
      var total = 0;
      for (var g = 0; g < 20; g++) {
        final game = CoopGame(players: players, random: Random(100 + g));
        var turns = 0;
        while (!game.isOver) {
          final move = bot.decide(game);
          if (move case CoopHint(:final to)) {
            expect(to, isNot(game.current));
            expect(game.hints, greaterThan(0));
          }
          game.apply(move);
          expect(++turns, lessThan(200));
        }
        total += game.score;
      }
      expect(total / 20, greaterThan(15));
    }
  });

  test('a joker played by a bot goes to a pile it fits', () {
    final deck = [
      GameCard(2, CardColor.joker),
      ...buildDeck(Random(5)).where((c) => !(c.isJoker && c.number == 2)),
    ];
    final game = CoopGame(players: 2, deck: deck);
    game.hands[0].first.reveal();
    game.fireworks.play(GameCard(1, CardColor.red));
    final move = const CoopBot().decide(game);
    expect(move, isA<CoopPlay>());
    expect((move as CoopPlay).target, CardColor.red);
  });
}
