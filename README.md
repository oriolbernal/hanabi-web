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
