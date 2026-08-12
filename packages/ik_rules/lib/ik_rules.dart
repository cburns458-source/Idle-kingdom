/// Pure Dart port of the Idle Kingdoms rules in `src/game`.
///
/// Nothing here may import `dart:io`, `dart:html`, or Flutter: the rules stay
/// testable headlessly and identically to the TypeScript original. Time and
/// randomness are always parameters, never ambient globals.
///
/// Generated save models define no `==`; compare them through `toJson`, which is
/// also how the parity fixtures check them.
library;

export 'src/activity/requirements.dart';
export 'src/activity/xp.dart';
export 'src/activity/xp_progress.dart';
export 'src/inventory/add_items.dart';
export 'src/inventory/capacity.dart';
export 'src/inventory/destroy.dart';
export 'src/inventory/favorites.dart';
export 'src/inventory/gold.dart';
export 'src/js_compat.dart';
export 'src/json_support.dart';
export 'src/rng/mulberry32.dart';
export 'src/save/generated/save_models.dart';
export 'src/skills/totals.dart';
