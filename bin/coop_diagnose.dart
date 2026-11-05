// Looks at the person's cooperative games in the app's move log (dev mode):
// what the hints between the person (seat 0) and the bots meant, and what
// the receiver did with them.
//
//   dart run bin/coop_diagnose.dart rl/data/coop_moves.jsonl [more.jsonl]
//
// A hint "points at a play" when one of the cards it touches fits a pile
// right now. For each hint we follow the touched cards until the
// receiver's next turns: played (fit or misfire), discarded, still held.

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:hanabi/game/coop.dart';
import 'package:hanabi/game/game.dart';
import 'package:hanabi/sim/simulated_player.dart';

class Tally {
  int hints = 0, pointsAtPlay = 0, oneCard = 0;
  int playedWithin1 = 0, playedLater = 0, discarded = 0, never = 0;
  double beliefSum = 0;

  @override
  String toString() =>
      'hints $hints, pointing at a play $pointsAtPlay '
      '(one card touched: $oneCard); that card: played next turn '
      '$playedWithin1, later $playedLater, discarded $discarded, never '
      '$never; receiver\'s own p(fits) after the hint: '
      '${pointsAtPlay == 0 ? '-' : (beliefSum / pointsAtPlay).toStringAsFixed(2)}';
}

void main(List<String> args) {
  final byPlayers = <int, ({Tally toBot, Tally toPerson})>{};
  final scores = <int, List<int>>{};
  for (final path in args) {
    for (final line in File(path).readAsLinesSync()) {
      if (!line.trim().endsWith('}')) continue;
      final e = jsonDecode(line) as Map<String, dynamic>;
      final mode = '${e['mode']}';
      if (!mode.startsWith('coop')) continue;
      final players = int.parse(mode.substring(4));
      final tally = byPlayers.putIfAbsent(
        players,
        () => (toBot: Tally(), toPerson: Tally()),
      );
      final game = CoopGame(
        players: players,
        deck: parseDeck(e['deck'] as String),
      );
      final moves = [
        for (final m in (e['moves'] as List).cast<String>()) CoopMove.parse(m),
      ];
      for (var i = 0; i < moves.length && !game.isOver; i++) {
        final move = moves[i];
        if (move case CoopHint(:final to, :final hint)) {
          final t = to == 0 ? tally.toPerson : tally.toBot;
          t.hints++;
          final playable = game.fireworks.playableCards();
          final touched = [
            for (final c in game.hands[to])
              if (switch (hint) {
                NumberHint(:final number) => c.number == number,
                ColorHint(:final color) => c.color == color,
              })
                c,
          ];
          final target = touched.where((c) => playable.any(c.sameAs));
          if (target.isNotEmpty) {
            t.pointsAtPlay++;
            if (touched.length == 1) t.oneCard++;
            final card = target.first;
            // Follow the card through the receiver's next turns.
            final copy = CoopGame.copy(game)..apply(move);
            final mine = copy.hands[to].indexWhere(
              (c) => c.sameAs(card) && (c.knownNumber || c.knownColor),
            );
            if (mine >= 0) {
              t.beliefSum += PlayerView(copy.viewFor(to)).playProbability(mine);
            }
            var turns = 0, outcome = 'never';
            final replay = CoopGame.copy(game)..apply(move);
            for (var j = i + 1; j < moves.length && !replay.isOver; j++) {
              final who = replay.current;
              final m = moves[j];
              if (who == to) {
                turns++;
                final index = switch (m) {
                  CoopPlay(:final index) || CoopDiscard(:final index) => index,
                  _ => -1,
                };
                if (index >= 0 && replay.hands[to][index].sameAs(card)) {
                  outcome = m is CoopPlay
                      ? (turns == 1 ? 'next' : 'later')
                      : 'discarded';
                  break;
                }
              }
              replay.apply(m);
            }
            switch (outcome) {
              case 'next':
                t.playedWithin1++;
              case 'later':
                t.playedLater++;
              case 'discarded':
                t.discarded++;
              default:
                t.never++;
            }
          }
        }
        game.apply(move);
      }
      scores.putIfAbsent(players, () => []).add(game.score);
    }
  }
  for (final MapEntry(key: players, value: t) in byPlayers.entries) {
    print('\n== $players players, scores ${scores[players]}');
    print('person -> bots: ${t.toBot}');
    print('bots -> person: ${t.toPerson}');
  }
}
