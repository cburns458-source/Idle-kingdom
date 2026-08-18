# RestoriaIdle — Flutter client

The Flutter front end for the game whose rules live in `../packages`. This package
holds UI only: widgets format and lay out, and every number they show comes from
`ik_rules` or `ik_runtime`.

```bash
flutter run -d chrome   # or any attached device
flutter test
flutter analyze
```

`content/` is a symlink to the repo's shared `content/` directory, so this client
and the React app read the same data and art. New asset folders have to be added
to the `assets:` list in `pubspec.yaml` — Flutter does not include them
recursively.

See [`../docs/flutter-migration.md`](../docs/flutter-migration.md) for how this
fits together with the Dart packages and the parity harness.
