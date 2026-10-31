// ignore_for_file: avoid_print
// Per-decision regret of several hint givers against the search's values,
// on states visited when <driver> gives the hints.
//   dart run bin/_diag.dart <driver: search|model|expert> <model.json> <games> <rounds>
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:hanabi/game/game.dart';
import 'package:hanabi/sim/expert.dart';
import 'package:hanabi/sim/hint_search.dart';
import 'package:hanabi/sim/rl_strategy.dart';
import 'package:hanabi/sim/simulation.dart';

class _Probe extends HintStrategy {
  _Probe(this.driver, this.model, this.search, this.rounds);
  final String driver;
  final RlStrategy model;
  final HintSearch search;
  final int rounds;
  final random = Random(1);
  final regret = <String, List<double>>{};
  final agree = <String, int>{};
  int n = 0;

  @override
  String get name => 'probe';

  @override
  Hint? choose(Game game) {
    final scored = search.evaluate(game, rounds: rounds);
    if (scored.isEmpty) return null;
    final best = scored.reduce((a, b) => a + b);
    if (scored.length > 1) {
      n++;
      final values = {for (final s in scored) s.$1: s.$2};
      final picks = {
        'model': model.choose(game)!,
        'expert': const ExpertHints().choose(game)!,
        'random': scored[random.nextInt(scored.length)].$1,
        'search': best.$1,
      };
      picks.forEach((who, hint) {
        (regret[who] ??= []).add(best.$2 - values[hint]!);
        if (hint == best.$1) agree[who] = (agree[who] ?? 0) + 1;
      });
    }
    return switch (driver) {
      'model' => model.choose(game),
      'expert' => const ExpertHints().choose(game),
      _ => best.$1,
    };
  }
}

extension on (Hint, double) {
  (Hint, double) operator +((Hint, double) o) => o.$2 > $2 ? o : this;
}

void main(List<String> args) {
  final model = RlStrategy(
    jsonDecode(File(args[1]).readAsStringSync()),
    name: 'model',
  );
  final probe = _Probe(args[0], model, HintSearch(random: Random(9)), int.parse(args[3]));
  for (var s = 0; s < int.parse(args[2]); s++) {
    playOut(Game(random: Random(60000 + s), strategy: probe), ExpertPlayer.tuned);
  }
  print('driver ${args[0]}, ${probe.n} decisions, ${args[3]} rounds');
  for (final e in probe.regret.entries) {
    final mean = e.value.reduce((a, b) => a + b) / e.value.length;
    print('  ${e.key.padRight(7)} regret ${mean.toStringAsFixed(3)}  agrees ${((probe.agree[e.key] ?? 0) / probe.n * 100).toStringAsFixed(0)}%');
  }
}
