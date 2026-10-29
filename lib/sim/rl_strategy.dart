import 'dart:math';

import '../game/card.dart';
import '../game/game.dart';
import 'simulated_player.dart';
import 'smart_strategies.dart';

/// Must match `rl/hanabi/encoding.py` exactly: the policy was trained on it.
const observationSize = handSize * slotFeatures + 5 + 30 + 3;
const slotFeatures = 19;

/// Actions 0-4 hint the numbers 1-5, actions 5-10 hint each color.
const actionCount = 11;

Hint actionToHint(int action) => action < 5
    ? NumberHint(action + 1)
    : ColorHint(CardColor.values[action - 5]);

int hintToAction(Hint hint) => switch (hint) {
  NumberHint(:final number) => number - 1,
  ColorHint(:final color) => 5 + color.index,
};

/// Turns what the hint giver sees into a fixed-size vector of numbers.
List<double> encodeObservation(Game game) {
  final obs = <double>[];
  final view = PlayerView(game);
  final playable = game.fireworks.playableCards();

  for (var i = 0; i < handSize; i++) {
    if (i >= game.hand.length) {
      obs.addAll(List.filled(slotFeatures, 0));
      continue;
    }
    final card = game.hand[i];
    obs
      ..add(1)
      ..addAll([for (var n = 1; n <= 5; n++) card.number == n ? 1 : 0])
      ..addAll([for (final c in CardColor.values) card.color == c ? 1 : 0])
      ..add(card.knownNumber ? 1 : 0)
      ..add(card.knownColor ? 1 : 0)
      ..add(playable.any(card.sameAs) ? 1 : 0)
      ..add(LookaheadStrategy.isCritical(game, card) ? 1 : 0)
      ..add(isDead(game, card) ? 1 : 0)
      ..add(view.surelyPlayable(i) ? 1 : 0)
      ..add(view.surelyUseless(i) ? 1 : 0);
  }

  for (final c in CardColor.piles) {
    obs.add((game.fireworks.top(c)?.number ?? 0) / 5);
  }

  for (final c in CardColor.values) {
    for (var n = 1; n <= 5; n++) {
      final copies = c == CardColor.joker ? 1 : numberDistribution[n - 1];
      final gone = game.discarded
          .where((d) => d.number == n && d.color == c)
          .length;
      obs.add(gone / copies);
    }
  }

  obs
    ..add(game.hints / maxHints)
    ..add(game.errors / allowedErrors)
    ..add(game.deckSize / 50);
  return obs;
}

/// Hints chosen by a small neural network trained with reinforcement
/// learning (see `rl/`). [weights] is the JSON written by `rl/export.py`.
class RlStrategy extends HintStrategy {
  RlStrategy(Map<String, dynamic> weights)
    : _layers = [
        for (final l in weights['layers'] as List)
          (
            [
              for (final row in l['w'] as List)
                [for (final v in row as List) (v as num).toDouble()],
            ],
            [for (final v in l['b'] as List) (v as num).toDouble()],
          ),
      ];

  final List<(List<List<double>>, List<double>)> _layers;

  @override
  String get name => 'rl';

  /// Scores for each of the [actionCount] actions; higher is preferred.
  List<double> logits(List<double> input) {
    var x = input;
    for (var l = 0; l < _layers.length; l++) {
      final (w, b) = _layers[l];
      final hidden = l < _layers.length - 1;
      x = [
        for (var o = 0; o < w.length; o++)
          _activate(_dot(w[o], x) + b[o], hidden),
      ];
    }
    return x;
  }

  static double _dot(List<double> a, List<double> b) {
    var s = 0.0;
    for (var i = 0; i < a.length; i++) {
      s += a[i] * b[i];
    }
    return s;
  }

  static double _activate(double v, bool hidden) {
    if (!hidden) return v;
    if (v.abs() > 20) return v.sign;
    final e = exp(2 * v);
    return (e - 1) / (e + 1); // tanh
  }

  @override
  Hint? choose(Game game) {
    final allowed = {for (final h in game.usefulHints) hintToAction(h)};
    if (allowed.isEmpty) return null;
    final scores = logits(encodeObservation(game));
    final best = allowed.reduce((a, b) => scores[b] > scores[a] ? b : a);
    return actionToHint(best);
  }
}

bool isDead(Game game, GameCard card) {
  final f = game.fireworks;
  final piles = card.isJoker ? CardColor.piles : [card.color];
  return piles.every((c) => (f.top(c)?.number ?? 0) >= card.number);
}
