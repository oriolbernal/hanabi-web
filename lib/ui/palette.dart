import 'package:flutter/material.dart';

import '../game/card.dart';

const background = Color(0xFF0B1020);
const surface = Color(0xFF161D33);
const surfaceHigh = Color(0xFF222B48);
const textMuted = Color(0xFF8A93B2);
const accent = Color(0xFFFFB547);
const hintColor = Color(0xFF3E8ED0);

const jokerGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Color(0xFFE5484D),
    Color(0xFFF5D90A),
    Color(0xFF30A46C),
    Color(0xFF3E63DD),
    Color(0xFF8E4EC6),
  ],
);

Color cardColor(CardColor c) => switch (c) {
  CardColor.red => const Color(0xFFE5484D),
  CardColor.green => const Color(0xFF30A46C),
  CardColor.blue => const Color(0xFF3E63DD),
  CardColor.yellow => const Color(0xFFF5D90A),
  CardColor.white => const Color(0xFFEDEDED),
  CardColor.joker => const Color(0xFF8E4EC6),
};

/// Text color that reads well on top of [cardColor].
Color onCardColor(CardColor c) => switch (c) {
  CardColor.yellow || CardColor.white => const Color(0xFF1A1A1A),
  _ => Colors.white,
};

String colorName(CardColor c) => switch (c) {
  CardColor.red => 'red',
  CardColor.green => 'green',
  CardColor.blue => 'blue',
  CardColor.yellow => 'yellow',
  CardColor.white => 'white',
  CardColor.joker => 'joker',
};
