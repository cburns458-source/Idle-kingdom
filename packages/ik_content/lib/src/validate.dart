import 'generated/rows.dart';
import 'indexes.dart';

/// Id column per table, in the same order as `TABLE_ID_FIELDS` in
/// [src/game/data/validate.ts](../../../../src/game/data/validate.ts).
///
/// Order matters: it decides the order validation issues are reported in, which
/// the parity fixtures compare exactly.
const Map<String, String> tableIdFields = <String, String>{
  'Skills': 'Skill ID',
  'EquipmentSlots': 'Slot ID',
  'Items': 'Item ID',
  'Equipment': 'Equipment ID',
  'Statistics': 'Statistic ID',
  'Enchantments': 'Enchantment ID',
  'Maps': 'Map ID',
  'Locations': 'Location ID',
  'TravelConnections': 'Connection ID',
  'Facilities': 'Facility ID',
  'Activities': 'Activity ID',
  'PoolEntries': 'Pool Entry ID',
  'Actions': 'Action ID',
  'Requirements': 'Requirement ID',
  'Enemies': 'Enemy ID',
  'RewardEntries': 'Reward Entry ID',
  'Recipes': 'Recipe ID',
  'Projects': 'Project ID',
  'NPCs': 'NPC ID',
  'Shops': 'Shop ID',
  'Quests': 'Quest ID',
  'QuestDialogue': 'Dialogue ID',
  'Achievements': 'Achievement ID',
  'CosmeticSlots': 'Cosmetic Slot ID',
  'Cosmetics': 'Cosmetic ID',
  'AppearanceOptions': 'Appearance Option ID',
  'LocationSearches': 'Search ID',
  'Races': 'Race ID',
  'RaceBonuses': 'Race Bonus ID',
  'RaceStartingItems': 'Race Starting Item ID',
};

const List<String> _requiredConfigKeys = <String>[
  'primary_activity_slots',
  'save_slots',
  'unattended_cap',
  'currency_item_id',
  'starting_max_hp',
];

/// Tables that expose only Launch rows to the runtime. Tables absent here pass
/// through unfiltered, matching `filterLaunchContent`.
const List<String> launchFilteredTables = <String>[
  'Skills',
  'Items',
  'Statistics',
  'Enchantments',
  'Maps',
  'Locations',
  'TravelConnections',
  'Facilities',
  'Activities',
  'Actions',
  'Enemies',
  'Recipes',
  'Projects',
  'NPCs',
  'Shops',
  'Quests',
  'QuestDialogue',
  'Achievements',
  'CosmeticSlots',
  'Cosmetics',
  'AppearanceOptions',
  'LocationSearches',
  'Races',
];

enum IssueSeverity {
  error('error'),
  warning('warning');

  const IssueSeverity(this.wireName);

  final String wireName;
}

class ValidationIssue {
  const ValidationIssue({required this.severity, required this.message, this.table, this.id});

  final IssueSeverity severity;
  final String message;
  final String? table;
  final String? id;

  bool get isError => severity == IssueSeverity.error;

  /// Omits absent fields rather than writing nulls, matching the TypeScript
  /// objects once they have been through `JSON.stringify`.
  Map<String, Object?> toJson() => <String, Object?>{
    'severity': severity.wireName,
    if (table != null) 'table': table,
    if (id != null) 'id': id,
    'message': message,
  };

  @override
  String toString() => '${severity.wireName} ${table ?? 'root'}: $message';
}

/// Thrown when the root JSON is not shaped like a game database at all.
class DatabaseShapeException implements Exception {
  const DatabaseShapeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when validation finds errors, with the same message the TypeScript
/// loader produces.
class DatabaseValidationException implements Exception {
  const DatabaseValidationException(this.message, this.errors);

  final String message;
  final List<ValidationIssue> errors;

  @override
  String toString() => message;
}

/// Checks every table exists and is a list, then returns the typed view.
GameDatabase assertGameDatabaseShape(Object? raw) {
  if (raw is! Map<String, Object?>) {
    throw const DatabaseShapeException('Database root must be an object');
  }
  for (final table in databaseTables) {
    if (!raw.containsKey(table)) {
      throw DatabaseShapeException('Database missing required table: $table');
    }
    if (raw[table] is! List) {
      throw DatabaseShapeException('Database table must be an array: $table');
    }
  }
  return GameDatabase(raw);
}

List<ValidationIssue> validateDatabase(GameDatabase db) {
  final issues = <ValidationIssue>[];
  final indexes = buildIndexes(db);

  for (final entry in tableIdFields.entries) {
    final table = entry.key;
    final idField = entry.value;
    final seen = <String>{};
    for (final row in db.rowsOf(table)) {
      final id = row[idField];
      if (id is! String || id.isEmpty) {
        issues.add(
          ValidationIssue(severity: IssueSeverity.error, table: table, message: 'Missing $idField'),
        );
        continue;
      }
      if (seen.contains(id)) {
        issues.add(
          ValidationIssue(
            severity: IssueSeverity.error,
            table: table,
            id: id,
            message: 'Duplicate $idField: $id',
          ),
        );
      }
      seen.add(id);
    }
  }

  for (final location in db.locations) {
    final mapId = location.mapId;
    if (mapId != null && mapId.isNotEmpty && indexes.lookupById('Maps', mapId) == null) {
      issues.add(
        ValidationIssue(
          severity: IssueSeverity.error,
          table: 'Locations',
          id: location.locationId,
          message: 'Missing Map ID reference: $mapId',
        ),
      );
    }
    final parentId = location.parentLocationId;
    if (parentId != null && parentId.isNotEmpty && !indexes.locationsById.containsKey(parentId)) {
      issues.add(
        ValidationIssue(
          severity: IssueSeverity.error,
          table: 'Locations',
          id: location.locationId,
          message: 'Missing Parent Location ID reference: $parentId',
        ),
      );
    }
    final landingId = location.raw['Landing Location ID'];
    if (landingId is String &&
        landingId.isNotEmpty &&
        !indexes.locationsById.containsKey(landingId)) {
      issues.add(
        ValidationIssue(
          severity: IssueSeverity.error,
          table: 'Locations',
          id: location.locationId,
          message: 'Missing Landing Location ID reference: $landingId',
        ),
      );
    }
  }

  for (final activity in db.activities) {
    final locationId = activity.raw['Location ID'];
    if (locationId is String && !indexes.locationsById.containsKey(locationId)) {
      issues.add(
        ValidationIssue(
          severity: IssueSeverity.error,
          table: 'Activities',
          id: activity.activityId,
          message: 'Missing Location ID reference: $locationId',
        ),
      );
    }
  }

  for (final entry in db.poolEntries) {
    final actionId = entry.raw['Action ID'];
    if (actionId is String && indexes.lookupById('Actions', actionId) == null) {
      issues.add(
        ValidationIssue(
          severity: IssueSeverity.error,
          table: 'PoolEntries',
          id: '${entry.raw['Pool Entry ID'] ?? ''}',
          message: 'Missing Action ID reference: $actionId',
        ),
      );
    }
  }

  for (final action in db.actions) {
    final skillId = action.raw['Relevant Skill ID'];
    if (skillId is String && !indexes.skillsById.containsKey(skillId)) {
      issues.add(
        ValidationIssue(
          severity: IssueSeverity.error,
          table: 'Actions',
          id: '${action.raw['Action ID'] ?? ''}',
          message: 'Missing Relevant Skill ID reference: $skillId',
        ),
      );
    }
  }

  for (final cosmetic in db.cosmetics) {
    final itemId = cosmetic.raw['Item ID'];
    if (itemId is String && !indexes.itemsById.containsKey(itemId)) {
      issues.add(
        ValidationIssue(
          severity: IssueSeverity.error,
          table: 'Cosmetics',
          id: cosmetic.cosmeticId,
          message: 'Missing Item ID reference: $itemId',
        ),
      );
    }
    final slotId = cosmetic.raw['Cosmetic Slot ID'];
    if (slotId is String && indexes.lookupById('CosmeticSlots', slotId) == null) {
      issues.add(
        ValidationIssue(
          severity: IssueSeverity.error,
          table: 'Cosmetics',
          id: cosmetic.cosmeticId,
          message: 'Missing Cosmetic Slot ID reference: $slotId',
        ),
      );
    }
  }

  for (final search in db.locationSearches) {
    final locationId = search.raw['Location ID'];
    if (locationId is String && !indexes.locationsById.containsKey(locationId)) {
      issues.add(
        ValidationIssue(
          severity: IssueSeverity.error,
          table: 'LocationSearches',
          id: search.searchId,
          message: 'Missing Location ID reference: $locationId',
        ),
      );
    }
    final itemId = search.raw['Reward Item ID'];
    if (itemId is String && !indexes.itemsById.containsKey(itemId)) {
      issues.add(
        ValidationIssue(
          severity: IssueSeverity.error,
          table: 'LocationSearches',
          id: search.searchId,
          message: 'Missing Reward Item ID reference: $itemId',
        ),
      );
    }
  }

  for (final bonus in db.raceBonuses) {
    final raceId = bonus.raw['Race ID'];
    if (raceId is String && indexes.lookupById('Races', raceId) == null) {
      issues.add(
        ValidationIssue(
          severity: IssueSeverity.error,
          table: 'RaceBonuses',
          id: bonus.raceBonusId,
          message: 'Missing Race ID reference: $raceId',
        ),
      );
    }
    final referenceId = bonus.raw['Reference ID'];
    if (bonus.raw['Bonus Type'] == 'skill_drop_chance_percent' &&
        referenceId is String &&
        !indexes.skillsById.containsKey(referenceId)) {
      issues.add(
        ValidationIssue(
          severity: IssueSeverity.error,
          table: 'RaceBonuses',
          id: bonus.raceBonusId,
          message: 'Missing skill Reference ID: $referenceId',
        ),
      );
    }
  }

  for (final starter in db.raceStartingItems) {
    final raceId = starter.raw['Race ID'];
    if (raceId is String && indexes.lookupById('Races', raceId) == null) {
      issues.add(
        ValidationIssue(
          severity: IssueSeverity.error,
          table: 'RaceStartingItems',
          id: starter.raceStartingItemId,
          message: 'Missing Race ID reference: $raceId',
        ),
      );
    }
    final itemId = starter.raw['Item ID'];
    if (itemId is String && !indexes.itemsById.containsKey(itemId)) {
      issues.add(
        ValidationIssue(
          severity: IssueSeverity.error,
          table: 'RaceStartingItems',
          id: starter.raceStartingItemId,
          message: 'Missing Item ID reference: $itemId',
        ),
      );
    }
  }

  for (final race in db.races) {
    final raw = race.raw['Hostility Immunity Location IDs'];
    if (raw is! String || raw.trim().isEmpty) continue;
    final locationIds = raw.split(';').map((part) => part.trim()).where((part) => part.isNotEmpty);
    for (final locationId in locationIds) {
      if (!indexes.locationsById.containsKey(locationId)) {
        issues.add(
          ValidationIssue(
            severity: IssueSeverity.error,
            table: 'Races',
            id: race.raceId,
            message: 'Missing Hostility Immunity Location ID reference: $locationId',
          ),
        );
      }
    }
  }

  for (final key in _requiredConfigKeys) {
    if (!indexes.configByKey.containsKey(key)) {
      issues.add(
        ValidationIssue(
          severity: IssueSeverity.error,
          table: 'Config',
          message: 'Missing required config key: $key',
        ),
      );
    }
  }

  if (!indexes.locationsById.containsKey('LOC-0002')) {
    issues.add(
      const ValidationIssue(
        severity: IssueSeverity.error,
        table: 'Locations',
        id: 'LOC-0002',
        message: 'Starting location The Town (LOC-0002) is missing',
      ),
    );
  }

  return issues;
}

bool _hasLaunchPhase(Map<String, Object?> row) {
  if (!row.containsKey('Release Phase')) return true;
  return row['Release Phase'] == 'Launch';
}

/// Keeps source rows intact and exposes a Launch-only view for the runtime.
GameDatabase filterLaunchContent(GameDatabase db) {
  final next = Map<String, Object?>.of(db.raw);
  for (final table in launchFilteredTables) {
    next[table] = db.rowsOf(table).where(_hasLaunchPhase).toList(growable: false);
  }
  return GameDatabase(next);
}

int countNeedsData(GameDatabase db) {
  var count = 0;
  for (final table in databaseTables) {
    for (final row in db.rowsOf(table)) {
      if (row['Status'] == 'Needs Data') count += 1;
    }
  }
  return count;
}
