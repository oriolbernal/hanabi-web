import 'card.dart';

/// The five firework piles, one per color.
///
/// A 1-joker is placed on the first empty pile and stays "floating" while
/// only jokers sit there (a 2-joker on top keeps it colorless): if a real
/// card later needs that pile, or needs an empty pile the joker stack could
/// take as its own, the whole stack moves to make room. The first real card
/// played on the stack fixes its color.
class Fireworks {
  Fireworks();

  /// Played cards never change, so the copy can share them.
  Fireworks.copy(Fireworks other) {
    for (final c in CardColor.piles) {
      _piles[c]!.addAll(other._piles[c]!);
    }
  }

  final Map<CardColor, List<GameCard>> _piles = {
    for (final c in CardColor.piles) c: <GameCard>[],
  };

  List<GameCard> pile(CardColor color) => List.unmodifiable(_piles[color]!);

  GameCard? top(CardColor color) {
    final p = _piles[color]!;
    return p.isEmpty ? null : p.last;
  }

  bool fits(GameCard card, CardColor color) {
    final t = top(color);
    return t == null ? card.number == 1 : card.number - t.number == 1;
  }

  /// Pile holding only jokers (a 1-joker, maybe with more jokers on top),
  /// if any. Its color is not decided yet.
  CardColor? get floatingJoker {
    for (final c in CardColor.piles) {
      final p = _piles[c]!;
      if (p.isNotEmpty && p.every((card) => card.isJoker)) return c;
    }
    return null;
  }

  /// Whether a real (non-joker) card could be played by moving the floating
  /// joker stack: onto the stack once it sits in the card's own pile, or
  /// into the pile the stack occupies after the stack moves elsewhere.
  bool _fitsByMovingJoker(GameCard card) {
    final from = floatingJoker;
    if (from == null) return false;
    final stack = _piles[from]!;
    if (card.color == from) {
      // The real 1 wants this pile: the stack needs another empty pile.
      return card.number == 1 &&
          CardColor.piles.any((c) => c != from && _piles[c]!.isEmpty);
    }
    return _piles[card.color]!.isEmpty && card.number == stack.last.number + 1;
  }

  /// Plays [card]. Jokers above 1 go on [target]; everything else is placed
  /// automatically. Returns false if the card does not fit anywhere.
  bool play(GameCard card, {CardColor? target}) {
    if (card.isJoker) {
      if (card.number == 1) {
        for (final c in CardColor.piles) {
          if (_piles[c]!.isEmpty) {
            _piles[c]!.add(card);
            return true;
          }
        }
        return false;
      }
      if (target != null && fits(card, target)) {
        _piles[target]!.add(card);
        return true;
      }
      return false;
    }

    if (fits(card, card.color)) {
      _piles[card.color]!.add(card);
      return true;
    }
    return _playByMovingJoker(card);
  }

  bool _playByMovingJoker(GameCard card) {
    if (!_fitsByMovingJoker(card)) return false;
    final from = floatingJoker!;
    final stack = List.of(_piles[from]!);
    _piles[from]!.clear();
    final to = card.color == from
        ? CardColor.piles.firstWhere((c) => c != from && _piles[c]!.isEmpty)
        : card.color;
    _piles[to]!.addAll(stack);
    _piles[card.color]!.add(card);
    return true;
  }

  /// Cards (including joker variants) that would be a valid play right now,
  /// counting the plays that move the floating joker stack.
  List<GameCard> playableCards() {
    final result = <GameCard>[];
    for (final c in CardColor.piles) {
      final t = top(c);
      if (t == null) {
        result
          ..add(GameCard(1, c))
          ..add(GameCard(1, CardColor.joker));
      } else if (t.number < 5) {
        result
          ..add(GameCard(t.number + 1, c))
          ..add(GameCard(t.number + 1, CardColor.joker));
      }
    }
    final from = floatingJoker;
    if (from != null) {
      final next = _piles[from]!.last.number + 1;
      for (final c in CardColor.piles) {
        if (c == from) {
          if (_fitsByMovingJoker(GameCard(1, c))) result.add(GameCard(1, c));
        } else if (next <= 5 && _piles[c]!.isEmpty) {
          result.add(GameCard(next, c));
        }
      }
    }
    return result;
  }

  bool get victory => CardColor.piles.every((c) => top(c)?.number == 5);

  int get score =>
      CardColor.piles.fold(0, (sum, c) => sum + (top(c)?.number ?? 0));
}
