import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../game/card.dart';
import '../game/game.dart';
import '../sim/simulated_player.dart';

/// Every move the person makes, with what they could see at the time, kept
/// on the device (dev mode). Exported as JSON lines, it shows how people
/// really play, to compare with the simulated players and tune them.
class MoveLog {
  MoveLog._();

  static const _key = 'moveLog';

  /// Oldest moves are dropped beyond this many.
  static const capacity = 3000;

  static final List<String> _lines = [];
  static bool _loaded = false;

  static Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _lines.addAll(prefs.getStringList(_key) ?? const []);
    } catch (_) {
      // Storage may be unavailable (private browsing): keep it in memory.
    }
  }

  /// Records [move], about to be made in [game], and what the advisor
  /// suggested, if it was showing.
  static Future<void> record(
    Game game,
    Move move, {
    Move? advice,
    required String mode,
  }) async {
    await _load();
    _lines.add(jsonEncode(encode(game, move, advice: advice, mode: mode)));
    if (_lines.length > capacity) _lines.removeRange(0, _lines.length - capacity);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, _lines);
    } catch (_) {}
  }

  /// The log as JSON lines, oldest first.
  static Future<String> export() async {
    await _load();
    return _lines.join('\n');
  }

  static Future<int> get length async {
    await _load();
    return _lines.length;
  }

  /// One move as JSON: the state the person saw (and the real cards, which
  /// the log may know), then the move.
  static Map<String, dynamic> encode(
    Game game,
    Move move, {
    Move? advice,
    required String mode,
  }) => {
    'at': DateTime.now().toIso8601String(),
    'mode': mode,
    'piles': [
      for (final c in CardColor.piles) game.fireworks.top(c)?.number ?? 0,
    ],
    'hints': game.hints,
    'lives': game.errors,
    'deck': game.deckSize,
    'hand': [
      for (final card in game.hand)
        {
          'card': card.toString(),
          'knownNumber': card.knownNumber,
          'knownColor': card.knownColor,
          'notNumbers': card.notNumbers.toList()..sort(),
          'notColors': [for (final c in card.notColors) c.symbol],
        },
    ],
    'discarded': [for (final c in game.discarded) c.toString()],
    'move': describe(move),
    if (advice != null) 'advice': describe(advice),
  };

  static String describe(Move move) => switch (move) {
    PlayMove(:final index) => 'play $index',
    DiscardMove(:final index) => 'discard $index',
    HintMove() => 'hint',
  };
}
