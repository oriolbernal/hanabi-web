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
    this.outline,
    this.possible,
    this.onTap,
  });

  final GameCard card;
  final double width;
  final bool selected;
  final bool highlighted;

  /// A colored border, e.g. for the advisor's suggestion.
  final Color? outline;

  /// What the card can still be, when known better than from the hints
  /// alone (dev mode deduces it from every card in sight). Null shows only
  /// what hints ruled out.
  final Possible? possible;
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
            : outline ?? Colors.white.withValues(alpha: 0.08),
        width: selected || highlighted || outline != null ? 3 : 1,
      ),
      boxShadow: [
        if (highlighted)
          BoxShadow(color: Colors.white.withValues(alpha: 0.5), blurRadius: 14),
        if (selected)
          BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 16),
      ],
    );

    final fg = color == null ? textMuted : onCardColor(color);
    final numbers =
        possible?.numbers ??
        [
          for (var n = 1; n <= 5; n++)
            if (!card.notNumbers.contains(n)) n,
        ];
    final colors =
        possible?.colors ??
        [
          for (final c in CardColor.values)
            if (!card.notColors.contains(c)) c,
        ];

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
                bottom: width * 0.06,
                left: width * 0.1,
                child: Text(
                  '★',
                  style: TextStyle(color: fg, fontSize: width * 0.22),
                ),
              ),
            // What hints ruled out, shown as what is still possible.
            if (!card.knownNumber && numbers.length < 5)
              Positioned(
                top: width * 0.07,
                left: 0,
                right: 0,
                child: Text(
                  [for (final n in numbers) '$n'].join(' '),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: fg,
                    fontSize: width * 0.17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (color == null && colors.length < CardColor.values.length)
              Positioned(
                bottom: width * 0.09,
                left: 0,
                right: 0,
                child: _PossibleColors(colors: colors, size: width * 0.11),
              )
            else if (color == null && card.knownNumber)
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

/// The numbers and colors a card in hand can still be, in order.
typedef Possible = ({List<int> numbers, List<CardColor> colors});

/// Dots for the colors a card can still be, after the ruled-out ones.
class _PossibleColors extends StatelessWidget {
  const _PossibleColors({required this.colors, required this.size});

  final List<CardColor> colors;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final c in colors)
          Container(
            width: size,
            height: size,
            margin: EdgeInsets.symmetric(horizontal: size * 0.15),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c == CardColor.joker ? null : cardColor(c),
              gradient: c == CardColor.joker ? jokerGradient : null,
            ),
          ),
      ],
    );
  }
}

/// A small, fully revealed card used for discards.
class MiniCard extends StatelessWidget {
  const MiniCard({
    super.key,
    required this.card,
    this.size = 26,
    this.highlighted = false,
  });

  final GameCard card;
  final double size;

  /// Draws a thin frame around the card, leaving a small gap.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final isJoker = card.isJoker;
    final face = Container(
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
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: highlighted
              ? accent.withValues(alpha: 0.85)
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: face,
    );
  }
}
