import 'dart:math';

import '../game/card.dart';
import '../game/game.dart';
import 'expert.dart';
import 'mlp.dart';
import 'simulated_player.dart';
import 'smart_strategies.dart';

/// Must match `rl/hanabi/encoding.py` exactly: the policy was trained on it.
const observationSize = handSize * slotFeatures + 5 + 30 + 3;
const slotFeatures = 19;

/// Feature set v2 appends, for each action, what giving that hint would do.
const actionFeatures = 5;
const observationSizeV2 = observationSize + actionCount * actionFeatures;

/// Feature set v3 appends, per hand slot, the points the reachable score
/// would drop if that card were discarded, and the reachable score itself.
const observationSizeV3 = observationSizeV2 + handSize + 1;

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

/// v2 plus what is at stake: [Game.discardLoss] of each card and
/// [Game.maxScore].
List<double> encodeObservationV3(Game game) => encodeObservationV2(game)
  ..addAll([
    for (var i = 0; i < handSize; i++)
      i < game.hand.length ? game.discardLoss(game.hand[i]) / 5 : 0,
  ])
  ..add(game.maxScore() / 25);

/// Feature set v4 appends, per hint, what the expert player would do right
/// after it (see [encodeNextMoves]).
const nextMoveFeatures = 7;
const observationSizeV4 = observationSizeV3 + actionCount * nextMoveFeatures;

/// v3 plus [encodeNextMoves].
List<double> encodeObservationV4(Game game) =>
    encodeObservationV3(game)..addAll(encodeNextMoves(game));

/// For each of the [actionCount] hints (all zero when it would reveal
/// nothing), the move [ExpertPlayer.tuned] makes right after it and how it
/// turns out: play, discard or hint asked (one-hot); the played card fits;
/// the discarded card costs nothing; the points the discard costs (of 5);
/// and the best chance, from the player's view, of a card that really fits.
List<double> encodeNextMoves(Game game) {
  final useful = {for (final h in game.usefulHints) hintToAction(h)};
  final fits = game.fireworks.playableCards();
  final out = <double>[];
  for (var a = 0; a < actionCount; a++) {
    if (!useful.contains(a)) {
      out.addAll(List.filled(nextMoveFeatures, 0));
      continue;
    }
    final g = Game.copy(game)..giveHint(actionToHint(a));
    final move = ExpertPlayer.tuned.decide(g);
    final view = PlayerView(g);
    var chance = 0.0;
    for (var i = 0; i < g.hand.length; i++) {
      if (fits.any(g.hand[i].sameAs)) {
        chance = max(chance, view.playProbability(i));
      }
    }
    out.addAll(switch (move) {
      PlayMove(:final index) => [
        1,
        0,
        0,
        fits.any(g.hand[index].sameAs) ? 1 : 0,
        0,
        0,
        chance,
      ],
      DiscardMove(:final index) => [
        0,
        1,
        0,
        0,
        g.discardLoss(g.hand[index]) == 0 ? 1 : 0,
        g.discardLoss(g.hand[index]) / 5,
        chance,
      ],
      HintMove() => [0, 0, 1, 0, 0, 0, chance],
    });
  }
  return out;
}

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
  RlStrategy(
    Map<String, dynamic> weights, {
    this.name = 'rl',
    this.playFirst = false,
  }) : _encode = switch (weights['features'] ?? 'v1') {
         'v1' => encodeObservation,
         'v2' => encodeObservationV2,
         'v3' => encodeObservationV3,
         'v4' => encodeObservationV4,
         final f => throw ArgumentError('unknown feature set $f'),
       },
       _net = Mlp(weights);

  final List<double> Function(Game) _encode;
  final Mlp _net;

  @override
  final String name;

  /// Rule layer on top of the network: when some hint would give a card
  /// that really fits a good chance (see [playChanceAfter]) of being played,
  /// only the hints giving the best chance are considered. People expect
  /// "it's a 1" (87%) before "it's red" (30%), which the network may not.
  final bool playFirst;

  /// Scores for each of the [actionCount] actions; higher is preferred.
  List<double> logits(List<double> input) => _net(input);

  @override
  Hint? choose(Game game) {
    var allowed = {for (final h in game.usefulHints) hintToAction(h)};
    if (allowed.isEmpty) return null;
    if (playFirst) {
      final chance = {for (final a in allowed) a: playChanceAfter(game, a)};
      final best = chance.values.reduce(max);
      if (best >= 0.5 && best > playChanceAfter(game, null) + 1e-9) {
        allowed = {
          for (final a in allowed)
            if (chance[a]! >= best - 1e-9) a,
        };
      }
    }
    final scores = logits(_encode(game));
    final best = allowed.reduce((a, b) => scores[b] > scores[a] ? b : a);
    return actionToHint(best);
  }

  /// Best chance, from the player's point of view, of playing a card that
  /// really fits, after giving the hint [action] (or none).
  static double playChanceAfter(Game game, int? action) {
    final g = action == null
        ? game
        : (Game.copy(game)..applyHint(actionToHint(action)));
    final fits = game.fireworks.playableCards();
    final view = PlayerView(g);
    var best = 0.0;
    for (var i = 0; i < g.hand.length; i++) {
      if (fits.any(g.hand[i].sameAs)) best = max(best, view.playProbability(i));
    }
    return best;
  }
}

bool isDead(Game game, GameCard card) {
  final f = game.fireworks;
  final piles = card.isJoker ? CardColor.piles : [card.color];
  return piles.every((c) => (f.top(c)?.number ?? 0) >= card.number);
}
