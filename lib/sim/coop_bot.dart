import '../game/card.dart';
import '../game/coop.dart';
import '../game/game.dart';
import 'expert.dart';
import 'simulated_player.dart';

/// A partner for the cooperative game, built from the solitaire's rules:
/// [player] judges its own hand from the hints and every card in sight,
/// and [ExpertHints] judges what each hint would tell another player.
///
/// On its turn, in this order:
/// 1. Plays a card that surely fits.
/// 2. Gives a hint that lets someone play a card for sure, to whoever plays
///    soonest.
/// 3. Warns a player, the soonest first, off a card they would otherwise
///    throw away and that cannot be lost (the last copy of a needed card,
///    or a joker).
/// 4. Does what [player] would do in the solitaire: discard a useless card,
///    play a likely one or keep hints in reserve; where it would ask for a
///    hint, it gives the most useful one instead.
/// 5. Otherwise discards the card least likely to cost points.
class CoopBot {
  const CoopBot({
    this.player = ExpertPlayer.tuned,
    this.person = 0,
    this.personPlayer = ExpertPlayer.human,
    this.idleFirst = false,
    this.minValue = double.negativeInfinity,
    this.idleBonus = 0,
  });

  /// A sure-play hint goes first to someone with nothing sure to play yet;
  /// a player who already has one can wait.
  final bool idleFirst;

  /// A hint that brings no sure play and protects nothing is only worth a
  /// token if [ExpertHints] values it at least this much (plus
  /// [idleBonus] for a player with nothing sure to do); otherwise the bot
  /// discards to win a token back.
  final double minValue;
  final double idleBonus;

  final ExpertPlayer player;

  /// The seat of the person, or null if every seat is a bot. Nobody is
  /// favoured: the seat only says how to predict that player's moves.
  final int? person;

  /// How the person is expected to play: fitted to the app's move log.
  final ExpertPlayer personPlayer;

  static const _hints = ExpertHints();

  CoopMove decide(CoopGame game) {
    final me = game.current;
    final view = game.viewFor(me);
    final decision = player.decideWithReason(view);

    if (decision.reason == MoveReason.surePlay) return _toMove(game, decision);
    if (game.hints > 0) {
      final urgent =
          _surePlayHint(game, me) ??
          _others(
            game,
            me,
          ).map((p) => _protectHint(game, p)).nonNulls.firstOrNull;
      if (urgent != null) return urgent;
    }
    switch (decision.reason) {
      case MoveReason.askHint:
        final hint = _bestHint(game, me);
        if (hint != null && (game.hints == maxHints || _worth(game, hint))) {
          return hint;
        }
        // Nothing worth telling: decide as if no hint were left.
        return _toMove(game, player.decideWithReason(view..hints = 0));
      default:
        return _toMove(game, decision);
    }
  }

  /// The other players in the order they play after [me].
  static Iterable<int> _others(CoopGame game, int me) => [
    for (var k = 1; k < game.players; k++) (me + k) % game.players,
  ];

  ExpertPlayer _model(int seat) => seat == person ? personPlayer : player;

  /// Whether [p] has nothing they can surely play or discard.
  static bool _idle(CoopGame game, int p) {
    final view = PlayerView(game.viewFor(p));
    for (var i = 0; i < game.hands[p].length; i++) {
      if (view.surelyPlayable(i)) return false;
    }
    return true;
  }

  CoopMove? _surePlayHint(CoopGame game, int me) {
    var order = _others(game, me).toList();
    if (idleFirst) {
      final idle = {for (final p in order) p: _idle(game, p)};
      order = [
        ...order.where((p) => idle[p]!),
        ...order.where((p) => !idle[p]!),
      ];
    }
    for (final p in order) {
      final best = _hints.bestHint(game.viewFor(p));
      if (best != null && best.$2 == HintReason.surePlay) {
        return CoopHint(p, best.$1);
      }
    }
    return null;
  }

  /// If player [next] would discard a card that must be kept, a hint
  /// touching it (its number if unknown, else its color).
  CoopMove? _protectHint(CoopGame game, int next) {
    if (next == game.current) return null;
    final view = game.viewFor(next);
    final move = _model(next).decide(view);
    if (move is! DiscardMove) return null;
    final card = game.hands[next][move.index];
    final mustKeep = card.isJoker
        ? CardColor.piles.any(
            (c) => (game.fireworks.top(c)?.number ?? 0) < card.number,
          )
        : view.discardLoss(card) > 0;
    if (!mustKeep) return null;
    if (!card.knownNumber) return CoopHint(next, NumberHint(card.number));
    if (!card.knownColor) return CoopHint(next, ColorHint(card.color));
    return null;
  }

  /// The most useful hint for anyone, by [ExpertHints]' value (plus
  /// [idleBonus] for a player with nothing sure to do), then whoever plays
  /// soonest.
  CoopHint? _bestHint(CoopGame game, int me) {
    CoopHint? best;
    var bestValue = double.negativeInfinity;
    for (final p in _others(game, me)) {
      final ranked = _hints.rankHints(game.viewFor(p));
      if (ranked.isEmpty) continue;
      final value = ranked.first.$3 + (_idle(game, p) ? idleBonus : 0);
      if (value > bestValue) {
        best = CoopHint(p, ranked.first.$1);
        bestValue = value;
      }
    }
    return best;
  }

  bool _worth(CoopGame game, CoopHint hint) {
    if (minValue == double.negativeInfinity) return true;
    final ranked = _hints.rankHints(game.viewFor(hint.to));
    final value = ranked.firstWhere((r) => r.$1 == hint.hint).$3;
    return value + (_idle(game, hint.to) ? idleBonus : 0) >= minValue;
  }

  CoopMove _toMove(CoopGame game, ExpertDecision decision) {
    switch (decision.move) {
      case PlayMove(:final index):
        final view = game.viewFor(game.current);
        return CoopPlay(
          index,
          target: game.needsTarget(index) ? bestJokerTarget(view, index) : null,
        );
      case DiscardMove(:final index):
        return CoopDiscard(index);
      case HintMove():
        // Only reached with no hint worth giving and tokens left.
        return CoopDiscard(0);
    }
  }
}
