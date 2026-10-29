import 'dart:convert';

import 'package:flutter/services.dart';

import '../game/game.dart';
import '../sim/rl_strategy.dart';
import '../sim/smart_strategies.dart';

/// Who chooses the hint when you press *Hint*.
enum HintMode {
  classic('Classic', 'The original rule: reveals what most cards share.'),
  smart('Smart', 'Tries every hint and picks the one that helps most.'),
  ai('AI', 'A neural network trained on thousands of simulated games.');

  const HintMode(this.label, this.description);
  final String label;
  final String description;

  Future<HintStrategy> load() async => switch (this) {
    HintMode.classic => const DummyStrategy(),
    HintMode.smart => const LookaheadStrategy(),
    HintMode.ai => await _rlStrategy,
  };

  static final Future<HintStrategy> _rlStrategy = rootBundle
      .loadString('assets/models/hint_policy.json')
      .then((json) => RlStrategy(jsonDecode(json) as Map<String, dynamic>));
}
