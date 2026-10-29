# hanabi_flutter

Flutter (mobile + web) version of the Hanabi solitaire from `../hanabi-console`.

Play it at https://oriolbernal.github.io/hanabi-web/

## Documentation

- [How the AI was trained](docs/rl.md) – reinforcement learning, every
  experiment, results and training curves (in Catalan).
- [`rl/README.md`](rl/README.md) – technical notes for the training code.

## Code

- `lib/game/` – pure Dart game logic (port of the Java rules)
- `lib/ui/` – screens and widgets
- `lib/sim/` – simulated players, hint strategies, trained policies
- `rl/` – reinforcement learning training (Python)

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
