import 'package:flutter_test/flutter_test.dart';
import 'package:hanabi/ui/settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('records games, best score, averages and survives a reload', () async {
    SharedPreferences.setMockInitialValues({});
    await Settings.load();
    expect(await Settings.recordGame(15), isFalse); // first game: no record
    expect(await Settings.recordGame(18), isTrue);
    expect(await Settings.recordGame(12), isFalse);
    final s = Settings.stats.value;
    expect((s.played, s.best), (3, 18));
    expect(s.average, 15);

    Settings.stats.value = Stats(const []);
    await Settings.load();
    expect(Settings.stats.value.scores, [15, 18, 12]);
  });
}
