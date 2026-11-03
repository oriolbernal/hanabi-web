import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hanabi/game/card.dart';
import 'package:hanabi/game/coop.dart';
import 'package:hanabi/game/game.dart';
import 'package:hanabi/sim/coop_bot.dart';
import 'package:hanabi/sim/coop_search.dart';
import 'package:hanabi/sim/simulated_player.dart';

void main() {
  test('hands of five, whatever the number of players', () {
    for (final (players, size) in [(2, 5), (3, 5), (4, 5)]) {
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

  test('an imagined deal keeps what the player knows and sees', () {
    final game = CoopGame(players: 3, random: Random(11));
    game.hint(1, NumberHint(game.hands[1][2].number)); // player 0 tells 1
    game.hint(2, NumberHint(game.hands[2][0].number)); // player 1 tells 2
    game.hint(1, ColorHint(game.hands[1][0].color)); // player 2 tells 1
    final seen = [
      for (final p in [0, 2]) game.hands[p].join(),
    ];
    String unseen(CoopGame g) =>
        (CoopGame.copy(g).hands[1].map((c) => '$c').toList()..sort()).join();
    for (var seed = 0; seed < 30; seed++) {
      final imagined = CoopGame.imagined(game, 1, Random(seed));
      expect([
        for (final p in [0, 2]) imagined.hands[p].join(),
      ], seen);
      expect(imagined.deckSize, game.deckSize);
      expect(unseen(imagined).length, unseen(game).length);
      for (var i = 0; i < 5; i++) {
        final real = game.hands[1][i], card = imagined.hands[1][i];
        if (real.knownNumber) expect(card.number, real.number);
        if (real.knownColor) expect(card.color, real.color);
        expect(real.notNumbers.contains(card.number), isFalse);
        expect(real.notColors.contains(card.color), isFalse);
      }
    }
  });

  test('searching bots finish games with legal moves', () {
    final search = CoopSearch(rounds: 8, random: Random(1));
    for (var g = 0; g < 4; g++) {
      final game = CoopGame(players: 2 + g % 3, random: Random(200 + g));
      while (!game.isOver) {
        final move = search.decide(game);
        if (move case CoopHint(:final to)) expect(to, isNot(game.current));
        if (move case CoopPlay(:final index, :final target)
            when game.needsTarget(index)) {
          expect(target, isNotNull);
        }
        game.apply(move);
      }
      expect(game.score, greaterThan(5));
    }
  });
}
