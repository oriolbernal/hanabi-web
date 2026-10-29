import 'card.dart';

/// The five firework piles, one per color.
///
/// A 1-joker is placed on the first empty pile and stays "floating" while it
/// is alone there: if a real card later needs that pile, or needs an empty
/// pile the joker could take as its 1, the joker moves to make room.
class Fireworks {
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

  /// Pile holding a lone 1-joker, if any.
  CardColor? get floatingJoker {
    for (final c in CardColor.piles) {
      final p = _piles[c]!;
      if (p.length == 1 && p.first.isJoker) return c;
    }
    return null;
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
    final from = floatingJoker;
    if (from == null) return false;
    final joker = _piles[from]!.single;
    _piles[from]!.clear();
    for (final c in CardColor.piles) {
      if (_piles[c]!.isNotEmpty) continue;
      _piles[c]!.add(joker);
      if (fits(card, card.color)) {
        _piles[card.color]!.add(card);
        return true;
      }
      _piles[c]!.clear();
    }
    _piles[from]!.add(joker);
    return false;
  }

  /// Cards (including joker variants) that would be a valid play right now.
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
    return result;
  }

  bool get victory => CardColor.piles.every((c) => top(c)?.number == 5);

  int get score =>
      CardColor.piles.fold(0, (sum, c) => sum + (top(c)?.number ?? 0));
}
