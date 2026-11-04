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
/// reads both, one candidate at a time. Add a [version] when either
/// changes, so old data and models are not mixed up: c1 summarises the
/// other hands, c2 adds every card in them and which ones a hint touches.
class CoopFeatures {
  CoopFeatures(this.game, {this.version = latest})
    : me = game.current,
      view = game.viewFor(game.current) {
    if (!versions.contains(version)) {
      throw ArgumentError('unknown co-op features $version');
    }
    pv = PlayerView(view);
  }

  static const versions = ['c1', 'c2'];
  static const latest = 'c2';

  /// Per card in another player's hand (c2).
  static const _cardSize = 13;

  static int stateSize(String version) =>
      14 + 5 * 8 + 3 * 4 + (version == 'c1' ? 0 : 3 * 5 * _cardSize);
  static int moveSize(String version) =>
      3 + 5 + 5 + 3 + 1 + 8 + (version == 'c1' ? 0 : 10);

  final String version;

  final CoopGame game;
  final int me;
  final Game view;
  late final PlayerView pv;

  static const _hints = ExpertHints();

  /// The other players' views and hint scores, computed once.
  final Map<int, Game> _views = {};
  final Map<int, List<HintScore>> _scores = {};
  final Map<int, bool> _idle = {};
  final Map<int, PlayerView> _pvs = {};

  Game viewOf(int p) => _views.putIfAbsent(p, () => game.viewFor(p));
  PlayerView playerViewOf(int p) =>
      _pvs.putIfAbsent(p, () => PlayerView(viewOf(p)));
  List<HintScore> scoresOf(int p) =>
      _scores.putIfAbsent(p, () => _hints.scoreHints(viewOf(p)));

  /// Whether [p] has nothing they can surely play.
  bool idle(int p) => _idle.putIfAbsent(p, () {
    final v = playerViewOf(p);
    for (var i = 0; i < game.hands[p].length; i++) {
      if (v.surelyPlayable(i)) return false;
    }
    return true;
  });

  /// Seats after [me], in turn order: 1 is the next player.
  int distance(int p) => (p - me + game.players) % game.players;

  int chop() => view.hand.indexWhere((c) => !c.knownNumber && !c.knownColor);

  static int _chopOf(List<GameCard> hand) =>
      hand.indexWhere((c) => !c.knownNumber && !c.knownColor);

  late final List<GameCard> _playable = game.fireworks.playableCards();

  bool _isPlayable(GameCard c) => _playable.any(c.sameAs);

  /// Can never be played: its pile (every pile, for a joker) is past it.
  bool _isDead(GameCard c) {
    final f = game.fireworks;
    final piles = c.isJoker ? CardColor.piles : [c.color];
    return piles.every((p) => (f.top(p)?.number ?? 0) >= c.number);
  }

  /// Cards still needed before [c] fits, 0 when it is playable.
  int _gap(GameCard c) {
    final f = game.fireworks;
    final piles = c.isJoker ? CardColor.piles : [c.color];
    return piles
        .map((p) => c.number - (f.top(p)?.number ?? 0) - 1)
        .where((g) => g >= 0)
        .fold(4, (a, b) => a < b ? a : b);
  }

  /// Every card in the other players' hands, in turn order (c2).
  List<double> _cards() {
    final out = <double>[];
    for (var k = 1; k <= 3; k++) {
      final p = (me + k) % game.players;
      final hand = k < game.players ? game.hands[p] : const <GameCard>[];
      final chop = _chopOf(hand);
      for (var i = 0; i < 5; i++) {
        if (i >= hand.length) {
          out.addAll(List.filled(_cardSize, 0));
          continue;
        }
        final c = hand[i];
        final theirs = playerViewOf(p);
        var twins = 0;
        for (var q = 0; q < game.players; q++) {
          if (q == me) continue;
          for (final d in game.hands[q]) {
            if (!identical(d, c) && d.sameAs(c)) twins++;
          }
        }
        out.addAll([
          1,
          _isPlayable(c) ? 1 : 0,
          _isDead(c) ? 1 : 0,
          LookaheadStrategy.isCritical(viewOf(p), c) ? 1 : 0,
          c.number / 5,
          _gap(c) / 4,
          c.isJoker ? 1 : 0,
          c.knownNumber ? 1 : 0,
          c.knownColor ? 1 : 0,
          theirs.playProbability(i),
          theirs.surelyPlayable(i) ? 1 : 0,
          i == chop ? 1 : 0,
          twins > 0 ? 1 : 0,
        ]);
      }
    }
    return out;
  }

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
    if (version != 'c1') out.addAll(_cards());
    assert(out.length == stateSize(version));
    return out;
  }

  List<double> move(CoopMove m) {
    final out = List<double>.filled(moveSize(version), 0);
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
        if (version != 'c1') {
          // Which cards it touches, and what they really are.
          final hand = game.hands[to];
          final chop = _chopOf(hand);
          for (var i = 0; i < hand.length; i++) {
            final c = hand[i];
            final touches = switch (hint) {
              NumberHint(:final number) => c.number == number,
              ColorHint(:final color) => c.color == color,
            };
            if (!touches) continue;
            out[25 + i] = 1;
            if (_isPlayable(c)) out[30] += 0.2;
            if (_isDead(c)) out[31] += 0.2;
            if (LookaheadStrategy.isCritical(viewOf(to), c)) out[32] += 0.2;
            if (i == chop) out[33] = 1;
            if (hint is NumberHint ? !c.knownNumber : !c.knownColor) {
              out[34] += 0.2;
            }
          }
        }
    }
    return out;
  }
}
