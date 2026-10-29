import 'package:flutter/material.dart';

import '../game/card.dart';
import 'game_screen.dart';
import 'hint_mode.dart';
import 'palette.dart';
import 'tutorial_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HintMode _mode = HintMode.ai;

  Future<void> _play() async {
    final mode = _mode;
    final strategy = await mode.load();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameScreen(mode: mode, strategy: strategy),
      ),
    );
  }

  Widget _modeSelector() {
    return Column(
      children: [
        const Text(
          'HINTS',
          style: TextStyle(
            color: textMuted,
            fontSize: 12,
            letterSpacing: 2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<HintMode>(
          showSelectedIcon: false,
          segments: [
            for (final m in HintMode.values)
              ButtonSegment(value: m, label: Text(m.label)),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: Text(
            _mode.description,
            textAlign: TextAlign.center,
            style: const TextStyle(color: textMuted, fontSize: 13),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.6),
            radius: 1.2,
            colors: [Color(0xFF1E2750), background],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final c in CardColor.piles)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            Icons.auto_awesome,
                            color: cardColor(c),
                            size: 28,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'HANABI',
                    style: TextStyle(
                      fontSize: 52,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 12,
                    ),
                  ),
                  const Text(
                    'solitaire',
                    style: TextStyle(
                      fontSize: 16,
                      color: textMuted,
                      letterSpacing: 4,
                    ),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(width: 280, child: _modeSelector()),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 240,
                    child: FilledButton(
                      onPressed: _play,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Play', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 240,
                    child: OutlinedButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TutorialScreen(),
                        ),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'How to play',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
