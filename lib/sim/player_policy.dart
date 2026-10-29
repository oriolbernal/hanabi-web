import '../game/card.dart';
import '../game/game.dart';
import 'mlp.dart';
import 'simulated_player.dart';

/// Must match `rl/hanabi/player_env.py` exactly: the agent was trained on it.
const playerSlotFeatures = 28;
const playerObservationSize = handSize * playerSlotFeatures + 5 + 30 + 3 + 1;

/// Actions 0-4 play that card, 5-9 discard it, 10 asks for a hint.
const playerActionCount = 2 * handSize + 1;
const askAction = 2 * handSize;

/// Only public information and what hints revealed, never the real cards.
List<double> encodePlayerObservation(Game game) {
  final obs = <double>[];
  final view = PlayerView(game);
  for (var i = 0; i < handSize; i++) {
    if (i >= game.hand.length) {
      obs.addAll(List.filled(playerSlotFeatures, 0));
      continue;
    }
    final card = game.hand[i];
    double flag(bool b) => b ? 1 : 0;
    obs
      ..addAll([1, flag(card.knownNumber), flag(card.knownColor)])
      ..addAll([
        for (var n = 1; n <= 5; n++) flag(card.knownNumber && card.number == n),
      ])
      ..addAll([
        for (final c in CardColor.values)
          flag(card.knownColor && card.color == c),
      ])
      ..addAll([for (var n = 1; n <= 5; n++) flag(card.notNumbers.contains(n))])
      ..addAll([
        for (final c in CardColor.values) flag(card.notColors.contains(c)),
      ])
      ..addAll([
        view.playProbability(i),
        view.uselessProbability(i),
        view.expectedDiscardLoss(i) / 5,
      ]);
  }
  for (final c in CardColor.piles) {
    obs.add((game.fireworks.top(c)?.number ?? 0) / 5);
  }
  for (final c in CardColor.values) {
    for (var n = 1; n <= 5; n++) {
      final copies = c == CardColor.joker ? 1 : numberDistribution[n - 1];
      final gone = game.discarded
          .where((d) => d.number == n && d.color == c)
          .length;
      obs.add(gone / copies);
    }
  }
  obs
    ..add(game.hints / maxHints)
    ..add(game.errors / allowedErrors)
    ..add(game.deckSize / 50)
    ..add(game.maxScore() / 25);
  return obs;
}

/// Actions the player may take right now.
List<bool> playerActionMask(Game game) {
  final n = game.hand.length;
  return [
    for (var i = 0; i < handSize; i++) i < n,
    for (var i = 0; i < handSize; i++) i < n,
    game.hints > 0 && game.usefulHints.isNotEmpty,
  ];
}

/// What a person can know about one card in hand.
class CardOdds {
  CardOdds(this.play, this.useless, this.discardLoss);

  /// Chance the card fits a firework right now.
  final double play;

  /// Chance the card can never be played.
  final double useless;

  /// Expected points of reachable score lost by discarding it.
  final double discardLoss;
}

List<CardOdds> cardOdds(Game game) {
  final view = PlayerView(game);
  return [
    for (var i = 0; i < game.hand.length; i++)
      CardOdds(
        view.playProbability(i),
        view.uselessProbability(i),
        view.expectedDiscardLoss(i),
      ),
  ];
}

/// The player agent trained with reinforcement learning (`rl/train_player.py`),
/// used to suggest moves in the app and as a simulated player.
class PlayerPolicy extends SimulatedPlayer {
  PlayerPolicy(Map<String, dynamic> weights, {this.name = 'agent'})
    : _net = Mlp(weights);

  final Mlp _net;

  @override
  final String name;

  @override
  Move decide(Game game) {
    final mask = playerActionMask(game);
    final scores = _net(encodePlayerObservation(game));
    var best = -1;
    for (var a = 0; a < playerActionCount; a++) {
      if (mask[a] && (best < 0 || scores[a] > scores[best])) best = a;
    }
    if (best == askAction) return HintMove();
    if (best < handSize) return PlayMove(best);
    return DiscardMove(best - handSize);
  }
}
