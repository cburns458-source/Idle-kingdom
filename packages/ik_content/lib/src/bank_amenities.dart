import 'generated/rows.dart';

/// Known dedicated bank nodes. Kept so older rows without `_bank` keys still match.
const List<String> knownBankLocationIds = <String>['LOC-0034', 'LOC-0035'];

/// Pool shared by every bank's "Pick a deposit box" thievery activity.
const String depositBoxPoolId = 'POOL-0047';

/// Whether this location is a bank vault (storage + deposit-box thievery).
///
/// Current banks are listed explicitly; future banks match an `*_bank` internal
/// key or a Display Name that contains the word "Bank".
bool locationLooksLikeBank(LocationRow? location) {
  if (location == null) return false;
  if (knownBankLocationIds.contains(location.locationId)) return true;
  final key = (location.raw['Internal Key'] as String?)?.trim().toLowerCase() ?? '';
  if (key.endsWith('_bank') || key == 'bank') return true;
  final name = (location.raw['Display Name'] as String?) ?? '';
  return RegExp(r'\bbank\b', caseSensitive: false).hasMatch(name);
}

int _activitySerial(String activityId) {
  final match = RegExp(r'^ACT-(\d+)$').firstMatch(activityId);
  if (match == null) return 0;
  return int.tryParse(match.group(1)!) ?? 0;
}

/// Ensures every bank location has a deposit-box thievery activity on [depositBoxPoolId].
///
/// Current Town/Citadel banks already ship with ACT-0059 / ACT-0060. Future bank
/// locations get a cloned activity with a fresh ACT id so content authors only
/// need to add the location.
GameDatabase withBankDepositBoxActivities(GameDatabase db) {
  ActivityRow? template;
  for (final row in db.activities) {
    if (row.poolId == depositBoxPoolId) {
      template = row;
      break;
    }
  }
  if (template == null) return db;

  final covered = <String>{
    for (final row in db.activities)
      if (row.poolId == depositBoxPoolId) row.locationId,
  };

  var nextSerial = 0;
  for (final row in db.activities) {
    final serial = _activitySerial(row.activityId);
    if (serial > nextSerial) nextSerial = serial;
  }

  final extras = <Map<String, Object?>>[];
  for (final location in db.locations) {
    if (!locationLooksLikeBank(location)) continue;
    if (covered.contains(location.locationId)) continue;
    nextSerial += 1;
    final id = 'ACT-${nextSerial.toString().padLeft(4, '0')}';
    final clone = Map<String, Object?>.of(template.raw);
    clone['Activity ID'] = id;
    clone['Internal Key'] = 'pick_deposit_box_${location.locationId.toLowerCase()}';
    clone['Location ID'] = location.locationId;
    extras.add(clone);
  }

  if (extras.isEmpty) return db;

  final next = Map<String, Object?>.of(db.raw);
  next['Activities'] = [...db.activities.map((row) => row.raw), ...extras];
  return GameDatabase(next);
}
