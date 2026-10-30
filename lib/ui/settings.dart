import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'strings.dart';

/// Preferences remembered between sessions.
class Settings {
  Settings._();

  static const _devModeKey = 'devMode';

  /// Shows the AI advisor (suggested move and odds per card) in games.
  static final devMode = ValueNotifier(false);

  static const _languageKey = 'language';

  /// Language of every text in the app; the device's until one is chosen.
  static final language = ValueNotifier(Language.system);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_languageKey);
      language.value = Language.values.firstWhere(
        (l) => l.name == saved,
        orElse: () => Language.system,
      );
      devMode.value = prefs.getBool(_devModeKey) ?? false;
      stats.value = Stats([
        for (final s in prefs.getStringList(_scoresKey) ?? []) int.parse(s),
      ]);
    } catch (_) {
      // Storage may be unavailable (private browsing): keep the default.
    }
  }

  static const _scoresKey = 'scores';

  /// Scores of finished games, oldest first.
  static final stats = ValueNotifier(Stats(const []));

  /// Saves a finished game's score. Returns whether it beats every earlier
  /// game.
  static Future<bool> recordGame(int score) async {
    final before = stats.value;
    final isRecord = before.played > 0 && score > before.best;
    stats.value = Stats([...before.scores, score]);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_scoresKey, [
        for (final s in stats.value.scores) '$s',
      ]);
    } catch (_) {}
    return isRecord;
  }

  static Future<void> setLanguage(Language l) async {
    language.value = l;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_languageKey, l.name);
    } catch (_) {}
  }

  static Future<void> setDevMode(bool on) async {
    devMode.value = on;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_devModeKey, on);
    } catch (_) {}
  }
}

class Stats {
  Stats(this.scores);

  final List<int> scores;

  int get played => scores.length;
  int get best => scores.isEmpty ? 0 : scores.reduce(max);
  double get average =>
      scores.isEmpty ? 0 : scores.reduce((a, b) => a + b) / scores.length;

  /// Mean of the last [n] games, to see recent form.
  double recent([int n = 10]) {
    final last = scores.skip(max(0, scores.length - n)).toList();
    return last.isEmpty ? 0 : last.reduce((a, b) => a + b) / last.length;
  }
}
