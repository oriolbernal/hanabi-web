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
        for (final number
            in card.knownNumber ? [card.number] : const [1, 2, 3, 4, 5])
          if ((_seen[_key(number, color)] ?? 0) < _copies(number, color))
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
