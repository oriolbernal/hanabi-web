import 'dart:math';

import '../game/card.dart';
import '../game/game.dart';
import 'simulated_player.dart';
import 'smart_strategies.dart';

/// Must match `rl/hanabi/encoding.py` exactly: the policy was trained on it.
const observationSize = handSize * slotFeatures + 5 + 30 + 3;
const slotFeatures = 19;

/// Feature set v2 appends, for each action, what giving that hint would do.
const actionFeatures = 5;
const observationSizeV2 = observationSize + actionCount * actionFeatures;

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

/// v1 plus [encodeActionEffects].
List<double> encodeObservationV2(Game game) =>
    encodeObservation(game)..addAll(encodeActionEffects(game));

/// For each of the [actionCount] hints, [actionFeatures] numbers describing
/// its effect (all zero when the hint would reveal nothing):
/// change in surely playable cards, change in surely useless cards, cards
/// touched, touched cards that are really playable, touched critical cards.
List<double> encodeActionEffects(Game game) {
  (int, int) sure(Game g) {
    final view = PlayerView(g);
    var playable = 0, useless = 0;
    for (var i = 0; i < g.hand.length; i++) {
      if (view.surelyPlayable(i)) playable++;
      if (view.surelyUseless(i)) useless++;
    }
    return (playable, useless);
  }

  final (playable0, useless0) = sure(game);
  final reallyPlayable = game.fireworks.playableCards();
  final useful = {for (final h in game.usefulHints) hintToAction(h)};
  final out = <double>[];
  for (var a = 0; a < actionCount; a++) {
    if (!useful.contains(a)) {
      out.addAll(List.filled(actionFeatures, 0));
      continue;
    }
    final hint = actionToHint(a);
    final touched = game.hand.where(
      (c) => switch (hint) {
        NumberHint(:final number) => c.number == number,
        ColorHint(:final color) => c.color == color,
      },
    );
    final (playable, useless) = sure(Game.copy(game)..applyHint(hint));
    out.addAll([
      (playable - playable0) / 5,
      (useless - useless0) / 5,
      touched.length / 5,
      touched.where((c) => reallyPlayable.any(c.sameAs)).length / 5,
      touched.where((c) => LookaheadStrategy.isCritical(game, c)).length / 5,
    ]);
  }
  return out;
}

/// Hints chosen by a small neural network trained with reinforcement
/// learning (see `rl/`). [weights] is the JSON written by `rl/export.py`.
class RlStrategy extends HintStrategy {
  RlStrategy(Map<String, dynamic> weights, {this.name = 'rl'})
    : _encode = switch (weights['features'] ?? 'v1') {
        'v1' => encodeObservation,
        'v2' => encodeObservationV2,
        final f => throw ArgumentError('unknown feature set $f'),
      },
      _layers = [
        for (final l in weights['layers'] as List)
          (
            [
              for (final row in l['w'] as List)
                [for (final v in row as List) (v as num).toDouble()],
            ],
            [for (final v in l['b'] as List) (v as num).toDouble()],
          ),
      ];

  final List<double> Function(Game) _encode;
  final List<(List<List<double>>, List<double>)> _layers;

  @override
  final String name;

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
    final scores = logits(_encode(game));
    final best = allowed.reduce((a, b) => scores[b] > scores[a] ? b : a);
    return actionToHint(best);
  }
}

bool isDead(Game game, GameCard card) {
  final f = game.fireworks;
  final piles = card.isJoker ? CardColor.piles : [card.color];
  return piles.every((c) => (f.top(c)?.number ?? 0) >= card.number);
}
