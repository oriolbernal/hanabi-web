import '../game/card.dart';
import '../game/coop.dart';
import '../game/game.dart';
import 'mlp.dart';

/// A co-op bot trained by self-play alone (rl/coop_ppo.py): one network that
/// played every seat for hundreds of millions of moves, learning from the
/// team's score and nothing else. It sees what the player in turn sees, as
/// rl/hanabi/coop_env.py encodes it (the two must agree number for number:
/// test/selfplay_test.dart), and plays the legal move it likes most.
///
/// Its conventions are its own: with copies of itself it reaches 25 most of
/// the time, with a person it may not.
class SelfPlayBot {
  SelfPlayBot(Map<String, dynamic> weights) : _net = Mlp(weights) {
    if (weights['obs'] != obsSize || weights['actions'] != actions) {
      throw ArgumentError('not a self-play model for this encoding');
    }
  }

  final Mlp _net;

  static const obsSize = 876;
  static const actions = 68;

  static const _play = 0, _playOn = 5, _discard = 30, _hintN = 35, _hintC = 50;

  CoopMove decide(CoopGame game) {
    final scores = _net(observe(game));
    final mask = legal(game);
    var best = -1;
    for (var a = 0; a < actions; a++) {
      if (mask[a] && (best < 0 || scores[a] > scores[best])) best = a;
    }
    return decode(game, best);
  }

  static int ident(GameCard c) => (c.number - 1) * 6 + c.color.index;

  static List<bool> legal(CoopGame g) {
    final mask = List.filled(actions, false);
    final hand = g.hands[g.current];
    for (var i = 0; i < hand.length; i++) {
      final c = hand[i];
      mask[_discard + i] = true;
      if (c.isJoker && c.number != 1) {
        for (var p = 0; p < 5; p++) {
          mask[_playOn + i * 5 + p] = true;
        }
      } else {
        mask[_play + i] = true;
      }
    }
    if (g.hints > 0) {
      for (var k = 1; k < g.players; k++) {
        for (final c in g.hands[(g.current + k) % g.players]) {
          mask[_hintN + (k - 1) * 5 + c.number - 1] = true;
          mask[_hintC + (k - 1) * 6 + c.color.index] = true;
        }
      }
    }
    return mask;
  }

  static CoopMove decode(CoopGame g, int a) {
    if (a < _playOn) return CoopPlay(a);
    if (a < _discard) {
      final i = (a - _playOn) ~/ 5;
      return CoopPlay(i, target: CardColor.piles.elementAt((a - _playOn) % 5));
    }
    if (a < _hintN) return CoopDiscard(a - _discard);
    if (a < _hintC) {
      final k = (a - _hintN) ~/ 5, n = (a - _hintN) % 5;
      return CoopHint((g.current + k + 1) % g.players, NumberHint(n + 1));
    }
    final k = (a - _hintC) ~/ 6, c = (a - _hintC) % 6;
    return CoopHint(
      (g.current + k + 1) % g.players,
      ColorHint(CardColor.values.elementAt(c)),
    );
  }

  // Layout, as in rl/hanabi/coop_env.py.
  static const _other = 41, _own = 12;
  static const _offOwn = 3 * 5 * _other;
  static const _offUnseen = _offOwn + 5 * _own;
  static const _offTable = _offUnseen + 30;
  static const _offReceived = _offTable + 55;
  static const _offLast = _offReceived + 4 * 11;

  static (List<int>, List<int>) _possible(GameCard c) => (
    c.knownNumber
        ? [c.number]
        : [
            for (var n = 1; n <= 5; n++)
              if (!c.notNumbers.contains(n)) n,
          ],
    c.knownColor
        ? [c.color.index]
        : [
            for (final col in CardColor.values)
              if (!c.notColors.contains(col)) col.index,
          ],
  );

  static List<double> observe(CoopGame g) {
    final o = List<double>.filled(obsSize, 0);
    final me = g.current;
    final total = [
      for (var n = 1; n <= 5; n++)
        for (final c in CardColor.values)
          (c == CardColor.joker ? 1 : numberDistribution.elementAt(n - 1))
              .toDouble(),
    ];
    final unseen = List.of(total);
    for (final c in g.discarded) {
      unseen[ident(c)] -= 1;
    }
    for (final p in CardColor.piles) {
      for (final c in g.fireworks.pile(p)) {
        unseen[ident(c)] -= 1;
      }
    }
    for (var k = 1; k < g.players; k++) {
      final hand = g.hands[(me + k) % g.players];
      for (var i = 0; i < hand.length; i++) {
        final c = hand[i];
        final base = ((k - 1) * 5 + i) * _other;
        o[base + ident(c)] = 1;
        unseen[ident(c)] -= 1;
        final (numbers, colors) = _possible(c);
        for (final n in numbers) {
          o[base + 30 + n - 1] = 1;
        }
        for (final col in colors) {
          o[base + 35 + col] = 1;
        }
      }
    }
    final mine = g.hands[me];
    for (var i = 0; i < mine.length; i++) {
      final base = _offOwn + i * _own;
      final (numbers, colors) = _possible(mine[i]);
      for (final n in numbers) {
        o[base + n - 1] = 1;
      }
      for (final col in colors) {
        o[base + 5 + col] = 1;
      }
      o[base + 11] = 1;
    }
    for (var i = 0; i < 30; i++) {
      o[_offUnseen + i] = unseen[i] / total[i];
    }
    const t = _offTable;
    for (var p = 0; p < 5; p++) {
      o[t +
              p * 6 +
              (g.fireworks.top(CardColor.piles.elementAt(p))?.number ?? 0)] =
          1;
    }
    o[t + 30 + (g.fireworks.floatingJoker?.index ?? 5)] = 1;
    o[t + 36 + g.hints] = 1;
    o[t + 47 + g.errors] = 1;
    o[t + 51] = g.deckSize / 50;
    o[t + 52 + g.players - 2] = 1;
    for (var k = 0; k < g.players; k++) {
      final r = g.received[(me + k) % g.players];
      if (r == null) continue;
      final base = _offReceived + k * 11;
      for (final i in r.touched) {
        o[base + i] = 1;
      }
      o[base + 5 + r.focus] = 1;
      o[base + 10] = 1;
    }
    for (var k = 1; k < g.players; k++) {
      final last = g.lastMoves[(me + k) % g.players];
      if (last == null) continue;
      final base = _offLast + (k - 1) * 24;
      o[base + 'pdh'.indexOf(last.kind)] = 1;
      if (last.kind == 'h') {
        o[base + 8 + (last.to - me) % g.players] = 1;
        switch (last.hint!) {
          case NumberHint(:final number):
            o[base + 12 + number - 1] = 1;
          case ColorHint(:final color):
            o[base + 17 + color.index] = 1;
        }
      } else {
        o[base + 3 + last.slot] = 1;
        o[base + 23] = last.fits ? 1 : 0;
      }
    }
    return o;
  }
}
