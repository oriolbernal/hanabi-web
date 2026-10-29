import '../game/card.dart';
import '../game/game.dart';

sealed class Move {}

class PlayMove extends Move {
  PlayMove(this.index);
  final int index;
}

class DiscardMove extends Move {
  DiscardMove(this.index);
  final int index;
}

class HintMove extends Move {}

/// Stands in for a human so thousands of games can be played unattended.
abstract class SimulatedPlayer {
  const SimulatedPlayer();

  String get name;

  Move decide(Game game);
}

/// A careful player that only acts on what it knows for sure:
///
/// 1. Plays a card that is playable whatever it turns out to be.
/// 2. Discards a card that is useless whatever it turns out to be.
/// 3. Otherwise asks for a hint while there are tokens left.
/// 4. Otherwise discards the oldest card it does not know to be valuable.
///
/// It knows what hints revealed plus every card it can see (fireworks and
/// discards), so it can rule out cards whose copies are all accounted for.
class CarefulPlayer extends SimulatedPlayer {
  const CarefulPlayer();

  @override
  String get name => 'careful';

  @override
  Move decide(Game game) {
    final view = PlayerView(game);
    for (var i = 0; i < game.hand.length; i++) {
      if (view.surelyPlayable(i)) return PlayMove(i);
    }
    for (var i = 0; i < game.hand.length; i++) {
      if (view.surelyUseless(i)) return DiscardMove(i);
    }
    if (game.hints > 0 && game.usefulHints.isNotEmpty) return HintMove();
    for (var i = 0; i < game.hand.length; i++) {
      if (!view.maybeValuable(i)) return DiscardMove(i);
    }
    return DiscardMove(0);
  }
}

/// Plays a card when the chance it fits is at least [playThreshold]
/// ([lastLifeThreshold] with one life left), so it may misfire, and
/// discards a card likely enough to be useless to win back a hint:
///
/// 1. Plays the card most likely to fit, if likely enough.
/// 2. Discards the card most likely to be useless, if likely enough.
/// 3. Otherwise asks for a hint while there are tokens left.
/// 4. Otherwise discards an unhinted card, the least likely to be a last
///    copy.
class RiskTakingPlayer extends SimulatedPlayer {
  const RiskTakingPlayer(
    this.name, {
    required this.playThreshold,
    required this.lastLifeThreshold,
    required this.discardThreshold,
  });

  @override
  final String name;
  final double playThreshold;
  final double lastLifeThreshold;
  final double discardThreshold;

  @override
  Move decide(Game game) {
    final view = PlayerView(game);
    final n = game.hand.length;

    var best = -1;
    var bestP = -1.0;
    for (var i = 0; i < n; i++) {
      final p = view.playProbability(i);
      if (p > bestP) {
        best = i;
        bestP = p;
      }
    }
    final threshold = game.errors == 1 ? lastLifeThreshold : playThreshold;
    if (best >= 0 && bestP >= threshold) return PlayMove(best);

    var junk = -1;
    var junkP = -1.0;
    for (var i = 0; i < n; i++) {
      final p = view.uselessProbability(i);
      if (p > junkP) {
        junk = i;
        junkP = p;
      }
    }
    if (junk >= 0 && junkP >= discardThreshold) return DiscardMove(junk);
    if (game.hints > 0 && game.usefulHints.isNotEmpty) return HintMove();

    // Hinted cards are being prepared to play: throw away an unhinted one
    // if possible, the one least likely to be a last copy.
    var safest = 0;
    var safestCost = double.infinity;
    for (var i = 0; i < n; i++) {
      final card = game.hand[i];
      final hinted = card.knownNumber || card.knownColor;
      final cost = (hinted ? 1 : 0) + view.criticalProbability(i);
      if (cost < safestCost) {
        safest = i;
        safestCost = cost;
      }
    }
    return DiscardMove(safest);
  }
}

/// Simulated players from most careful to boldest.
const playerProfiles = <SimulatedPlayer>[
  CarefulPlayer(),
  RiskTakingPlayer(
    'cautious',
    playThreshold: 0.9,
    lastLifeThreshold: 1,
    discardThreshold: 1,
  ),
  RiskTakingPlayer(
    'balanced',
    playThreshold: 0.75,
    lastLifeThreshold: 0.95,
    discardThreshold: 0.9,
  ),
  RiskTakingPlayer(
    'bold',
    playThreshold: 0.6,
    lastLifeThreshold: 0.85,
    discardThreshold: 0.85,
  ),
];

/// What the player can deduce about each card in hand.
class PlayerView {
  PlayerView(this.game) {
    for (final c in game.discarded) {
      _seen.update(_key(c.number, c.color), (v) => v + 1, ifAbsent: () => 1);
    }
    for (final color in CardColor.piles) {
      for (final c in game.fireworks.pile(color)) {
        _seen.update(_key(c.number, c.color), (v) => v + 1, ifAbsent: () => 1);
      }
    }
  }

  final Game game;
  final Map<int, int> _seen = {};

  static int _key(int number, CardColor color) => number * 10 + color.index;

  static int _copies(int number, CardColor color) =>
      color == CardColor.joker ? 1 : numberDistribution[number - 1];

  /// Every (number, color) the card at [index] could still be.
  List<(int, CardColor)> candidates(int index) {
    final card = game.hand[index];
    return [
      for (final color in card.knownColor ? [card.color] : CardColor.values)
        if (!card.notColors.contains(color))
          for (final number
              in card.knownNumber ? [card.number] : const [1, 2, 3, 4, 5])
            if (!card.notNumbers.contains(number) &&
                (_seen[_key(number, color)] ?? 0) < _copies(number, color))
              (number, color),
    ];
  }

  bool _canPlay(int number, CardColor color) {
    final f = game.fireworks;
    if (color != CardColor.joker) return f.fits(GameCard(number, color), color);
    return CardColor.piles.any((c) => f.fits(GameCard(number, color), c));
  }

  /// A card is dead once its pile is already past its number. Jokers can go
  /// anywhere, so they are only dead when no pile still needs that number.
  bool _isDead(int number, CardColor color) {
    final f = game.fireworks;
    final piles = color == CardColor.joker ? CardColor.piles : [color];
    return piles.every((c) => (f.top(c)?.number ?? 0) >= number);
  }

  /// How many copies of each candidate are still unaccounted for: not
  /// discarded, not played and not a fully known card elsewhere in hand.
  /// Each candidate's probability is proportional to its weight.
  Map<(int, CardColor), int> weights(int index) {
    final inHand = <int, int>{};
    for (var j = 0; j < game.hand.length; j++) {
      final c = game.hand[j];
      if (j != index && c.isKnown) {
        inHand.update(_key(c.number, c.color), (v) => v + 1, ifAbsent: () => 1);
      }
    }
    return {
      for (final (n, c) in candidates(index))
        if (_copies(n, c) - (_seen[_key(n, c)] ?? 0) - (inHand[_key(n, c)] ?? 0)
            case final w when w > 0)
          (n, c): w,
    };
  }

  double _probability(int index, bool Function(int, CardColor) test) {
    final w = weights(index);
    final total = w.values.fold(0, (a, b) => a + b);
    if (total == 0) return 0;
    final hits = w.entries
        .where((e) => test(e.key.$1, e.key.$2))
        .fold(0, (a, e) => a + e.value);
    return hits / total;
  }

  double playProbability(int index) => _probability(index, _canPlay);

  double uselessProbability(int index) => _probability(index, _isDead);

  /// Chance that discarding this card loses the last copy of a needed card.
  double criticalProbability(int index) => _probability(
    index,
    (n, c) => !_isDead(n, c) && game.remaining(n, c) == 1,
  );

  bool surelyPlayable(int index) {
    final options = candidates(index);
    return options.isNotEmpty && options.every((o) => _canPlay(o.$1, o.$2));
  }

  bool surelyUseless(int index) {
    final options = candidates(index);
    return options.isNotEmpty && options.every((o) => _isDead(o.$1, o.$2));
  }

  /// Known to be a 5 or a joker: losing it would cap the score.
  bool maybeValuable(int index) {
    final card = game.hand[index];
    return (card.knownNumber && card.number == 5) ||
        (card.knownColor && card.isJoker);
  }
}

/// Cards the player can play or discard without any risk.
int safeActions(Game game) {
  final view = PlayerView(game);
  var count = 0;
  for (var i = 0; i < game.hand.length; i++) {
    if (view.surelyPlayable(i) || view.surelyUseless(i)) count++;
  }
  return count;
}
