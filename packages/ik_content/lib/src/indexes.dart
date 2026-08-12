import 'db_row.dart';
import 'generated/rows.dart';
import 'validate.dart';

/// Lookup tables built once per loaded database.
///
/// Mirrors `DatabaseIndexes` in [src/game/data/types.ts](../../../../src/game/data/types.ts).
/// Insertion order is preserved, and a later duplicate id overwrites an earlier
/// one exactly as `new Map(...)` does in TypeScript.
class DatabaseIndexes {
  DatabaseIndexes({
    required this.byTableId,
    required this.configByKey,
    required this.skillsById,
    required this.locationsById,
    required this.itemsById,
    required this.mapsById,
    required this.activitiesById,
    required this.actionsById,
    required this.facilitiesByLocationId,
    required this.activitiesByLocationId,
    required this.npcsByLocationId,
    required this.shopsByLocationId,
    required this.poolEntriesByPoolId,
    required this.rewardEntriesByTableId,
    required this.locationSearchesByLocationId,
  });

  final Map<String, Map<String, Map<String, Object?>>> byTableId;
  final Map<String, ConfigRow> configByKey;
  final Map<String, SkillRow> skillsById;
  final Map<String, LocationRow> locationsById;
  final Map<String, ItemRow> itemsById;
  final Map<String, MapRow> mapsById;
  final Map<String, ActivityRow> activitiesById;
  final Map<String, ActionRow> actionsById;
  final Map<String, List<FacilityRow>> facilitiesByLocationId;
  final Map<String, List<ActivityRow>> activitiesByLocationId;
  final Map<String, List<NpcRow>> npcsByLocationId;
  final Map<String, List<ShopRow>> shopsByLocationId;
  final Map<String, List<PoolEntryRow>> poolEntriesByPoolId;
  final Map<String, List<RewardEntryRow>> rewardEntriesByTableId;
  final Map<String, List<LocationSearchRow>> locationSearchesByLocationId;

  Map<String, Object?>? lookupById(String table, String id) => byTableId[table]?[id];
}

/// Key for an index entry, tolerating a malformed row.
///
/// `new Map(rows.map(...))` in TypeScript happily keys on a missing column, and
/// [validateDatabase] builds indexes before it reports problems, so a row with no
/// id must not crash the very code that is supposed to complain about it. Rows
/// with a missing column collapse onto one entry, as they do in JavaScript.
String _keyOf(DbRow row, String column) {
  final value = row.raw[column];
  return value is String ? value : '$value';
}

Map<String, T> _byId<T extends DbRow>(List<T> rows, String idColumn) {
  final map = <String, T>{};
  for (final row in rows) {
    map[_keyOf(row, idColumn)] = row;
  }
  return map;
}

Map<String, List<T>> _groupBy<T extends DbRow>(List<T> rows, String column) {
  final map = <String, List<T>>{};
  for (final row in rows) {
    map.putIfAbsent(_keyOf(row, column), () => <T>[]).add(row);
  }
  return map;
}

DatabaseIndexes buildIndexes(GameDatabase db) {
  final byTableId = <String, Map<String, Map<String, Object?>>>{};
  for (final entry in tableIdFields.entries) {
    final map = <String, Map<String, Object?>>{};
    for (final row in db.rowsOf(entry.key)) {
      final id = row[entry.value];
      if (id is String && id.isNotEmpty) map[id] = row;
    }
    byTableId[entry.key] = map;
  }

  return DatabaseIndexes(
    byTableId: byTableId,
    configByKey: _byId(db.config, 'Key'),
    skillsById: _byId(db.skills, 'Skill ID'),
    locationsById: _byId(db.locations, 'Location ID'),
    itemsById: _byId(db.items, 'Item ID'),
    mapsById: _byId(db.maps, 'Map ID'),
    activitiesById: _byId(db.activities, 'Activity ID'),
    actionsById: _byId(db.actions, 'Action ID'),
    facilitiesByLocationId: _groupBy(db.facilities, 'Location ID'),
    activitiesByLocationId: _groupBy(db.activities, 'Location ID'),
    npcsByLocationId: _groupBy(db.npcs, 'Location ID'),
    shopsByLocationId: _groupBy(db.shops, 'Location ID'),
    poolEntriesByPoolId: _groupBy(db.poolEntries, 'Pool ID'),
    rewardEntriesByTableId: _groupBy(db.rewardEntries, 'Reward Table ID'),
    locationSearchesByLocationId: _groupBy(db.locationSearches, 'Location ID'),
  );
}
