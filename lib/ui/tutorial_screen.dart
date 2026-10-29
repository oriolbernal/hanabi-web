import 'package:flutter/material.dart';

import '../game/card.dart';
import '../game/game.dart';
import 'card_view.dart';
import 'palette.dart';

class _Step {
  const _Step(this.title, this.text, this.cards);
  final String title;
  final String text;
  final List<GameCard> cards;
}

GameCard _card(int n, CardColor c, {bool number = false, bool color = false}) =>
    GameCard(n, c)
      ..knownNumber = number
      ..knownColor = color;

final _steps = [
  _Step(
    'The goal',
    'Each card has a NUMBER and a COLOR. Build one firework per color by '
        'stacking its cards in order, from 1 to 5. A perfect show scores 25.',
    [
      for (var n = 1; n <= 5; n++)
        _card(n, CardColor.red, number: true, color: true),
    ],
  ),
  _Step(
    'Your hand',
    'You hold $handSize cards, but you cannot see them. '
        'Tap a card to select it, then play or discard it.',
    [
      _card(2, CardColor.red),
      _card(1, CardColor.green),
      _card(5, CardColor.blue),
      _card(1, CardColor.yellow),
      _card(1, CardColor.white),
    ],
  ),
  _Step(
    'Hints',
    'Ask for a hint to reveal all your cards sharing a number or a color. '
        'You have $maxHints hint tokens; discarding a card gives one back.',
    [
      _card(2, CardColor.red),
      _card(1, CardColor.green, number: true),
      _card(5, CardColor.blue),
      _card(1, CardColor.yellow, number: true),
      _card(1, CardColor.white, number: true),
    ],
  ),
  _Step(
    'What hints rule out',
    'A hint also tells you about the cards it does not touch. After "these '
        'are your 1s", the others show the numbers they can still be; after '
        '"these are green", the dots show the colors still possible.',
    [
      _card(2, CardColor.red)
        ..notNumbers.add(1)
        ..notColors.add(CardColor.green),
      _card(1, CardColor.green, number: true, color: true),
      _card(5, CardColor.blue)
        ..notNumbers.add(1)
        ..notColors.add(CardColor.green),
      _card(1, CardColor.yellow, number: true)..notColors.add(CardColor.green),
      _card(3, CardColor.green, color: true)..notNumbers.add(1),
    ],
  ),
  _Step(
    'Misfires',
    'Playing a card that does not fit costs a life. '
        'Lose $allowedErrors lives and the show is over. '
        'The game also ends when the deck and your hand run out.',
    [],
  ),
  _Step(
    'Jokers',
    'There are five rainbow jokers, numbered 1 to 5. A joker can go on any '
        'firework. A joker 1 takes the first free spot, marked "wild", and '
        'steps aside if a real 1 needs it. For higher jokers you choose the '
        'firework. Keep them for where they are needed: each joker can '
        'replace one lost card.',
    [
      for (var n = 1; n <= 3; n++)
        _card(n, CardColor.joker, number: true, color: true),
    ],
  ),
  _Step(
    'Max score',
    'The flag in the top bar shows the best score still reachable. It drops '
        'when every copy of a card you needed is gone, so discard carefully: '
        'losing one 5 costs nothing while the joker 5 can replace it, a '
        'second one costs a point.',
    [],
  ),
];

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _steps.length - 1;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('How to play'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: _controller,
                    onPageChanged: (p) => setState(() => _page = p),
                    children: [for (final s in _steps) _buildStep(s)],
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _steps.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.all(4),
                        width: i == _page ? 20 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _page ? accent : surfaceHigh,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: last
                          ? () => Navigator.pop(context)
                          : () => _controller.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(last ? 'Got it!' : 'Next'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(_Step step) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (step.cards.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final c in step.cards) CardView(card: c, width: 52),
              ],
            ),
            const SizedBox(height: 32),
          ],
          Text(
            step.title,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(
            step.text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, height: 1.5),
          ),
        ],
      ),
    );
  }
}
