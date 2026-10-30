import 'package:flutter_test/flutter_test.dart';
import 'package:hanabi/game/card.dart';
import 'package:hanabi/ui/strings.dart';

void main() {
  final english = Language.en.strings;

  for (final language in Language.values) {
    final s = language.strings;

    test('${language.name} has every tutorial step', () {
      expect(s.tutorial, hasLength(english.tutorial.length));
    });

    test('${language.name} names every color', () {
      for (final c in CardColor.values) {
        expect(s.colorName(c), isNotEmpty);
        expect(s.colorHint(c), isNotEmpty);
      }
    });
  }

  test('Catalan and Spanish use a decimal comma', () {
    expect(Language.ca.strings.decimal(18.25), '18,3');
    expect(Language.es.strings.decimal(0.4), '0,4');
    expect(english.decimal(0.4), '0.4');
  });
}
