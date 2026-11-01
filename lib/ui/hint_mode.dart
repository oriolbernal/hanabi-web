import 'dart:convert';

import 'package:flutter/services.dart';

import '../game/game.dart';
import '../sim/expert.dart';
import '../sim/hint_search.dart';
import '../sim/rl_strategy.dart';
import '../sim/smart_strategies.dart';
import 'strings.dart';

/// Who chooses the hint when you press *Hint*.
enum HintMode {
  classic,
  smart,
  ai,
  search;

  String get label => tr.modeLabel(this);
  String get description => tr.modeDescription(this);

  Future<HintStrategy> load() async => switch (this) {
    HintMode.classic => const DummyStrategy(),
    HintMode.smart => const LookaheadStrategy(),
    HintMode.ai => await _rlStrategy,
    // The search simulates the human-like player, the one fitted to the
    // move log; against that player it scores 20.7 to the rules' 17.6.
    // Same tie-break as the network below, wider because 32 rollouts are
    // noisier than the network: 0.5 points costs nothing measurable.
    HintMode.search => SearchHints(
      search: HintSearch(player: ExpertPlayer.human, playMargin: 0.5),
    ),
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
