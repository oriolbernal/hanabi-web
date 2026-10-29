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

  /// Ruled out by hints that did not touch this card: if the three cards on
  /// the right are green, the two on the left are not.
  final Set<int> notNumbers = {};
  final Set<CardColor> notColors = {};

  GameCard copy() => GameCard(number, color)
    ..knownNumber = knownNumber
    ..knownColor = knownColor
    ..notNumbers.addAll(notNumbers)
    ..notColors.addAll(notColors);

  /// Records a hint that did not touch this card. Ruling out every other
  /// option reveals the attribute, as a person would deduce.
  void ruleOutNumber(int n) {
    notNumbers.add(n);
    if (notNumbers.length == 4) knownNumber = true;
  }

  void ruleOutColor(CardColor c) {
    notColors.add(c);
    if (notColors.length == CardColor.values.length - 1) knownColor = true;
  }

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
