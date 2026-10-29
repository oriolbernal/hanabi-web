import 'package:flutter/material.dart';

import '../game/card.dart';
import 'palette.dart';

/// Draws a card showing only what the player knows about it.
class CardView extends StatelessWidget {
  const CardView({
    super.key,
    required this.card,
    this.width = 64,
    this.selected = false,
    this.highlighted = false,
    this.onTap,
  });

  final GameCard card;
  final double width;
  final bool selected;
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = card.knownColor ? card.color : null;
    final height = width * 1.45;

    final decoration = BoxDecoration(
      color: color == null
          ? surfaceHigh
          : color == CardColor.joker
          ? null
          : cardColor(color),
      gradient: color == CardColor.joker ? jokerGradient : null,
      borderRadius: BorderRadius.circular(width * 0.14),
      border: Border.all(
        color: selected
            ? accent
            : highlighted
            ? Colors.white
            : Colors.white.withValues(alpha: 0.08),
        width: selected || highlighted ? 3 : 1,
      ),
      boxShadow: [
        if (highlighted)
          BoxShadow(color: Colors.white.withValues(alpha: 0.5), blurRadius: 14),
        if (selected)
          BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 16),
      ],
    );

    final fg = color == null ? textMuted : onCardColor(color);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: width,
        height: height,
        transform: Matrix4.translationValues(0, selected ? -12 : 0, 0),
        decoration: decoration,
        child: Stack(
          children: [
            Center(
              child: Text(
                card.knownNumber ? '${card.number}' : '?',
                style: TextStyle(
                  fontSize: width * 0.55,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
            ),
            if (color == CardColor.joker)
              Positioned(
                top: width * 0.06,
                left: width * 0.1,
                child: Text(
                  '★',
                  style: TextStyle(color: fg, fontSize: width * 0.22),
                ),
              ),
            if (color == null && card.knownNumber)
              Positioned(
                bottom: width * 0.06,
                right: width * 0.1,
                child: Text(
                  '?',
                  style: TextStyle(color: fg, fontSize: width * 0.2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A small, fully revealed card used for discards.
class MiniCard extends StatelessWidget {
  const MiniCard({super.key, required this.card, this.size = 26});

  final GameCard card;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isJoker = card.isJoker;
    return Container(
      width: size,
      height: size * 1.3,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isJoker ? null : cardColor(card.color),
        gradient: isJoker ? jokerGradient : null,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${card.number}',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: size * 0.55,
          color: onCardColor(card.color),
        ),
      ),
    );
  }
}
