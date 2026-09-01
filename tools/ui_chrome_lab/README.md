# UI Chrome Lab

Standalone Flutter web playground for RestoriaIdle chrome directions.
**Does not import or modify game client code.**

## Run locally

```bash
cd tools/ui_chrome_lab
flutter pub get
flutter run -d chrome
# or
flutter build web --release --pwa-strategy=none
python3 -m http.server 8765 -d build/web
```

## Styles

| Chip | Source | License |
|------|--------|---------|
| A Baseline | Current game language (mock) | n/a |
| B nes_ui | https://pub.dev/packages/nes_ui | MIT |
| C pixel_ui | https://pub.dev/packages/pixel_ui | MIT |
| D Kenney | Fantasy UI Borders panels | CC0 |
| E Leather | Custom painters + noise | n/a |

