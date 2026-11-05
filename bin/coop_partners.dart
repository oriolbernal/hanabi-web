// Partners for the co-op bots (lib/sim/partners.dart): which one plays most
// like the person, and how each bot does next to each of them.
//
//   dart run bin/coop_partners.dart fit rl/data/coop_moves*.jsonl
//       Share of the person's moves (seat 0 of the app's move log) each
//       partner makes in the same position, exactly and by kind of move.
//
//   dart run bin/coop_partners.dart cross [games] [players]
//       [--net=model.json ...] [--min-play=0.8] [--seed=N]
//       Mean score of each bot (the rules, and each network) with each
//       partner in seat 0 and the bot in every other seat, on the same
//       decks. Held-out partners are marked with *.

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:hanabi/game/coop.dart';
import 'package:hanabi/sim/coop_bot.dart';
import 'package:hanabi/sim/coop_net.dart';
import 'package:hanabi/sim/partners.dart';
import 'package:hanabi/sim/smart_strategies.dart';

void main(List<String> args) {
  switch (args.firstOrNull) {
    case 'fit':
      fit(args.skip(1).toList());
    case 'cross':
      cross(args.skip(1).toList());
    default:
      print('usage: coop_partners.dart fit <logs> | cross [games] [players]');
  }
}

String kind(CoopMove m) => switch (m) {
  CoopPlay() => 'play',
  CoopDiscard() => 'discard',
  CoopHint() => 'hint',
};

void fit(List<String> paths) {
  const names = [...PartnerZoo.trainPartners, ...PartnerZoo.heldOutPartners];
  final partners = {
    for (final n in names)
      if (!n.contains('noisy')) n: PartnerZoo.byName(n),
  };
  final exact = {for (final n in partners.keys) n: 0};
  final sameKind = {for (final n in partners.keys) n: 0};
  // Per kind of the person's move: how often the partner makes exactly it.
  final recall = {for (final n in partners.keys) n: <String, int>{}};
  var moves = 0;
  final byKind = <String, int>{};
  for (final path in paths) {
    for (final line in File(path).readAsLinesSync()) {
      if (!line.trim().endsWith('}')) continue;
      final e = jsonDecode(line) as Map<String, dynamic>;
      final mode = '${e['mode']}';
      if (!mode.startsWith('coop')) continue;
      final game = CoopGame(
        players: int.parse(mode.substring(4)),
        deck: parseDeck(e['deck'] as String),
      );
      for (final text in (e['moves'] as List).cast<String>()) {
        if (game.isOver) break;
        final move = CoopMove.parse(text);
        if (game.current == 0) {
          moves++;
          byKind.update(kind(move), (v) => v + 1, ifAbsent: () => 1);
          for (final MapEntry(key: n, value: p) in partners.entries) {
            final guess = p(game);
            if (guess.text == move.text) {
              exact[n] = exact[n]! + 1;
              recall[n]!.update(kind(move), (v) => v + 1, ifAbsent: () => 1);
            }
            if (kind(guess) == kind(move)) sameKind[n] = sameKind[n]! + 1;
          }
        }
        game.apply(move);
      }
    }
  }
  print('$moves moves of the person: $byKind\n');
  print('partner           same move  same kind     plays  discards     hints');
  final order = partners.keys.toList()
    ..sort((a, b) => exact[b]!.compareTo(exact[a]!));
  for (final n in order) {
    print(
      '${n.padRight(16)}  ${(100 * exact[n]! / moves).toStringAsFixed(1).padLeft(8)}%'
      '  ${(100 * sameKind[n]! / moves).toStringAsFixed(1).padLeft(8)}%'
      '${[
        for (final k in ['play', 'discard', 'hint']) '${(100 * (recall[n]![k] ?? 0) / byKind[k]!).toStringAsFixed(0).padLeft(9)}%',
      ].join()}',
    );
  }
}

void cross(List<String> args) {
  final numbers = args.where((a) => !a.startsWith('--')).toList();
  final games = numbers.isNotEmpty ? int.parse(numbers[0]) : 200;
  final players = numbers.length > 1 ? int.parse(numbers[1]) : 2;
  String? opt(String name) => [
    for (final a in args)
      if (a.startsWith('--$name=')) a.substring(name.length + 3),
  ].firstOrNull;
  final seed = int.parse(opt('seed') ?? '9000');
  final minPlay = double.parse(opt('min-play') ?? '0.8');
  final bots = <String, CoopPolicy>{
    'rules': const CoopBot().decide,
    for (final a in args)
      if (a.startsWith('--net='))
        File(a.substring(6)).uri.pathSegments.last.split('.').first: CoopNet(
          jsonDecode(File(a.substring(6)).readAsStringSync()),
          minPlayChance: minPlay,
        ).decide,
  };
  const partners = [...PartnerZoo.trainPartners, ...PartnerZoo.heldOutPartners];
  print('$players players, $games games from seed $seed; partner in seat 0\n');
  print('partner         ${[for (final b in bots.keys) b.padLeft(9)].join()}');
  final totals = {for (final b in bots.keys) b: 0.0};
  final heldOut = {for (final b in bots.keys) b: 0.0};
  // Bot discards of a card nobody can replace, and of those it had a hint
  // on, over every game.
  final critical = {for (final b in bots.keys) b: 0};
  final knownCritical = {for (final b in bots.keys) b: 0};
  for (final partnerName in partners) {
    final row = <String>[];
    for (final MapEntry(key: botName, value: bot) in bots.entries) {
      final partner = PartnerZoo.byName(partnerName, random: Random(seed));
      var sum = 0;
      for (var g = 0; g < games; g++) {
        final game = CoopGame(players: players, random: Random(seed + g));
        while (!game.isOver) {
          if (game.current == 0) {
            game.apply(partner(game));
            continue;
          }
          final move = bot(game);
          if (move case CoopDiscard(:final index)) {
            final c = game.hands[game.current][index];
            if (LookaheadStrategy.isCritical(game.viewFor(game.current), c)) {
              critical[botName] = critical[botName]! + 1;
              if (c.knownNumber || c.knownColor) {
                knownCritical[botName] = knownCritical[botName]! + 1;
              }
            }
          }
          game.apply(move);
        }
        sum += game.score;
      }
      final mean = sum / games;
      totals[botName] = totals[botName]! + mean;
      if (PartnerZoo.heldOutPartners.contains(partnerName)) {
        heldOut[botName] = heldOut[botName]! + mean;
      }
      row.add(mean.toStringAsFixed(2).padLeft(9));
    }
    final mark = PartnerZoo.heldOutPartners.contains(partnerName) ? '*' : ' ';
    print('${(partnerName + mark).padRight(16)}${row.join()}');
  }
  print(
    '\nmean            ${[for (final b in bots.keys) (totals[b]! / partners.length).toStringAsFixed(2).padLeft(9)].join()}',
  );
  print(
    'held-out mean   ${[for (final b in bots.keys) (heldOut[b]! / PartnerZoo.heldOutPartners.length).toStringAsFixed(2).padLeft(9)].join()}',
  );
  final all = games * partners.length;
  print(
    'critical disc.  ${[for (final b in bots.keys) (critical[b]! / all).toStringAsFixed(2).padLeft(9)].join()}  per game',
  );
  print(
    '  ...hinted     ${[for (final b in bots.keys) (knownCritical[b]! / all).toStringAsFixed(2).padLeft(9)].join()}  per game',
  );
}
