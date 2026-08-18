import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../combat/engine.dart';
import '../config.dart';
import '../equipment/vitals.dart';
import '../save/generated/save_models.dart';

const String templeLocationId = 'LOC-0036';

bool locationHasBlessing(LocationRow? location) {
  return location?.raw['Internal Key'] == 'temple';
}

class BlessResult {
  const BlessResult.ok(this.save, {required this.alreadyFull, String? message})
    : reason = null,
      _message = message;

  const BlessResult.failed(this.reason, {String? message})
    : save = null,
      alreadyFull = false,
      _message = message;

  final PlayerSave? save;
  final String? reason;
  final bool alreadyFull;
  final String? _message;

  bool get ok => reason == null;

  String get message =>
      _message ??
      (alreadyFull ? 'You are already at full health.' : 'The monks restore you to full health.');
}

/// Instant Temple heal. Does not start an activity or change equipment.
BlessResult requestBlessing(GameDatabase db, PlayerSave save, num nowMs) {
  if (isDeathPaused(save, nowMs)) {
    return const BlessResult.failed('Cannot receive a blessing while recovering from defeat.');
  }
  final location = db.locations.firstWhereOrNull((row) => row.locationId == save.currentLocationId);
  if (!locationHasBlessing(location)) {
    return BlessResult.failed(
      configString(db, 'copy.amenity.blessing.not_here', 'The monks are not here.'),
    );
  }

  final next = withRecalculatedVitals(db, save);
  if (next.currentHp >= next.maxHp) {
    return BlessResult.ok(
      next,
      alreadyFull: true,
      message: configString(
        db,
        'copy.amenity.blessing.already_full',
        'You are already at full health.',
      ),
    );
  }
  return BlessResult.ok(
    next.copyWith(currentHp: next.maxHp),
    alreadyFull: false,
    message: configString(
      db,
      'copy.amenity.blessing.restored',
      'The monks restore you to full health.',
    ),
  );
}
