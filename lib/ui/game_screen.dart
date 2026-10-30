import 'package:flutter/material.dart';

import '../game/card.dart';
import '../game/game.dart';
import '../sim/expert.dart';
import '../sim/hint_search.dart';
import '../sim/simulated_player.dart';
import 'advisor.dart';
import 'card_view.dart';
import 'hint_mode.dart';
import 'palette.dart';
import 'settings.dart';
import 'strings.dart';

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

  /// Suggests moves and shows each card's odds (dev mode); null until loaded.
  SimulatedPlayer? _advisor;
  bool _showAdvice = true;

  /// Moves made so far, so the advice is computed once per move and not on
  /// every rebuild (it is costly on the web).
  int _moves = 0;
  Advice? _advice;
  int _adviceMoves = -1;

  Advice? _currentAdvice() {
    final advisor = _advisor;
    if (!Settings.devMode.value || !_showAdvice || advisor == null) {
      return null;
    }
    if (_game.isOver) return null;
    if (_adviceMoves != _moves) {
      _advice = Advice(_game, advisor);
      _adviceMoves = _moves;
    }
    return _advice;
  }

  @override
  void initState() {
    super.initState();
    // The search picks hints expecting the expert's way of playing, and the
    // trained agent plays badly with them (17 instead of 21.5 points).
    if (widget.strategy is SearchHints) {
      _advisor = ExpertPlayer.tuned;
      return;
    }
    loadAdvisor.then((a) {
      if (mounted) setState(() => _advisor = a);
    });
  }

  /// Cards revealed by the last hint, highlighted until the next move.
  Set<GameCard> _revealed = {};

  void _restart() => setState(() {
    _game = Game(strategy: widget.strategy);
    _selected = null;
    _revealed = {};
    _moves++;
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
      _moves++;
    });
    if (result case PlayFailure(:final card)) {
      _toast(tr.misfire(card), color: const Color(0xFF8C1D24));
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
      _moves++;
    });
    _toast(tr.discarded(card));
    _checkEnd();
  }

  /// While the search hint giver is thinking: no other move meanwhile.
  bool _thinking = false;

  Future<void> _hint() async {
    final Hint? picked;
    if (widget.strategy case final SearchHints search) {
      if (_game.usefulHints.isEmpty) {
        _toast(tr.allKnown);
        return;
      }
      setState(() => _thinking = true);
      _toast(tr.thinking);
      final chosen = await search.chooseWithin(
        Game.copy(_game),
        const Duration(milliseconds: 1500),
      );
      if (!mounted) return;
      setState(() => _thinking = false);
      if (chosen == null) return;
      _game.giveHint(chosen);
      picked = chosen;
    } else {
      picked = _game.hint();
    }
    if (picked == null) {
      _toast(tr.allKnown);
      return;
    }
    final hint = picked;
    setState(() {
      _moves++;
      _revealed = switch (hint) {
        NumberHint(:final number) =>
          _game.hand.where((c) => c.number == number).toSet(),
        ColorHint(:final color) =>
          _game.hand.where((c) => c.color == color).toSet(),
      };
    });
    _toast(switch (hint) {
      NumberHint(:final number) => tr.numberHint(number),
      ColorHint(:final color) => tr.colorHint(color),
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
              Text(
                tr.chooseJokerPile,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
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

  Future<void> _checkEnd() async {
    if (!_game.isOver) return;
    final won = _game.fireworks.victory;
    final record = await Settings.recordGame(_game.score);
    if (!mounted) return;
    final stats = Settings.stats.value;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: surface,
        title: Text(
          won
              ? tr.perfectShow
              : record
              ? tr.newRecord
              : tr.showOver,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr.yourScore(_game.score),
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 12),
            Text(tr.endStats(stats), style: const TextStyle(color: textMuted)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(this.context);
            },
            child: Text(tr.menu),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _restart();
            },
            child: Text(tr.playAgain),
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
              tr.hintsSubtitle(widget.mode.label),
              style: const TextStyle(fontSize: 12, color: textMuted),
            ),
          ],
        ),
        actions: [
          if (Settings.devMode.value)
            IconButton(
              tooltip: _showAdvice ? tr.hideAdvice : tr.showAdvice,
              icon: Icon(
                _showAdvice
                    ? Icons.tips_and_updates
                    : Icons.tips_and_updates_outlined,
              ),
              color: _showAdvice ? accent : null,
              onPressed: () => setState(() => _showAdvice = !_showAdvice),
            ),
          IconButton(
            tooltip: tr.newGame,
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
                final advice = _currentAdvice();
                final possible = Settings.devMode.value
                    ? possibleCards(_game)
                    : null;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      _StatusBar(game: _game),
                      const SizedBox(height: 20),
                      _sectionLabel(tr.fireworks),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final c in CardColor.piles)
                            _PileView(
                              color: c,
                              top: _game.fireworks.top(c),
                              width: cardWidth,
                              wild: _game.fireworks.floatingJoker == c,
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _sectionLabel(tr.discards),
                      Expanded(
                        child: SizedBox(
                          width: double.infinity,
                          child: _Discards(cards: _game.discarded),
                        ),
                      ),
                      _messageBar(),
                      const SizedBox(height: 12),
                      _sectionLabel(tr.yourHand),
                      if (advice != null) _suggestion(advice),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < handSize; i++)
                            i < _game.hand.length
                                ? Column(
                                    children: [
                                      CardView(
                                        card: _game.hand[i],
                                        width: cardWidth,
                                        selected: _selected == i,
                                        highlighted: _revealed.contains(
                                          _game.hand[i],
                                        ),
                                        outline: advice?.cardIndex == i
                                            ? advice!.color
                                            : null,
                                        possible: possible?[i],
                                        onTap: () => setState(
                                          () => _selected = _selected == i
                                              ? null
                                              : i,
                                        ),
                                      ),
                                      if (advice != null) ...[
                                        const SizedBox(height: 4),
                                        OddsLabel(
                                          odds: advice.odds[i],
                                          width: cardWidth,
                                          suggested: advice.cardIndex == i
                                              ? advice.color
                                              : null,
                                        ),
                                      ],
                                    ],
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
            label: tr.play,
            icon: Icons.auto_awesome,
            color: cardColor(CardColor.green),
            onPressed: hasSelection && !_thinking ? _play : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _actionButton(
            label: tr.discard,
            icon: Icons.delete_outline,
            color: cardColor(CardColor.red),
            onPressed: hasSelection && !_thinking ? _discard : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _actionButton(
            label: tr.hint,
            icon: Icons.lightbulb_outline,
            color: hintColor,
            onPressed: _game.hints > 0 && !_thinking ? _hint : null,
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
          _message ?? tr.tapCard,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _message == null ? textMuted : Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// The advisor's move; tapping it selects the card it is about.
  Widget _suggestion(Advice advice) {
    final color = advice.color;
    return GestureDetector(
      onTap: () => setState(() => _selected = advice.cardIndex),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(Icons.tips_and_updates, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${tr.ai}: ${advice.describe()}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
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
            tr.hintsStat,
          ),
          _stat(
            Icons.local_fire_department,
            const Color(0xFFE5484D),
            '${game.errors}/$allowedErrors',
            tr.livesStat,
          ),
          _stat(Icons.style, textMuted, '${game.deckSize}', tr.deckStat),
          _stat(Icons.star, accent, '${game.score}', tr.scoreStat),
          _stat(
            Icons.flag_outlined,
            textMuted,
            '${game.maxScore()}',
            tr.maxStat,
          ),
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
    this.wild = false,
    this.onTap,
  });

  final CardColor color;
  final GameCard? top;
  final double width;

  /// A lone 1-joker: not tied to this color yet, it moves if a real card
  /// needs the pile.
  final bool wild;
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
      // A joker on top would hide which pile this is: frame it in its color.
      body = CardView(
        card: GameCard(card.number, card.color)..reveal(),
        width: width,
        outline: card.isJoker ? base : null,
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          body,
          const SizedBox(height: 6),
          // The color bar always stays, so the pile is recognisable; a
          // floating joker adds its label below without moving the layout.
          SizedBox(
            height: 4,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                Container(
                  width: width * 0.5,
                  height: 4,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                if (wild)
                  Positioned(
                    top: 6,
                    child: Text(
                      tr.wild,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1,
                        color: textMuted,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
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
      return Align(
        alignment: Alignment.topLeft,
        child: Text(
          tr.noDiscards,
          style: const TextStyle(color: textMuted, fontStyle: FontStyle.italic),
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

/// What each card in hand can still be, given the hints and every card in
/// sight: all copies of a card on the piles, discarded or known in hand
/// rule it out.
List<Possible> possibleCards(Game game) {
  final view = PlayerView(game);
  return [
    for (var i = 0; i < game.hand.length; i++)
      () {
        final options = view.weights(i).keys;
        return (
          numbers: [
            for (var n = 1; n <= 5; n++)
              if (options.any((o) => o.$1 == n)) n,
          ],
          colors: [
            for (final c in CardColor.values)
              if (options.any((o) => o.$2 == c)) c,
          ],
        );
      }(),
  ];
}
