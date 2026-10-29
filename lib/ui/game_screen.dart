import 'package:flutter/material.dart';

import '../game/card.dart';
import '../game/game.dart';
import 'card_view.dart';
import 'hint_mode.dart';
import 'palette.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.mode, required this.strategy});

  final HintMode mode;
  final HintStrategy strategy;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late Game _game = Game(strategy: widget.strategy);
  int? _selected;

  /// Cards revealed by the last hint, highlighted until the next move.
  Set<GameCard> _revealed = {};

  void _restart() => setState(() {
    _game = Game(strategy: widget.strategy);
    _selected = null;
    _revealed = {};
  });

  /// Feedback about the last move, shown above the hand.
  String? _message;
  Color? _messageColor;

  void _toast(String message, {Color? color}) => setState(() {
    _message = message;
    _messageColor = color;
  });

  Future<void> _play() async {
    final index = _selected;
    if (index == null) return;
    CardColor? target;
    if (_game.needsTarget(index)) {
      target = await _askTarget();
      if (target == null) return;
    }
    final result = _game.play(index, target: target);
    setState(() {
      _selected = null;
      _revealed = {};
    });
    if (result case PlayFailure(:final card)) {
      _toast(
        'Misfire! That card was a ${card.number} ${colorName(card.color)}.',
        color: const Color(0xFF8C1D24),
      );
    }
    _checkEnd();
  }

  void _discard() {
    final index = _selected;
    if (index == null) return;
    final card = _game.discard(index);
    setState(() {
      _selected = null;
      _revealed = {};
    });
    _toast('Discarded a ${card.number} ${colorName(card.color)}.');
    _checkEnd();
  }

  void _hint() {
    final hint = _game.hint();
    if (hint == null) {
      _toast('You already know all your cards. Play or discard them.');
      return;
    }
    setState(() {
      _revealed = switch (hint) {
        NumberHint(:final number) =>
          _game.hand.where((c) => c.number == number).toSet(),
        ColorHint(:final color) =>
          _game.hand.where((c) => c.color == color).toSet(),
      };
    });
    _toast(switch (hint) {
      NumberHint(:final number) => 'Hint: these are your ${number}s.',
      ColorHint(color: CardColor.joker) => 'Hint: these are your jokers.',
      ColorHint(:final color) =>
        'Hint: these are your ${colorName(color)} cards.',
    });
  }

  Future<CardColor?> _askTarget() {
    return showModalBottomSheet<CardColor>(
      context: context,
      backgroundColor: surface,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "It's a joker! Choose where to play it",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final c in CardColor.piles)
                    _PileView(
                      color: c,
                      top: _game.fireworks.top(c),
                      width: 52,
                      onTap: () => Navigator.pop(context, c),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _checkEnd() {
    if (!_game.isOver) return;
    final won = _game.fireworks.victory;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: surface,
        title: Text(won ? 'Perfect show! 🎆' : 'The show is over'),
        content: Text(
          'Your score is ${_game.score} / 25',
          style: const TextStyle(fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(this.context);
            },
            child: const Text('Menu'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _restart();
            },
            child: const Text('Play again'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Column(
          children: [
            const Text(
              'HANABI',
              style: TextStyle(letterSpacing: 6, fontWeight: FontWeight.w800),
            ),
            Text(
              '${widget.mode.label} hints',
              style: const TextStyle(fontSize: 12, color: textMuted),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'New game',
            icon: const Icon(Icons.refresh),
            onPressed: _restart,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = ((constraints.maxWidth - 32 - 4 * 10) / 5)
                    .clamp(40.0, 84.0);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _StatusBar(game: _game),
                      const SizedBox(height: 20),
                      _sectionLabel('FIREWORKS'),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final c in CardColor.piles)
                            _PileView(
                              color: c,
                              top: _game.fireworks.top(c),
                              width: cardWidth,
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _sectionLabel('DISCARDS'),
                      Expanded(
                        child: SizedBox(
                          width: double.infinity,
                          child: _Discards(cards: _game.discarded),
                        ),
                      ),
                      _messageBar(),
                      const SizedBox(height: 12),
                      _sectionLabel('YOUR HAND'),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (var i = 0; i < handSize; i++)
                            i < _game.hand.length
                                ? CardView(
                                    card: _game.hand[i],
                                    width: cardWidth,
                                    selected: _selected == i,
                                    highlighted: _revealed.contains(
                                      _game.hand[i],
                                    ),
                                    onTap: () => setState(
                                      () =>
                                          _selected = _selected == i ? null : i,
                                    ),
                                  )
                                : SizedBox(width: cardWidth),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _actions(),
                      const SizedBox(height: 12),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _actions() {
    final hasSelection = _selected != null;
    return Row(
      children: [
        Expanded(
          child: _actionButton(
            label: 'Play',
            icon: Icons.auto_awesome,
            color: cardColor(CardColor.green),
            onPressed: hasSelection ? _play : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _actionButton(
            label: 'Discard',
            icon: Icons.delete_outline,
            color: cardColor(CardColor.red),
            onPressed: hasSelection ? _discard : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _actionButton(
            label: 'Hint',
            icon: Icons.lightbulb_outline,
            color: hintColor,
            onPressed: _game.hints > 0 ? _hint : null,
          ),
        ),
      ],
    );
  }

  /// A colored button whose label shrinks instead of wrapping on narrow
  /// screens.
  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageBar() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Container(
        key: ValueKey(_message),
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _message == null
              ? Colors.transparent
              : _messageColor ?? surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _message ?? 'Tap a card to select it',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _message == null ? textMuted : Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: textMuted,
          fontSize: 12,
          letterSpacing: 2,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _stat(
            Icons.lightbulb,
            const Color(0xFF7CC4FF),
            '${game.hints}/$maxHints',
            'hints',
          ),
          _stat(
            Icons.local_fire_department,
            const Color(0xFFE5484D),
            '${game.errors}/$allowedErrors',
            'lives',
          ),
          _stat(Icons.style, textMuted, '${game.deckSize}', 'deck'),
          _stat(Icons.star, accent, '${game.score}', 'score'),
          _stat(Icons.flag_outlined, textMuted, '${game.maxScore()}', 'max'),
        ],
      ),
    );
  }

  Widget _stat(IconData icon, Color color, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Text(label, style: const TextStyle(fontSize: 11, color: textMuted)),
        ],
      ),
    );
  }
}

class _PileView extends StatelessWidget {
  const _PileView({
    required this.color,
    required this.top,
    required this.width,
    this.onTap,
  });

  final CardColor color;
  final GameCard? top;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final base = cardColor(color);
    final card = top;
    final Widget body;
    if (card == null) {
      body = Container(
        width: width,
        height: width * 1.45,
        decoration: BoxDecoration(
          color: base.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(width * 0.14),
          border: Border.all(color: base.withValues(alpha: 0.6), width: 2),
        ),
      );
    } else {
      body = CardView(
        card: GameCard(card.number, card.color)..reveal(),
        width: width,
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          body,
          const SizedBox(height: 6),
          Container(
            width: width * 0.5,
            height: 4,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

class _Discards extends StatelessWidget {
  const _Discards({required this.cards});

  final List<GameCard> cards;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return const Align(
        alignment: Alignment.topLeft,
        child: Text(
          'Nothing discarded yet',
          style: TextStyle(color: textMuted, fontStyle: FontStyle.italic),
        ),
      );
    }
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final color in CardColor.values)
            if (cards.any((c) => c.color == color))
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Wrap(
                  spacing: 0,
                  runSpacing: 0,
                  children: [
                    for (final c
                        in cards.where((c) => c.color == color).toList()
                          ..sort((a, b) => a.number.compareTo(b.number)))
                      MiniCard(card: c, highlighted: identical(c, cards.last)),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
