// Replays the cooperative games of the app's move log (dev mode, copy icon)
// and shows, turn by turn, what each bot did and what it would do now, with
// the hints the person (player 0) received.
//
//   dart run bin/coop_replay.dart rl/data/moves.jsonl

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:hanabi/game/card.dart';
import 'package:hanabi/game/coop.dart';
import 'package:hanabi/game/game.dart';
import 'package:hanabi/sim/coop_bot.dart';

CoopMove parse(String text) {
  switch (text[0]) {
    case 'p':
      final target = text.length > 2
          ? CardColor.values.firstWhere((c) => c.symbol == text[2])
          : null;
      return CoopPlay(int.parse(text[1]), target: target);
    case 'd':
      return CoopDiscard(int.parse(text[1]));
    default:
      final [to, what] = text.substring(1).split(':');
      final n = int.tryParse(what);
      return CoopHint(
        int.parse(to),
        n != null
            ? NumberHint(n)
            : ColorHint(CardColor.values.firstWhere((c) => c.symbol == what)),
      );
  }
}

void main(List<String> args) {
  for (final line in File(args[0]).readAsLinesSync()) {
    if (!line.trim().endsWith('}')) continue;
    final e = jsonDecode(line) as Map<String, dynamic>;
    final mode = '${e['mode']}';
    if (!mode.startsWith('coop')) continue;
    final players = int.parse(mode.substring(4));
    final text = e['deck'] as String;
    final deck = [
      for (var i = 0; i < text.length; i += 2)
        GameCard(
          int.parse(text[i]),
          CardColor.values.firstWhere((c) => c.symbol == text[i + 1]),
        ),
    ];
    final game = CoopGame(
      players: players,
      deck: deck,
      first: e['first'] as int? ?? 0,
    );
    print('\n=== ${e['at']}  $players players');
    var toYou = 0;
    for (final m in (e['moves'] as List).cast<String>()) {
      final who = game.current;
      final hands = [for (var p = 0; p < players; p++) game.hands[p].join(' ')]
          .join(' | ');
      final bot = who == 0
          ? ''
          : '  (bot now: ${describe(const CoopBot().decide(game))})';
      if (m.startsWith('h0:')) toYou++;
      print(
        '${'$who'.padLeft(2)} $m$bot   hints ${game.hints} score ${game.score}'
        '   $hands',
      );
      game.apply(parse(m));
    }
    print('score ${game.score}, hints to player 0: $toYou');
  }
}

String describe(CoopMove m) => switch (m) {
  CoopPlay(:final index, :final target) => 'p$index${target?.symbol ?? ''}',
  CoopDiscard(:final index) => 'd$index',
  CoopHint(:final to, hint: NumberHint(:final number)) => 'h$to:$number',
  CoopHint(:final to, hint: ColorHint(:final color)) => 'h$to:${color.symbol}',
};
