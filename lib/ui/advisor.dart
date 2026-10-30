import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/card.dart';
import '../game/game.dart';
import '../sim/player_policy.dart';
import '../sim/simulated_player.dart';
import 'palette.dart';
import 'strings.dart';

/// The trained player agent, loaded once from the app's assets.
final Future<PlayerPolicy> loadAdvisor = rootBundle
    .loadString('assets/models/player_policy.json')
    .then(
      (json) => PlayerPolicy(
        jsonDecode(json) as Map<String, dynamic>,
        noWastedDiscards: true,
        safeDiscardMargin: PlayerPolicy.appSafeDiscardMargin,
      ),
    );

/// What the advisor knows and would do, from the player's point of view.
class Advice {
  Advice(Game game, PlayerPolicy agent)
    : odds = cardOdds(game),
      move = agent.decide(game);

  final List<CardOdds> odds;
  final Move move;

  int? get cardIndex => switch (move) {
    PlayMove(:final index) || DiscardMove(:final index) => index,
    HintMove() => null,
  };

  /// Green to play, red to discard, blue to ask for a hint.
  Color get color => switch (move) {
    PlayMove() => cardColor(CardColor.green),
    DiscardMove() => cardColor(CardColor.red),
    HintMove() => hintColor,
  };

  String describe() => switch (move) {
    PlayMove(:final index) => tr.advicePlay(index + 1, _pct(odds[index].play)),
    DiscardMove(:final index) => tr.adviceDiscard(
      index + 1,
      tr.decimal(odds[index].discardLoss),
    ),
    HintMove() => tr.adviceHint,
  };
}

String _pct(double p) => '${(p * 100).round()}%';

Color playColor(double p) => p >= 0.9
    ? cardColor(CardColor.green)
    : p >= 0.6
    ? accent
    : textMuted;

Color lossColor(double loss) => loss >= 0.5
    ? cardColor(CardColor.red)
    : loss > 0.05
    ? accent
    : textMuted;

/// Odds shown under a card in hand.
class OddsLabel extends StatelessWidget {
  const OddsLabel({
    super.key,
    required this.odds,
    required this.width,
    this.suggested,
  });

  final CardOdds odds;
  final double width;

  /// Set to the advice color when this is the card the advisor would use.
  final Color? suggested;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: suggested?.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(6),
        border: suggested == null ? null : Border.all(color: suggested!),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          children: [
            _line(
              Icons.play_arrow_rounded,
              _pct(odds.play),
              playColor(odds.play),
            ),
            _line(
              Icons.delete_outline,
              odds.discardLoss < 0.05
                  ? '0'
                  : '-${odds.discardLoss.toStringAsFixed(1)}',
              lossColor(odds.discardLoss),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(IconData icon, String text, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 2),
      Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}
