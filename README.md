# RestoriaIdle

Mobile-first game set in Restoria, built from the Game Bible and the compact JSON
database in `content/`. One account carries one character, on whichever device it
is signed in on.

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
flutter build web --release # Ship it

# From the repo root, the same as `flutter run` against the web-server device:
npm run dev                 # Serves the Flutter client at http://localhost:5173

npm install
npm test                    # The reference rules, and the fixture drift check
```

## Notes

- Sign-in comes first: the character belongs to the account, not to the phone.
- Loads `content/data/game-database.json`, the same copy both halves read.
- Signing in loads the account's save, and signs the other device out.
- The save is written back on its own; there is no sync button to press.
