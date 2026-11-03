import '../game/card.dart';
import '../game/coop.dart';
import '../game/game.dart';
import '../sim/expert.dart';
import 'simulated_player.dart';
import 'smart_strategies.dart';

/// What a co-op bot sees, as numbers for a network that scores its moves
/// (`rl/coop_distill.py`). Only what the player in turn can know goes in:
/// their own hand through the hints, the table and the other hands.
///
/// [state] describes the position, [move] one candidate move; the network
/// reads both, one candidate at a time. Change [version] when either
/// changes, so old data and models are not mixed up.
class CoopFeatures {
  CoopFeatures(this.game)
    : me = game.current,
      view = game.viewFor(game.current) {
    pv = PlayerView(view);
  }

  static const version = 'c1';
  static const stateSize = 14 + 5 * 8 + 3 * 4;
  static const moveSize = 3 + 5 + 5 + 3 + 1 + 8;

  final CoopGame game;
  final int me;
  final Game view;
  late final PlayerView pv;

  static const _hints = ExpertHints();

  /// The other players' views and hint scores, computed once.
  final Map<int, Game> _views = {};
  final Map<int, List<HintScore>> _scores = {};
  final Map<int, bool> _idle = {};

  Game viewOf(int p) => _views.putIfAbsent(p, () => game.viewFor(p));
  List<HintScore> scoresOf(int p) =>
      _scores.putIfAbsent(p, () => _hints.scoreHints(viewOf(p)));

  /// Whether [p] has nothing they can surely play.
  bool idle(int p) => _idle.putIfAbsent(p, () {
    final v = PlayerView(viewOf(p));
    for (var i = 0; i < game.hands[p].length; i++) {
      if (v.surelyPlayable(i)) return false;
    }
    return true;
  });

  /// Seats after [me], in turn order: 1 is the next player.
  int distance(int p) => (p - me + game.players) % game.players;

  int chop() => view.hand.indexWhere((c) => !c.knownNumber && !c.knownColor);

  late final List<double> state = _state();

  List<double> _state() {
    final f = game.fireworks;
    final out = <double>[
      for (final c in CardColor.piles) (f.top(c)?.number ?? 0) / 5,
      game.hints / maxHints,
      game.errors / allowedErrors,
      game.deckSize / 50,
      game.deckSize == 0 ? 1 : 0,
      for (var n = 2; n <= maxPlayers; n++) game.players == n ? 1 : 0,
      game.score / 25,
      view.maxScore() / 25,
    ];
    for (var i = 0; i < 5; i++) {
      if (i >= view.hand.length) {
        out.addAll(List.filled(8, 0));
        continue;
      }
      final c = view.hand[i];
      out.addAll([
        c.knownNumber ? 1 : 0,
        c.knownColor ? 1 : 0,
        pv.playProbability(i),
        pv.uselessProbability(i),
        pv.expectedDiscardRisk(i).clamp(0, 5) / 5,
        pv.surelyPlayable(i) ? 1 : 0,
        pv.surelyUseless(i) ? 1 : 0,
        i == chop() ? 1 : 0,
      ]);
    }
    final playable = f.playableCards();
    for (var k = 1; k <= 3; k++) {
      if (k >= game.players) {
        out.addAll(List.filled(4, 0));
        continue;
      }
      final p = (me + k) % game.players;
      final hand = game.hands[p];
      out.addAll([
        idle(p) ? 1 : 0,
        hand.where((c) => playable.any(c.sameAs)).length / 5,
        hand
                .where(
                  (c) =>
                      !c.knownNumber &&
                      !c.knownColor &&
                      LookaheadStrategy.isCritical(viewOf(p), c),
                )
                .length /
            5,
        hand.where((c) => c.knownNumber || c.knownColor).length / 5,
      ]);
    }
    assert(out.length == stateSize);
    return out;
  }

  List<double> move(CoopMove m) {
    final out = List<double>.filled(moveSize, 0);
    switch (m) {
      case CoopPlay(:final index) || CoopDiscard(:final index):
        out[m is CoopPlay ? 0 : 1] = 1;
        out[3 + index] = 1;
        out[8] = pv.playProbability(index);
        out[9] = pv.uselessProbability(index);
        out[10] = pv.expectedDiscardRisk(index).clamp(0, 5) / 5;
        final c = view.hand[index];
        out[11] = c.knownNumber || c.knownColor ? 1 : 0;
        out[12] = index == chop() ? 1 : 0;
      case CoopHint(:final to, :final hint):
        out[2] = 1;
        out[13 + distance(to) - 1] = 1;
        out[16] = hint is NumberHint ? 1 : 0;
        final s = scoresOf(to).firstWhere((s) => s.hint == hint);
        out[17] = s.surePlays / 5;
        out[18] = s.protects / 5;
        out[19] = s.useless / 5;
        out[20] = s.misleading / 5;
        out[21] = s.touched / 5;
        out[22] = s.chance;
        out[23] = s.info / 5;
        out[24] = idle(to) ? 1 : 0;
    }
    return out;
  }
}
