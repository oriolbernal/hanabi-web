import 'dart:convert';

import 'package:flutter/services.dart';

import '../game/game.dart';
import '../sim/rl_strategy.dart';
import '../sim/smart_strategies.dart';
import 'strings.dart';

/// Who chooses the hint when you press *Hint*.
enum HintMode {
  classic,
  smart,
  ai;

  String get label => tr.modeLabel(this);
  String get description => tr.modeDescription(this);

  Future<HintStrategy> load() async => switch (this) {
    HintMode.classic => const DummyStrategy(),
    HintMode.smart => const LookaheadStrategy(),
    HintMode.ai => await _rlStrategy,
  };

  static final Future<HintStrategy> _rlStrategy = rootBundle
      .loadString('assets/models/hint_policy.json')
      .then(
        (json) => RlStrategy(
          jsonDecode(json) as Map<String, dynamic>,
          playFirst: true,
        ),
      );
}
