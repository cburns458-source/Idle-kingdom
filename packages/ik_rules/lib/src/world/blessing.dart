import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../combat/engine.dart';
import '../config.dart';
import '../equipment/vitals.dart';
import '../save/generated/save_models.dart';

const String templeLocationId = 'LOC-0036';
const num blessingOverhealRatio = 0.1;

/// Blessing always snaps to 110% of current max. Extra 10% does not stack.
num blessedCurrentHp(num maxHp) => maxHp + (maxHp * blessingOverhealRatio).floor();

bool locationHasBlessing(LocationRow? location) {
  return location?.raw['Internal Key'] == 'temple';
}

class BlessResult {
  const BlessResult.ok(this.save, {required this.alreadyFull, this._message}) : reason = null;

  const BlessResult.failed(this.reason, {this._message}) : save = null, alreadyFull = false;

  final PlayerSave? save;
  final String? reason;
  final bool alreadyFull;
  final String? _message;

  bool get ok => reason == null;

  String get message =>
      _message ??
      (alreadyFull
          ? "The monks' blessing already fills you."
          : 'The monks restore you beyond full health.');
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
  final targetHp = blessedCurrentHp(next.maxHp);
  final alreadyBlessed = next.currentHp >= targetHp;
  return BlessResult.ok(
    next.copyWith(currentHp: targetHp),
    alreadyFull: alreadyBlessed,
    message: alreadyBlessed
        ? configString(
            db,
            'copy.amenity.blessing.already_full',
            "The monks' blessing already fills you.",
          )
        : configString(
            db,
            'copy.amenity.blessing.restored',
            'The monks restore you beyond full health.',
          ),
  );
}
