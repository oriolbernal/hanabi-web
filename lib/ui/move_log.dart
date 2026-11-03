import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../game/card.dart';
import '../game/coop.dart';
import '../game/game.dart';
import '../sim/simulated_player.dart';

/// Every game the person plays, kept on the device (dev mode): the deck in
/// the order it was dealt, then each move, with what the advisor suggested
/// when it was showing. Exported as JSON lines, one per game, it is small
/// enough to paste into a chat; `rl/analyze_moves.py` replays it to see how
/// people really play and to tune the simulated players.
///
/// Moves are `p3` (play card 3; a joker above 1 adds the pile, `p3B`),
/// `d0` (discard card 0) and `h5` / `hR` (the hint that was given).
///
/// A cooperative game (mode `coop2` to `coop4`) deals the deck hand by hand,
/// player 0 (the person) first, and records every player's move in turn
/// order; a hint names its receiver, `h2:5` or `h1:R`.
class MoveLog {
  MoveLog._();

  static const _key = 'gameLog';

  /// Oldest games are dropped beyond this many.
  static const capacity = 300;

  static final List<Map<String, dynamic>> _games = [];
  static bool _loaded = false;

  static Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final line in prefs.getStringList(_key) ?? const []) {
        _games.add(jsonDecode(line) as Map<String, dynamic>);
      }
    } catch (_) {
      // Storage may be unavailable (private browsing): keep it in memory.
    }
  }

  static Future<void> _save() async {
    if (_games.length > capacity) {
      _games.removeRange(0, _games.length - capacity);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, [for (final g in _games) jsonEncode(g)]);
    } catch (_) {}
  }

  /// Starts a game record: [deck] is the whole shuffled deck, hand first.
  static Future<void> startGame(
    List<GameCard> deck, {
    required String mode,
  }) async {
    final game = <String, dynamic>{
      'at': DateTime.now().toIso8601String(),
      'mode': mode,
      'deck': deck.map((c) => c.toString()).join(),
      'moves': <String>[],
      'advice': <String>[],
    };
    await _load();
    _games.add(game);
    await _save();
  }

  /// Records [move], about to be made, and what the advisor suggested, if it
  /// was showing. For a hint, [hint] is the one given; for a joker played
  /// onto a chosen pile, [target] is that pile.
  static Future<void> record(
    Move move, {
    Hint? hint,
    CardColor? target,
    Move? advice,
  }) async {
    final moveText = describe(move, hint: hint, target: target);
    final adviceText = advice == null ? '' : describe(advice);
    await _load();
    if (_games.isEmpty) return;
    (_games.last['moves'] as List).add(moveText);
    (_games.last['advice'] as List).add(adviceText);
    await _save();
  }

  /// Records a move of a cooperative game, whoever made it.
  static Future<void> recordCoop(CoopMove move) async {
    await _load();
    if (_games.isEmpty) return;
    (_games.last['moves'] as List).add(describeCoop(move));
    (_games.last['advice'] as List).add('');
    await _save();
  }

  static String describeCoop(CoopMove move) => switch (move) {
    CoopPlay(:final index, :final target) => 'p$index${target?.symbol ?? ''}',
    CoopDiscard(:final index) => 'd$index',
    CoopHint(:final to, hint: NumberHint(:final number)) => 'h$to:$number',
    CoopHint(:final to, hint: ColorHint(:final color)) =>
      'h$to:${color.symbol}',
  };

  /// The log as JSON lines, one game each, oldest first.
  static Future<String> export() async {
    await _load();
    return [for (final g in _games) jsonEncode(g)].join('\n');
  }

  /// How many games are kept.
  static Future<int> get length async {
    await _load();
    return _games.length;
  }

  static String describe(Move move, {Hint? hint, CardColor? target}) =>
      switch (move) {
        PlayMove(:final index) => 'p$index${target?.symbol ?? ''}',
        DiscardMove(:final index) => 'd$index',
        HintMove() => switch (hint) {
          NumberHint(:final number) => 'h$number',
          ColorHint(:final color) => 'h${color.symbol}',
          null => 'h',
        },
      };
}
