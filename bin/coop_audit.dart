// Audits the bots' moves in the person's cooperative games (dev-mode move
// log): costly discards, misfires and hints that point nowhere, per game.
//
//   dart run bin/coop_audit.dart rl/data/coop_moves_3.jsonl [--since=2026-11-04T15]

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:hanabi/game/coop.dart';
import 'package:hanabi/game/game.dart';
import 'package:hanabi/sim/smart_strategies.dart';

void main(List<String> args) {
  final since = [
    for (final a in args)
      if (a.startsWith('--since=')) a.substring(8),
  ].firstOrNull;
  var games = 0, botMoves = 0, botHints = 0;
  var critical = 0, criticalKnown = 0, playableDiscard = 0, misfires = 0;
  var noPlayHint = 0, fives = 0, fivesKnown = 0;
  final scores = <String, List<int>>{};
  for (final path in args.where((a) => !a.startsWith('--'))) {
    for (final line in File(path).readAsLinesSync()) {
      if (!line.trim().endsWith('}')) continue;
      final e = jsonDecode(line) as Map<String, dynamic>;
      final mode = '${e['mode']}';
      if (!mode.startsWith('coop')) continue;
      if (since != null && (e['at'] as String).compareTo(since) < 0) continue;
      final moves = (e['moves'] as List).cast<String>();
      if (moves.isEmpty) continue;
      games++;
      final game = CoopGame(
        players: int.parse(mode.substring(4)),
        deck: parseDeck(e['deck'] as String),
      );
      for (final text in moves) {
        if (game.isOver) break;
        final move = CoopMove.parse(text);
        final who = game.current;
        if (who != 0) {
          botMoves++;
          final view = game.viewFor(who);
          switch (move) {
            case CoopDiscard(:final index):
              final c = game.hands[who][index];
              if (LookaheadStrategy.isCritical(view, c)) {
                critical++;
                if (c.knownNumber || c.knownColor) criticalKnown++;
                if (c.number == 5) {
                  fives++;
                  if (c.knownNumber) fivesKnown++;
                }
              }
              if (game.fireworks.playableCards().any(c.sameAs)) {
                playableDiscard++;
              }
            case CoopPlay():
              final lives = game.errors;
              final copy = CoopGame.copy(game)..apply(move);
              if (copy.errors < lives) misfires++;
            case CoopHint(:final to, :final hint):
              botHints++;
              final fits = game.fireworks.playableCards();
              final touchesPlay = game.hands[to].any(
                (c) =>
                    fits.any(c.sameAs) &&
                    switch (hint) {
                      NumberHint(:final number) => c.number == number,
                      ColorHint(:final color) => c.color == color,
                    },
              );
              if (!touchesPlay) noPlayHint++;
          }
        }
        game.apply(move);
      }
      scores.putIfAbsent(mode, () => []).add(game.score);
    }
  }
  print('$games games: $scores\n');
  print('bot moves $botMoves');
  print(
    '  discards of a card nobody else can replace: $critical '
    '($criticalKnown the bot had a hint on), of which 5s: $fives '
    '($fivesKnown known 5s)',
  );
  print('  discards of a card that fitted right then: $playableDiscard');
  print('  misfires: $misfires');
  print(
    '  hints: $botHints, of which touching no card that fits now: '
    '$noPlayHint',
  );
}
