import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

/// A numeric Config value, falling back when the row is missing or non-numeric.
///
/// Ported from `configNumber` in `src/game/activity/gathering.ts`; the duration
/// rules in that module arrive with the activity engine.
num configNumber(GameDatabase db, String key, num fallback) {
  final value = db.config.firstWhereOrNull((row) => row.raw['Key'] == key)?.raw['Value'];
  return value is num && value.isFinite ? value : fallback;
}
