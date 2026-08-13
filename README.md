# Idle Kingdoms (Single-Player Demo)

Offline-capable, mobile-first game built from the Game Bible and the compact JSON
database in `content/`.

The game is the Flutter client in `app_flutter/`, over the Dart packages in
`packages/`. What remains under `src/` is not an app: it is the TypeScript rules
the Dart port was recorded from, kept as the parity reference. See
[docs/flutter-migration.md](docs/flutter-migration.md).

## Commands

```bash
dart pub get
dart test packages          # Rules, runtime, multiplayer, and parity replay

cd app_flutter
flutter test                # Widget tests over a fake clock and in-memory storage
flutter run -d chrome       # Play it

npm install
npm test                    # The reference rules, and the fixture drift check
```

## Notes

- Launches straight into the game: no login, and no account needed to play.
- Loads `content/data/game-database.json`, the same copy both halves read.
- Creates and reloads one local save automatically.
- Accounts, cloud saves, and the social screens are optional, and hidden until
  someone signs in.
