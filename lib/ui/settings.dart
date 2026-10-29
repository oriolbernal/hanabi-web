import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferences remembered between sessions.
class Settings {
  Settings._();

  static const _devModeKey = 'devMode';

  /// Shows the AI advisor (suggested move and odds per card) in games.
  static final devMode = ValueNotifier(false);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      devMode.value = prefs.getBool(_devModeKey) ?? false;
    } catch (_) {
      // Storage may be unavailable (private browsing): keep the default.
    }
  }

  static Future<void> setDevMode(bool on) async {
    devMode.value = on;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_devModeKey, on);
    } catch (_) {}
  }
}
