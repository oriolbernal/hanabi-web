# hanabi_flutter

Flutter (mobile + web) version of the Hanabi solitaire from `../hanabi-console`.

- `lib/game/` – pure Dart game logic (port of the Java rules)
- `lib/ui/` – screens and widgets

```sh
flutter run -d chrome      # web
flutter run                # connected phone / simulator
flutter test               # game logic tests
flutter build web          # output in build/web
```

## Benchmarking hint strategies

The hint given when you press *Hint* comes from a `HintStrategy`
(`lib/game/hint_strategy.dart`). To compare strategies, a simulated player
(`lib/sim/simulated_player.dart`) plays thousands of games on the same decks:

```sh
dart run bin/benchmark.dart 10000      # games per strategy
```
