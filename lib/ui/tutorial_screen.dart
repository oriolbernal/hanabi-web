import 'package:flutter/material.dart';

import '../game/card.dart';
import 'card_view.dart';
import 'palette.dart';
import 'strings.dart';

class _Step {
  const _Step(this.title, this.text, this.cards);
  final String title;
  final String text;
  final List<GameCard> cards;
}

/// The texts come from [Strings.tutorial], in the same order.
List<_Step> get _steps => [
  for (final (i, (title, text)) in tr.tutorial.indexed)
    _Step(title, text, _cards[i]),
];

GameCard _card(int n, CardColor c, {bool number = false, bool color = false}) =>
    GameCard(n, c)
      ..knownNumber = number
      ..knownColor = color;

final _cards = <List<GameCard>>[
  [
    for (var n = 1; n <= 5; n++)
      _card(n, CardColor.red, number: true, color: true),
  ],
  [
    _card(2, CardColor.red),
    _card(1, CardColor.green),
    _card(5, CardColor.blue),
    _card(1, CardColor.yellow),
    _card(1, CardColor.white),
  ],
  [
    _card(2, CardColor.red),
    _card(1, CardColor.green, number: true),
    _card(5, CardColor.blue),
    _card(1, CardColor.yellow, number: true),
    _card(1, CardColor.white, number: true),
  ],
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
  [],
  [
    for (var n = 1; n <= 3; n++)
      _card(n, CardColor.joker, number: true, color: true),
  ],
  [],
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
    final steps = _steps;
    final last = _page == steps.length - 1;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(tr.howToPlay),
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
                    children: [for (final s in steps) _buildStep(s)],
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < steps.length; i++)
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
                        child: Text(last ? tr.gotIt : tr.next),
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
