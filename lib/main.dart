import 'package:flutter/material.dart';

import 'ui/home_screen.dart';
import 'ui/palette.dart';

void main() => runApp(const HanabiApp());

class HanabiApp extends StatelessWidget {
  const HanabiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hanabi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
          surface: surface,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
