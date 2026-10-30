import 'dart:math';

import '../game/card.dart';
import '../game/game.dart';
import 'simulated_player.dart';
import 'smart_strategies.dart';

/// Why the expert gives a hint, in order of priority.
enum HintReason {
  /// Lets the player play a card for sure.
  surePlay,

  /// Warns about a card that must not be discarded: the last copy of a
  /// card still needed, or a joker.
  protect,

  /// Lets the player discard a card for sure.
  useless,

  /// Tells the most about the hand.
  info,
}

/// Hints chosen by explicit rules a person can follow. It sees the real
/// cards, as the hint giver does, and judges each hint by what the player
/// will know after it.
class ExpertHints extends HintStrategy {
  const ExpertHints();

  @override
  String get name => 'expert';

  @override
  Hint? choose(Game game) => bestHint(game)?.$1;

  (Hint, HintReason)? bestHint(Game game) {
    (Hint, HintReason)? best;
    var bestValue = double.negativeInfinity;
    final before = PlayerView(game);
    final fits = game.fireworks.playableCards();
    for (final hint in game.usefulHints) {
      final g = Game.copy(game)..applyHint(hint);
      final after = PlayerView(g);
      var surePlays = 0, protects = 0, useless = 0, misleading = 0;
      var chance = 0.0, info = 0.0;
      for (var i = 0; i < g.hand.length; i++) {
        final card = g.hand[i];
        final fitsNow = fits.any(card.sameAs);
        if (fitsNow && after.surelyPlayable(i) && !before.surelyPlayable(i)) {
          surePlays++;
        }
        if (fitsNow) chance = max(chance, after.playProbability(i));
        // A card that does not fit but now looks playable invites a misfire.
        if (!fitsNow && after.playProbability(i) >= 0.5) misleading++;
        final old = game.hand[i];
        final touched =
            !old.knownNumber && card.knownNumber ||
            !old.knownColor && card.knownColor;
        if (touched &&
            !(old.knownNumber || old.knownColor) &&
            _mustKeep(game, card)) {
          protects++;
        }
        if (after.surelyUseless(i) && !before.surelyUseless(i)) useless++;
        final was = before.candidates(i).length;
        if (was > 0) info += (was - after.candidates(i).length) / was;
      }
      final value =
          1000.0 * surePlays +
          200.0 * protects +
          100.0 * useless +
          50 * chance -
          300.0 * misleading +
          10 * info;
      if (value > bestValue) {
        bestValue = value;
        final reason = surePlays > 0
            ? HintReason.surePlay
            : protects > 0
            ? HintReason.protect
            : useless > 0
            ? HintReason.useless
            : HintReason.info;
        best = (hint, reason);
      }
    }
    return best;
  }

  /// Losing this card would cost points or a joker's protection.
  static bool _mustKeep(Game game, GameCard card) {
    if (card.isJoker) {
      return CardColor.piles.any(
        (c) => (game.fireworks.top(c)?.number ?? 0) < card.number,
      );
    }
    return LookaheadStrategy.isCritical(game, card);
  }
}

/// Why the expert suggests a move.
enum MoveReason {
  /// The card fits whatever it is.
  surePlay,

  /// The card can never be played: discarding it costs nothing.
  useless,

  /// The card is likely enough to fit.
  likelyPlay,

  /// Few hints left and a cheap discard: win one back first.
  keepHints,

  /// Nothing sure to do, and a hint can still help.
  askHint,

  /// No hint left: the card least likely to cost points.
  safestDiscard,

  /// The deck is empty: only plays can still score.
  lastChance,
}

class ExpertDecision {
  ExpertDecision(this.move, this.reason, {this.chance = 0, this.risk = 0});
  final Move move;
  final MoveReason reason;

  /// For [MoveReason.likelyPlay]: chance the card fits.
  final double chance;

  /// For [MoveReason.safestDiscard]: expected points it may cost.
  final double risk;
}

/// Plays by explicit rules a person can follow, in this order:
///
/// 1. Play a card that surely fits.
/// 2. Discard a card that surely cannot be played any more (unless every
///    hint token is already in hand: then the discard wins nothing).
/// 3. Play a card at least [playThreshold] likely to fit, if there are
///    lives to spare.
/// 4. Ask for a hint.
/// 5. Discard the card least likely to cost points, preferring cards no
///    hint has touched.
class ExpertPlayer extends SimulatedPlayer {
  const ExpertPlayer({
    this.playThreshold = 0.8,
    this.hintedPenalty = 0.3,
    this.reserve = 0,
    this.lowRisk = 0,
    this.name = 'expert',
  });

  /// Below this many hint tokens, a discard of at most [lowRisk] expected
  /// points comes before asking for a hint: running out of hints forces
  /// blind discards of cards that matter.
  final int reserve;
  final double lowRisk;

  /// The settings tuned in simulation (19.5 with the expert hints).
  static const tuned = ExpertPlayer(
    playThreshold: 0.5,
    hintedPenalty: 0.3,
    reserve: 8,
    lowRisk: 0.15,
  );

  final double playThreshold;

  /// Extra cost, in points, of discarding a card a hint has touched: the
  /// hint was spent on it for a reason.
  final double hintedPenalty;

  @override
  final String name;

  @override
  Move decide(Game game) => decideWithReason(game).move;

  ExpertDecision decideWithReason(Game game) {
    final view = PlayerView(game);
    final n = game.hand.length;

    // 1. Sure plays, lowest number first: it unlocks the next cards.
    int? sure;
    for (var i = 0; i < n; i++) {
      if (!view.surelyPlayable(i) || wastesJoker(game, i)) continue;
      if (sure == null || _lowest(game, i) < _lowest(game, sure)) sure = i;
    }
    if (sure != null) {
      return ExpertDecision(PlayMove(sure), MoveReason.surePlay);
    }

    // 2. Useless cards.
    if (game.hints < maxHints) {
      for (var i = 0; i < n; i++) {
        if (view.surelyUseless(i)) {
          return ExpertDecision(DiscardMove(i), MoveReason.useless);
        }
      }
    }

    var best = -1;
    var bestP = 0.0;
    for (var i = 0; i < n; i++) {
      if (wastesJoker(game, i)) continue;
      final p = view.playProbability(i);
      if (p > bestP) {
        best = i;
        bestP = p;
      }
    }

    // 3. Likely plays, only with a life to spare.
    if (game.errors > 1 && best >= 0 && bestP >= playThreshold) {
      return ExpertDecision(
        PlayMove(best),
        MoveReason.likelyPlay,
        chance: bestP,
      );
    }

    final (pick, pickRisk) = _safestDiscard(game, view);

    // 4. Keep some hints in reserve while a discard is cheap.
    if (game.hints < reserve && game.hints < maxHints && pickRisk <= lowRisk) {
      return ExpertDecision(
        DiscardMove(pick),
        MoveReason.keepHints,
        risk: pickRisk,
      );
    }

    // 5. Hints.
    if (game.hints > 0 && game.usefulHints.isNotEmpty) {
      return ExpertDecision(HintMove(), MoveReason.askHint);
    }

    // With the deck empty a discard brings nothing back, and a misfire
    // keeps the points already scored: play the likeliest card.
    if (game.deckSize == 0 && best >= 0) {
      return ExpertDecision(
        PlayMove(best),
        MoveReason.lastChance,
        chance: bestP,
      );
    }

    // 6. The safest discard.
    return ExpertDecision(
      DiscardMove(pick),
      MoveReason.safestDiscard,
      risk: pickRisk,
    );
  }

  /// The card least likely to cost points, and its expected cost.
  (int, double) _safestDiscard(Game game, PlayerView view) {
    var pick = 0;
    var pickCost = double.infinity;
    var pickRisk = 0.0;
    for (var i = 0; i < game.hand.length; i++) {
      final card = game.hand[i];
      final risk = view.expectedDiscardRisk(i);
      final hinted = card.knownNumber || card.knownColor;
      final cost = risk + (hinted ? hintedPenalty : 0);
      if (cost < pickCost) {
        pick = i;
        pickCost = cost;
        pickRisk = risk;
      }
    }
    return (pick, pickRisk);
  }

  /// The number the card shows, or 6 when unknown (sure plays only).
  static int _lowest(Game game, int i) {
    final c = game.hand[i];
    return c.knownNumber ? c.number : 6;
  }
}
