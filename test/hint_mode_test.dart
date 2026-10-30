import 'package:flutter_test/flutter_test.dart';
import 'package:hanabi/game/game.dart';
import 'package:hanabi/ui/hint_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final mode in HintMode.values) {
    test('${mode.name} mode gives useful hints', () async {
      final game = Game(strategy: await mode.load());
      final options = game.usefulHints;
      expect(options, contains(game.hint()));
    });
  }
}
