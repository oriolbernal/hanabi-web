// Writes reference co-op games for the Python port (rl/hanabi/coop.py) to
// reproduce exactly: random legal moves (jokers on random piles, so misfires
// and joker stacks happen), and the whole state after every move.
//
//   dart run bin/export_coop_parity.dart [games]

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:hanabi/game/card.dart';
import 'package:hanabi/game/coop.dart';
import 'package:hanabi/game/game.dart';
import 'package:hanabi/sim/coop_bot.dart';
import 'package:hanabi/sim/coop_search.dart';

String digest(CoopGame g) {
  String card(GameCard c) =>
      '$c${c.knownNumber ? 'n' : '-'}${c.knownColor ? 'c' : '-'}'
      '${(c.notNumbers.toList()..sort()).join()}/'
      '${(c.notColors.toList()..sort((a, b) => a.index.compareTo(b.index))).map((x) => x.symbol).join()}';
  String received(ReceivedHint? r) {
    if (r == null) return '-';
    final what = switch (r.hint) {
      NumberHint(:final number) => '$number',
      ColorHint(:final color) => color.symbol,
    };
    return '${r.giver}:$what:${r.touched.join(',')}:${r.chop}:${r.focus}';
  }

  final floating = g.fireworks.floatingJoker;
  return [
    for (final hand in g.hands) hand.map(card).join(' '),
    [for (final c in CardColor.piles) g.fireworks.top(c)?.number ?? 0].join(),
    floating == null ? '-' : '${floating.index}',
    '${g.hints}',
    '${g.errors}',
    '${g.current}',
    '${g.deckSize}',
    g.discarded.map((c) => '$c').join(),
    g.received.map(received).join(' '),
    g.isOver ? 'over' : 'on',
    '${g.score}',
  ].join('|');
}

void main(List<String> args) {
  final games = args.isNotEmpty ? int.parse(args[0]) : 600;
  final out = <Map<String, Object>>[];
  for (var seed = 0; seed < games; seed++) {
    final random = Random(seed);
    final players = 2 + seed % 3;
    final deck = buildDeck(random);
    final game = CoopGame(
      players: players,
      deck: [for (final c in deck) c.copy()],
    );
    final moves = <String>[];
    final states = <String>[digest(game)];
    // Mostly the rules bot, so games run long and reach jokers and the
    // endgame; sometimes a random legal move, so odd states happen too.
    final noise = seed.isEven ? 0.1 : 0.5;
    while (!game.isOver) {
      final legal = CoopSearch.legalMoves(game);
      var move = random.nextDouble() < noise
          ? legal[random.nextInt(legal.length)]
          : CoopSearch.withTarget(
              game,
              const CoopBot(person: null).decide(game),
            );
      if (move case CoopPlay(:final index) when game.needsTarget(index)) {
        move = CoopPlay(
          index,
          target: CardColor.piles[random.nextInt(CardColor.piles.length)],
        );
      }
      moves.add(move.text);
      game.apply(move);
      states.add(digest(game));
    }
    out.add({
      'players': players,
      'deck': deckText(deck),
      'moves': moves,
      'states': states,
    });
  }
  final file = File('rl/fixtures/coop_parity.json')
    ..createSync(recursive: true);
  file.writeAsStringSync(jsonEncode(out));
  print('Wrote $games games to ${file.path}');
}
