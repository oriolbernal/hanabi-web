import 'dart:math';

import 'card.dart';
import 'fireworks.dart';
import 'game.dart';

/// The most players a cooperative game takes.
const maxPlayers = 4;

/// What a player does on their turn in a cooperative game.
sealed class CoopMove {}

class CoopPlay extends CoopMove {
  CoopPlay(this.index, {this.target});
  final int index;

  /// For a 2-5 joker: the pile it goes to.
  final CardColor? target;
}

class CoopDiscard extends CoopMove {
  CoopDiscard(this.index);
  final int index;
}

class CoopHint extends CoopMove {
  CoopHint(this.to, this.hint);

  /// The player who receives the hint.
  final int to;
  final Hint hint;
}

/// Hanabi for 2-4 players who take turns, with this app's cards (jokers
/// included), hint tokens and lives. Nobody sees their own hand, everyone
/// sees the others'. On a turn a player plays a card, discards one (winning
/// a hint token back) or spends a token to tell another player which of
/// their cards have one number or one color. When the deck runs out, every
/// player has one last turn.
class CoopGame {
  CoopGame({required this.players, Random? random, List<GameCard>? deck})
    : assert(players >= 2 && players <= maxPlayers),
      _deck = deck ?? buildDeck(random),
      fireworks = Fireworks() {
    for (var p = 0; p < players; p++) {
      hands.add([]);
      for (var i = 0; i < handSize; i++) {
        _draw(p);
      }
    }
  }

  final int players;
  final List<GameCard> _deck;
  final List<List<GameCard>> hands = [];
  final List<GameCard> discarded = [];
  final Fireworks fireworks;
  int hints = maxHints;
  int errors = allowedErrors;

  /// Whose turn it is; player 0 is the person.
  int current = 0;

  /// Turns left once the deck is empty, or null while it still has cards.
  int? turnsLeft;

  /// Cards per hand: five, or four with four players, as in Hanabi.
  int get handSize => players >= 4 ? 4 : 5;

  int get deckSize => _deck.length;
  int get score => fireworks.score;
  bool get isOver => fireworks.victory || errors == 0 || turnsLeft == 0;

  /// Whether playing the card at [index] of the current hand needs a pile.
  bool needsTarget(int index) {
    final card = hands[current][index];
    return card.isJoker && card.number != 1;
  }

  /// The highest score still reachable, as in the solitaire.
  int maxScore() => viewFor(current).maxScore();

  /// The game as [player] sees it: their own hand (whose cards only the
  /// hints reveal), the table and every other hand.
  Game viewFor(int player) => Game.view(
    hand: hands[player],
    deck: _deck,
    discarded: discarded,
    fireworks: fireworks,
    hints: hints,
    errors: errors,
    inSight: [
      for (var p = 0; p < players; p++)
        if (p != player) ...hands[p],
    ],
  );

  /// Hints [player] could receive that reveal something new; each one
  /// touches at least one card, as the rules require.
  List<Hint> hintsFor(int player) {
    final result = <Hint>{};
    for (final card in hands[player]) {
      if (!card.knownNumber) result.add(NumberHint(card.number));
      if (!card.knownColor) result.add(ColorHint(card.color));
    }
    return result.toList();
  }

  /// The current player plays the card at [index].
  PlayResult play(int index, {CardColor? target}) {
    final hand = hands[current];
    final card = hand.removeAt(index)..reveal();
    _draw(current);
    final PlayResult result;
    if (fireworks.play(card, target: target)) {
      result = PlaySuccess();
    } else {
      discarded.add(card);
      errors--;
      result = PlayFailure(card);
    }
    _endTurn();
    return result;
  }

  /// The current player throws away the card at [index].
  GameCard discard(int index) {
    final card = hands[current].removeAt(index)..reveal();
    discarded.add(card);
    _draw(current);
    if (hints < maxHints) hints++;
    _endTurn();
    return card;
  }

  /// The current player tells player [to] about [hint]; returns the cards
  /// it points at.
  List<GameCard> hint(int to, Hint hint) {
    assert(to != current && hints > 0);
    hints--;
    final touched = <GameCard>[];
    for (final card in hands[to]) {
      switch (hint) {
        case NumberHint(:final number) when card.number == number:
          card.knownNumber = true;
          touched.add(card);
        case NumberHint(:final number):
          card.ruleOutNumber(number);
        case ColorHint(:final color) when card.color == color:
          card.knownColor = true;
          touched.add(card);
        case ColorHint(:final color):
          card.ruleOutColor(color);
      }
    }
    _endTurn();
    return touched;
  }

  /// Applies any [move] for the current player.
  void apply(CoopMove move) {
    switch (move) {
      case CoopPlay(:final index, :final target):
        play(index, target: target);
      case CoopDiscard(:final index):
        discard(index);
      case CoopHint(:final to, :final hint):
        this.hint(to, hint);
    }
  }

  void _draw(int player) {
    if (_deck.isNotEmpty) hands[player].add(_deck.removeAt(0));
  }

  void _endTurn() {
    if (turnsLeft != null) {
      turnsLeft = turnsLeft! - 1;
    } else if (_deck.isEmpty) {
      // The turn that drew the last card is over: everyone, including
      // whoever drew it, plays once more.
      turnsLeft = players;
    }
    current = (current + 1) % players;
  }
}
