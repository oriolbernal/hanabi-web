import 'package:flutter/material.dart';

import '../game/card.dart';
import 'game_screen.dart';
import 'palette.dart';
import 'tutorial_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
                  const SizedBox(height: 48),
                  SizedBox(
                    width: 240,
                    child: FilledButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const GameScreen()),
                      ),
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
