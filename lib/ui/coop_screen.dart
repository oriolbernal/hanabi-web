import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/card.dart';
import '../game/coop.dart';
import '../game/game.dart';
import '../sim/coop_net.dart';
import '../sim/coop_search.dart';
import 'card_view.dart';
import 'game_screen.dart';
import 'move_log.dart';
import 'palette.dart';
import 'settings.dart';
import 'strings.dart';

/// The bots' names, one per seat after yours.
const botNames = ['Aiko', 'Ren', 'Sora'];

/// A cooperative game: you (player 0) and [players] - 1 bots take turns.
/// You see their cards but not yours; tap your card to play or discard it,
/// or a partner's card to hint its number or color.
class CoopScreen extends StatefulWidget {
  const CoopScreen({super.key, required this.players});

  final int players;

  @override
  State<CoopScreen> createState() => _CoopScreenState();
}

/// A selected card: whose hand and which position.
typedef _Pick = ({int player, int index});

class _CoopScreenState extends State<CoopScreen> {
  late CoopGame _game = _deal();

  /// A fresh game; in dev mode the deck order opens its record in [MoveLog].
  CoopGame _deal() {
    final deck = buildDeck();
    if (Settings.devMode.value) {
      MoveLog.startGame(deck, mode: 'coop${widget.players}');
    }
    return CoopGame(players: widget.players, deck: List.of(deck));
  }

  /// The network trained on the search (rl/models/C8: 512x512, on every
  /// round of data taught by the search that imagines the person's way of
  /// playing). Bots only try a card that fits for sure or at least 80%
  /// likely, with a life to spare: blind plays made 1.5 misfires a game.
  /// bin/coop_eval.dart, seat 0 played by the person model, 300 games:
  /// 2 players 21.6 (rules 21.1), 3 players 23.9 (22.5), 4 players 24.3
  /// (22.7), about 0.3 bot misfires a game. Until it has loaded, the search
  /// plays.
  CoopMove _decide(CoopGame g) => _net?.decide(g) ?? _fallback.decide(g);

  static CoopNet? _net;
  static final _fallback = CoopSearch(rounds: 128, minPlayChance: 0.8);

  /// Loads the network once; until it is there, the search plays.
  static final Future<void> _loading = rootBundle
      .loadString('assets/models/coop_policy.json')
      .then(
        (json) => _net = CoopNet(
          jsonDecode(json) as Map<String, dynamic>,
          minPlayChance: 0.8,
        ),
      );

  @override
  void initState() {
    super.initState();
    _loading.then((_) {}, onError: (_) {});
  }

  /// Pause before each bot moves, so you can follow what happens.
  static const _botDelay = Duration(milliseconds: 1100);

  _Pick? _selected;

  /// What happened since your last move, oldest first.
  final List<String> _news = [];

  /// Cards pointed at by the hints in [_news].
  final Set<GameCard> _revealed = {};

  /// Whether a card in [_news] misfired.
  bool _misfire = false;

  /// Each player's last move, shown next to their name.
  late List<String?> _lastMove = List.filled(widget.players, null);

  /// Changes on every new game, so bot turns of an old game stop.
  int _round = 0;

  bool get _myTurn => _game.current == 0 && !_game.isOver;

  String? _name(int player) => player == 0 ? null : botNames[player - 1];

  String _label(int player) => player == 0 ? tr.you : botNames[player - 1];

  void _restart() => setState(() {
    _round++;
    _game = _deal();
    _selected = null;
    _news.clear();
    _revealed.clear();
    _misfire = false;
    _lastMove = List.filled(widget.players, null);
  });

  /// Applies [move] for the current player and reports it.
  void _apply(CoopMove move) {
    final who = _game.current;
    if (Settings.devMode.value) MoveLog.recordCoop(move);
    final String text;
    switch (move) {
      case CoopPlay(:final index, :final target):
        final card = _game.hands[who][index];
        final result = _game.play(index, target: target);
        _misfire |= result is PlayFailure;
        text = tr.playedBy(_name(who), card, fits: result is PlaySuccess);
      case CoopDiscard(:final index):
        text = tr.discardedBy(_name(who), _game.discard(index));
      case CoopHint(:final to, :final hint):
        _revealed.addAll(_game.hint(to, hint));
        text = tr.hintedBy(_name(who), _name(to), hint);
    }
    _news.add(text);
    _lastMove[who] = text;
  }

  Future<void> _myMove(CoopMove move) async {
    setState(() {
      _news.clear();
      _revealed.clear();
      _misfire = false;
      _selected = null;
      _apply(move);
    });
    await _runBots();
  }

  Future<void> _runBots() async {
    final round = _round;
    while (!_game.isOver && _game.current != 0) {
      setState(() {});
      await Future<void>.delayed(_botDelay);
      if (!mounted || round != _round) return;
      // About 0.1 s on a laptop browser.
      final move = _decide(_game);
      setState(() => _apply(move));
    }
    if (_game.isOver) await _showEnd();
  }

  Future<void> _play() async {
    final pick = _selected;
    if (pick == null || pick.player != 0) return;
    CardColor? target;
    if (_game.needsTarget(pick.index)) {
      target = await _askTarget();
      if (target == null) return;
    }
    await _myMove(CoopPlay(pick.index, target: target));
  }

  Future<void> _discard() async {
    final pick = _selected;
    if (pick == null || pick.player != 0) return;
    await _myMove(CoopDiscard(pick.index));
  }

  Future<void> _hint(Hint hint) async {
    final pick = _selected;
    if (pick == null || pick.player == 0) return;
    await _myMove(CoopHint(pick.player, hint));
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
                    PileView(
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

  Future<void> _showEnd() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: surface,
        title: Text(_game.fireworks.victory ? tr.perfectShow : tr.showOver),
        content: Text(
          tr.teamScore(_game.score),
          style: const TextStyle(fontSize: 18),
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
              '${tr.coop} · ${widget.players} ${tr.playersHeader.toLowerCase()}',
              style: const TextStyle(fontSize: 12, color: textMuted),
            ),
          ],
        ),
        actions: [
          if (Settings.devMode.value)
            IconButton(
              tooltip: tr.copyLog,
              icon: const Icon(Icons.copy_all),
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: await MoveLog.export()),
                );
                final games = await MoveLog.length;
                if (!mounted) return;
                setState(() {
                  _news
                    ..clear()
                    ..add(tr.logCopied(games));
                });
              },
            ),
          IconButton(
            tooltip: tr.newGame,
            icon: const Icon(Icons.refresh),
            onPressed: _restart,
          ),
        ],
      ),
      // Always in reach, however tall the table gets with four players.
      bottomNavigationBar: SafeArea(
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: _actions(),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = ((constraints.maxWidth - 32 - 4 * 10) / 5)
                    .clamp(40.0, 84.0);
                final partnerWidth = (cardWidth * 0.62).clamp(32.0, 52.0);
                // Only the discards scroll, so your hand and the hints
                // you receive always stay in sight.
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _body(cardWidth, partnerWidth),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(double cardWidth, double partnerWidth) {
    final possible = Settings.devMode.value
        ? possibleCards(_game.viewFor(0))
        : null;
    // The table scrolls when it does not fit; your hand, what just
    // happened and the buttons stay put below it.
    final table = Column(
      children: [
        StatusBar(
          hints: _game.hints,
          lives: _game.errors,
          deck: _game.deckSize,
          score: _game.score,
          max: _game.maxScore(),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final c in CardColor.piles)
              PileView(
                color: c,
                top: _game.fireworks.top(c),
                width: cardWidth * 0.68,
                wild: _game.fireworks.floatingJoker == c,
              ),
          ],
        ),
        const SizedBox(height: 14),
        for (var p = 1; p < _game.players; p++) _partner(p, partnerWidth),
        const SizedBox(height: 6),
        _sectionLabel(tr.discards),
        SizedBox(
          width: double.infinity,
          child: DiscardsView(cards: _game.discarded, scrolls: false),
        ),
        const SizedBox(height: 8),
      ],
    );
    return Column(
      children: [
        Expanded(child: SingleChildScrollView(child: table)),
        const SizedBox(height: 8),
        _messageBar(),
        const SizedBox(height: 10),
        _turnLabel(0, tr.yourHand),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < 5; i++)
              i < _game.hands[0].length
                  ? CardView(
                      card: _game.hands[0][i],
                      width: cardWidth,
                      selected: _selected == (player: 0, index: i),
                      highlighted: _revealed.contains(_game.hands[0][i]),
                      possible: possible?[i],
                      onTap: () => _select(0, i),
                    )
                  : SizedBox(width: cardWidth),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  void _select(int player, int index) => setState(() {
    final pick = (player: player, index: index);
    _selected = _selected == pick ? null : pick;
  });

  /// A partner's name, last move and face-up hand.
  Widget _partner(int p, double width) {
    final hand = _game.hands[p];
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _game.current == p && !_game.isOver
              ? accent.withValues(alpha: 0.7)
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _label(p),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  _game.current == p && !_game.isOver
                      ? tr.botThinking(_label(p))
                      : _lastMove[p] ?? '',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _game.current == p ? accent : textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          for (var i = 0; i < hand.length; i++)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: FaceCardView(
                card: hand[i],
                width: width,
                selected: _selected == (player: p, index: i),
                highlighted: _revealed.contains(hand[i]),
                onTap: () => _select(p, i),
              ),
            ),
        ],
      ),
    );
  }

  Widget _turnLabel(int player, String text) => Row(
    children: [
      Text(
        text,
        style: const TextStyle(
          color: textMuted,
          fontSize: 12,
          letterSpacing: 2,
          fontWeight: FontWeight.w600,
        ),
      ),
      const Spacer(),
      if (_myTurn)
        Text(
          tr.yourTurn,
          style: const TextStyle(
            color: accent,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
    ],
  );

  Widget _sectionLabel(String text) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 6),
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

  /// What happened since your last move, or what to do.
  Widget _messageBar() {
    final text = _news.isNotEmpty
        ? _news.join('\n')
        : _myTurn && _game.hints == 0
        ? tr.noHintTokens
        : tr.tapCardCoop;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Container(
        key: ValueKey(text),
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _news.isEmpty
              ? Colors.transparent
              : _misfire
              ? const Color(0xFF8C1D24)
              : surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _news.isEmpty ? textMuted : Colors.white,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _actions() {
    final pick = _selected;
    if (pick != null && pick.player != 0) {
      final card = _game.hands[pick.player][pick.index];
      final canHint = _myTurn && _game.hints > 0;
      return Row(
        children: [
          Expanded(
            child: _actionButton(
              label: '${tr.hint}: ${card.number}',
              icon: Icons.lightbulb_outline,
              color: hintColor,
              onPressed: canHint ? () => _hint(NumberHint(card.number)) : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _actionButton(
              label: '${tr.hint}: ${tr.colorName(card.color)}',
              icon: Icons.palette_outlined,
              color: hintColor,
              onPressed: canHint ? () => _hint(ColorHint(card.color)) : null,
            ),
          ),
        ],
      );
    }
    final mine = pick != null && _myTurn;
    return Row(
      children: [
        Expanded(
          child: _actionButton(
            label: tr.play,
            icon: Icons.auto_awesome,
            color: cardColor(CardColor.green),
            onPressed: mine ? _play : null,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _actionButton(
            label: tr.discard,
            icon: Icons.delete_outline,
            color: cardColor(CardColor.red),
            onPressed: mine ? _discard : null,
          ),
        ),
      ],
    );
  }

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
}
