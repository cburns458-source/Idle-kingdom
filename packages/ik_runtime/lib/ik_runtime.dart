/// Headless game runtime shared by every Dart client.
///
/// Ported from the tick loops currently living in `src/App.tsx`, so the Flutter
/// UI only renders state and forwards intents.
library;

export 'src/save_storage.dart';
export 'src/session/events.dart';
export 'src/session/progress.dart';
export 'src/session/tick.dart';
