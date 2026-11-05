import 'dart:math';

import '../game/card.dart';
import '../game/coop.dart';
import '../game/game.dart';
import 'coop_bot.dart';
import 'expert.dart';
import 'partners.dart';
import 'simulated_player.dart';

/// A quick way of playing used to imagine the rest of a game: play a card
/// the hints say fits, else tell someone about a card that fits now, else
/// discard the oldest card no hint has touched.
class QuickCoopPolicy {
  const QuickCoopPolicy();

  CoopMove decide(CoopGame game) {
    final me = game.current;
    final hand = game.hands[me];
    final f = game.fireworks;
    for (var i = 0; i < hand.length; i++) {
      final c = hand[i];
      if (c.knownNumber && c.knownColor && !c.isJoker && f.fits(c, c.color)) {
        return CoopPlay(i);
      }
      // A known number that fits every pile its color could be.
      if (c.knownNumber && !c.knownColor) {
        final colors = [
          for (final p in CardColor.piles)
            if (!c.notColors.contains(p)) p,
        ];
        if (c.notColors.contains(CardColor.joker) &&
            colors.isNotEmpty &&
            colors.every((p) => (f.top(p)?.number ?? 0) == c.number - 1)) {
          return CoopPlay(i);
        }
      }
    }
    if (game.hints > 0) {
      final playable = f.playableCards();
      for (var k = 1; k < game.players; k++) {
        final p = (me + k) % game.players;
        for (final c in game.hands[p]) {
          if (c.isKnown || !playable.any(c.sameAs)) continue;
          return CoopHint(
            p,
            c.knownNumber ? ColorHint(c.color) : NumberHint(c.number),
          );
        }
      }
    }
    if (game.hints < maxHints || game.hints == 0) {
      // The oldest card no hint has touched, else the oldest that is not a
      // known 5 or joker.
      var chop = hand.indexWhere((c) => !c.knownNumber && !c.knownColor);
      if (chop < 0) {
        chop = hand.indexWhere(
          (c) =>
              !(c.knownNumber && c.number == 5) && !(c.knownColor && c.isJoker),
        );
      }
      return CoopDiscard(chop < 0 ? 0 : chop);
    }
    for (var k = 1; k < game.players; k++) {
      final p = (me + k) % game.players;
      final options = game.hintsFor(p);
      if (options.isNotEmpty) return CoopHint(p, options.first);
    }
    return CoopDiscard(0);
  }
}

/// A sharper quick policy for the imagined games. It reasons, as cheaply
/// as possible, from what each card could still be after the hints
/// (positive and negative, without counting the cards in sight):
/// plays a card every possibility of which fits; else gives the hint that
/// turns a fitting card of the soonest player into a sure play; else
/// discards a card no possibility of which is still needed, else the
/// oldest card no hint has touched.
class SharpCoopPolicy {
  const SharpCoopPolicy();

  static List<(int, CardColor)> _options(GameCard c) => [
    for (final color in c.knownColor ? [c.color] : CardColor.values)
      if (!c.notColors.contains(color))
        for (final n in c.knownNumber ? [c.number] : const [1, 2, 3, 4, 5])
          if (!c.notNumbers.contains(n)) (n, color),
  ];

  static bool _fits(CoopGame g, int n, CardColor color) {
    final f = g.fireworks;
    final card = GameCard(n, color);
    if (color != CardColor.joker) return f.fits(card, color);
    return CardColor.piles.any((p) => f.fits(card, p));
  }

  static bool _dead(CoopGame g, int n, CardColor color) {
    final f = g.fireworks;
    final piles = color == CardColor.joker ? CardColor.piles : [color];
    return piles.every((p) => (f.top(p)?.number ?? 0) >= n);
  }

  static bool _surePlay(CoopGame g, GameCard c) {
    final o = _options(c);
    return o.isNotEmpty && o.every((x) => _fits(g, x.$1, x.$2));
  }

  CoopMove decide(CoopGame game) {
    final me = game.current;
    final hand = game.hands[me];
    for (var i = 0; i < hand.length; i++) {
      if (_surePlay(game, hand[i])) return CoopPlay(i);
    }
    if (game.hints > 0) {
      final playable = game.fireworks.playableCards();
      for (var k = 1; k < game.players; k++) {
        final p = (me + k) % game.players;
        final other = game.hands[p];
        if (other.any((c) => _surePlay(game, c))) continue; // busy already
        for (final c in other) {
          if (!playable.any(c.sameAs)) continue;
          for (final hint in [NumberHint(c.number), ColorHint(c.color)]) {
            final after = c.copy();
            if (hint is NumberHint) {
              after.knownNumber = true;
            } else {
              after.knownColor = true;
            }
            if (_surePlay(game, after)) return CoopHint(p, hint);
          }
        }
      }
    }
    if (game.hints < maxHints || game.hints == 0) {
      for (var i = 0; i < hand.length; i++) {
        final o = _options(hand[i]);
        if (o.isNotEmpty && o.every((x) => _dead(game, x.$1, x.$2))) {
          return CoopDiscard(i);
        }
      }
      var chop = hand.indexWhere((c) => !c.knownNumber && !c.knownColor);
      if (chop < 0) {
        chop = hand.indexWhere(
          (c) =>
              !(c.knownNumber && c.number == 5) && !(c.knownColor && c.isJoker),
        );
      }
      return CoopDiscard(chop < 0 ? 0 : chop);
    }
    return const QuickCoopPolicy().decide(game);
  }
}

/// A quick model of the person, fitted to the co-op move log: plays a card
/// the hints say fits, or one at least [playThreshold] likely to fit with a
/// life to spare, else gives a hint whenever a token is left (as
/// [QuickCoopPolicy] would, or any new information), else discards the
/// oldest untouched card.
///
/// With [readsClues] it also takes the last hint it received as "play this
/// card" (its focus), as most people do; with [givesClues] its hints point
/// at a card that fits now, as [ClueReader.playClue] does. Varying these
/// gives the search a population of partners to imagine, not just one.
class QuickPersonPolicy {
  const QuickPersonPolicy({
    this.playThreshold = 0.7,
    this.readsClues = false,
    this.givesClues = false,
  });

  final double playThreshold;
  final bool readsClues;
  final bool givesClues;

  /// The partners the search imagines in the person's seat, one per
  /// imagined game in turn.
  static const population = [
    QuickPersonPolicy(),
    QuickPersonPolicy(playThreshold: 0.5),
    QuickPersonPolicy(playThreshold: 0.95),
    QuickPersonPolicy(readsClues: true),
    QuickPersonPolicy(readsClues: true, givesClues: true),
    QuickPersonPolicy(readsClues: true, givesClues: true, playThreshold: 0.5),
  ];

  CoopMove decide(CoopGame game) {
    final me = game.current;
    final view = game.viewFor(me);
    final pv = PlayerView(view);
    var best = -1;
    var bestP = 0.0;
    for (var i = 0; i < view.hand.length; i++) {
      final p = pv.playProbability(i);
      if (p > bestP) {
        best = i;
        bestP = p;
      }
    }
    if (best >= 0 && bestP >= 0.999) return CoopPlay(best);
    final got = game.received[me];
    if (readsClues && got != null && got.hint != NumberHint(5)) {
      final f = got.focus;
      if (f < view.hand.length && !pv.surelyUseless(f)) {
        final p = pv.playProbability(f);
        if (p > 0 && (game.errors > 1 || p >= 0.5)) return CoopPlay(f);
      }
    }
    if (best >= 0 && bestP >= playThreshold && game.errors > 1) {
      return CoopPlay(best);
    }
    if (game.hints > 0) {
      if (givesClues) {
        final clue = ClueReader.playClue(game);
        if (clue != null) return clue;
      }
      final quick = const QuickCoopPolicy().decide(game);
      if (quick is CoopHint) return quick;
      for (var k = 1; k < game.players; k++) {
        final p = (me + k) % game.players;
        final options = game.hintsFor(p);
        if (options.isNotEmpty) return CoopHint(p, options.first);
      }
    }
    final chop = view.hand.indexWhere((c) => !c.knownNumber && !c.knownColor);
    return CoopDiscard(chop < 0 ? 0 : chop);
  }
}

/// A co-op bot that thinks ahead: for a handful of sensible moves (what
/// [CoopBot] would do, likely plays, the safest discards, the best hints
/// for each player) it imagines the rest of the game many times, its own
/// cards drawn again each time from what the hints allow, and keeps the
/// move with the best average final score. Every move is tried on the same
/// imagined games, so they compare fairly.
class CoopSearch {
  CoopSearch({
    this.rounds = 24,
    this.base = const CoopBot(),
    CoopMove Function(CoopGame)? rollout,
    this.person,
    this.personModels = const [QuickPersonPolicy()],
    this.minPlayChance = 0.4,
    this.allMoves = false,
    Random? random,
  }) : rollout = rollout ?? const QuickCoopPolicy().decide,
       _random = random ?? Random();

  /// The person's seat, played in the imagined games by [personModels];
  /// null when every seat is a bot.
  final int? person;

  /// How the person may play: each imagined game takes the next one in
  /// turn, the same for every candidate move so they compare fairly. With
  /// several, the moves that work with all of them win, not those tuned to
  /// a single way of playing.
  final List<QuickPersonPolicy> personModels;

  /// A card is only a candidate to play if it fits for sure or, with a
  /// life to spare, at least this likely; with the deck empty any card may
  /// be tried. Blind plays look reckless to a person even when they pay
  /// off on average.
  final double minPlayChance;

  /// Weighs every legal move, with no hand-made shortlist and no filter:
  /// what is worth doing (and when a 5 may go) is left to the imagined
  /// games, and to the network that learns from them.
  final bool allMoves;

  final int rounds;
  final CoopBot base;

  /// Plays the imagined games: the quick policy, or a trained network.
  final CoopMove Function(CoopGame) rollout;
  final Random _random;

  static const _hints = ExpertHints();

  CoopMove decide(CoopGame game) {
    final scored = evaluate(game);
    var best = 0;
    for (var m = 1; m < scored.length; m++) {
      if (scored[m].$2 > scored[best].$2) best = m;
    }
    return withTarget(game, scored[best].$1);
  }

  /// Each candidate move with its average final score over the imagined
  /// games (all the same score when there is a single candidate).
  List<(CoopMove, double)> evaluate(CoopGame game) {
    final options = candidates(game);
    if (options.length == 1) return [(options.single, 0)];
    final totals = List.filled(options.length, 0.0);
    for (var r = 0; r < rounds; r++) {
      final world = CoopGame.imagined(game, game.current, _random);
      final seed = _random.nextInt(1 << 30);
      final model = personModels[r % personModels.length];
      for (var m = 0; m < options.length; m++) {
        totals[m] += _playOut(world, options[m], seed, model);
      }
    }
    return [
      for (var m = 0; m < options.length; m++) (options[m], totals[m] / rounds),
    ];
  }

  /// A joker of 2-5 needs a pile: the one that keeps the most points open.
  static CoopMove withTarget(CoopGame game, CoopMove move) {
    if (move case CoopPlay(:final index, target: null)
        when game.needsTarget(index)) {
      return CoopPlay(
        index,
        target: bestJokerTarget(game.viewFor(game.current), index),
      );
    }
    return move;
  }

  double _playOut(
    CoopGame world,
    CoopMove move,
    int seed,
    QuickPersonPolicy model,
  ) {
    final g = CoopGame.copy(world);
    final card = switch (move) {
      CoopPlay(:final index) => g.hands[g.current][index],
      _ => null,
    };
    // A joker of 2-5 needs a pile: the one the bot would pick.
    final target =
        move is CoopPlay && card != null && card.isJoker && card.number > 1
        ? bestJokerTarget(g.viewFor(g.current), move.index)
        : (move is CoopPlay ? move.target : null);
    switch (move) {
      case CoopPlay(:final index):
        g.play(index, target: target);
      default:
        g.apply(move);
    }
    final random = Random(seed);
    var turns = 0;
    while (!g.isOver && turns++ < 200) {
      final m = g.current == person ? model.decide(g) : rollout(g);
      if (m case CoopPlay(:final index) when g.needsTarget(index)) {
        final c = g.hands[g.current][index];
        final fits = [
          for (final p in CardColor.piles)
            if (g.fireworks.fits(c, p)) p,
        ];
        g.play(
          index,
          target: fits.isEmpty
              ? CardColor.red
              : fits[random.nextInt(fits.length)],
        );
      } else {
        g.apply(m);
      }
    }
    return g.score.toDouble();
  }

  /// The moves worth comparing, without repeats.
  List<CoopMove> candidates(CoopGame game) {
    if (allMoves) return legalMoves(game);
    final me = game.current;
    final view = game.viewFor(me);
    final pv = PlayerView(view);
    final result = <String, CoopMove>{};
    void add(CoopMove m) => result.putIfAbsent(_key(m), () => m);

    add(base.decide(game));
    final plays = [
      for (var i = 0; i < view.hand.length; i++)
        if (pv.playProbability(i) >= 0.4) (i, pv.playProbability(i)),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    for (final (i, _) in plays.take(2)) {
      add(CoopPlay(i));
    }
    bool reckless(CoopMove m) {
      if (m is! CoopPlay || game.deckSize == 0) return false;
      final p = pv.playProbability(m.index);
      if (pv.surelyPlayable(m.index)) return false;
      return game.errors <= 1 || p < minPlayChance;
    }

    if (game.hints < maxHints) {
      final chop = view.hand.indexWhere((c) => !c.knownNumber && !c.knownColor);
      if (chop >= 0) add(CoopDiscard(chop));
      add(CoopDiscard(safestDiscard(view, pv)));
    }
    if (game.hints > 0) {
      for (var k = 1; k < game.players; k++) {
        final p = (me + k) % game.players;
        for (final (hint, _, _) in _hints.rankHints(game.viewFor(p)).take(2)) {
          add(CoopHint(p, hint));
        }
      }
    }
    final safe = [
      for (final m in result.values)
        if (!reckless(m)) m,
    ];
    if (safe.isEmpty) {
      // Only reckless plays left (all tokens in hand, nothing new to tell):
      // a discard wastes nothing but the token it cannot win back.
      safe.add(CoopDiscard(safestDiscard(view, pv)));
    }
    return safe;
  }

  /// Every move the current player may make: play or discard any card, or
  /// any hint that tells another player something new.
  static List<CoopMove> legalMoves(CoopGame game) {
    final me = game.current;
    final hand = game.hands[me].length;
    return [
      for (var i = 0; i < hand; i++) CoopPlay(i),
      for (var i = 0; i < hand; i++) CoopDiscard(i),
      if (game.hints > 0)
        for (var k = 1; k < game.players; k++)
          for (final h in game.hintsFor((me + k) % game.players))
            CoopHint((me + k) % game.players, h),
    ];
  }

  /// The card whose loss costs least: one surely useless if there is one,
  /// else the lowest expected cost in points, a hinted card costing
  /// [hintedPenalty] more (the hint was spent on it for a reason), and a
  /// card that surely fits never.
  static int safestDiscard(
    Game view,
    PlayerView pv, {
    double hintedPenalty = 0.3,
  }) {
    var best = 0;
    var bestCost = double.infinity;
    for (var i = 0; i < view.hand.length; i++) {
      final c = view.hand[i];
      final double cost;
      if (pv.surelyUseless(i)) {
        cost = -1;
      } else if (pv.surelyPlayable(i)) {
        cost = 100;
      } else {
        cost =
            pv.expectedDiscardRisk(i) +
            (c.knownNumber || c.knownColor ? hintedPenalty : 0);
      }
      if (cost < bestCost) {
        best = i;
        bestCost = cost;
      }
    }
    return best;
  }

  static String _key(CoopMove m) => switch (m) {
    CoopPlay(:final index) => 'p$index',
    CoopDiscard(:final index) => 'd$index',
    CoopHint(:final to, hint: NumberHint(:final number)) => 'h$to:$number',
    CoopHint(:final to, hint: ColorHint(:final color)) =>
      'h$to:${color.symbol}',
  };
}
