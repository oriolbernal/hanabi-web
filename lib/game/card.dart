enum CardColor {
  red('R'),
  green('G'),
  blue('B'),
  yellow('Y'),
  white('W'),
  joker('*');

  const CardColor(this.symbol);
  final String symbol;

  /// The colors that have their own firework pile (everything but the joker).
  static const piles = [red, green, blue, yellow, white];
}

class GameCard {
  GameCard(this.number, this.color);

  final int number;
  final CardColor color;
  bool knownNumber = false;
  bool knownColor = false;

  GameCard copy() => GameCard(number, color)
    ..knownNumber = knownNumber
    ..knownColor = knownColor;

  bool get isJoker => color == CardColor.joker;
  bool get isKnown => knownNumber && knownColor;

  void reveal() {
    knownNumber = true;
    knownColor = true;
  }

  bool sameAs(GameCard other) => number == other.number && color == other.color;

  @override
  String toString() => '$number${color.symbol}';
}
