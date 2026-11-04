import 'dart:convert';

import 'package:flutter/services.dart';

import '../game/game.dart';
import '../sim/rl_strategy.dart';
import 'strings.dart';

/// Who chooses the hint when you press *Hint*.
enum HintMode {
  classic,
  ai;

  String get label => tr.modeLabel(this);
  String get description => tr.modeDescription(this);

  Future<HintStrategy> load() async => switch (this) {
    HintMode.classic => const DummyStrategy(),
    HintMode.ai => await _rlStrategy,
  };

  static final Future<HintStrategy> _rlStrategy = rootBundle
      .loadString('assets/models/hint_policy.json')
      .then(
        // Hints the player will ask for anyway come out nearly tied, so
        // within 0.2 points the one giving a likely play (as the human-like
        // player judges it, p >= 0.7) goes first: costs 0.05, and the first
        // hint of a game is always the playable card when there is one.
        (json) => RlStrategy(
          jsonDecode(json) as Map<String, dynamic>,
          playMargin: 0.2,
          playChance: 0.7,
        ),
      );
}
