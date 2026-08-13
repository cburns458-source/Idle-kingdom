import 'package:collection/collection.dart';

import '../js_compat.dart';
import '../rng/mulberry32.dart';
import '../save/generated/save_models.dart';
import '../time.dart';

const num critterHourMs = 3600000;

/// One roll per full activity-hour spent at the Critter's location.
const double critterSpawnChance = 1 / 200;

class CritterDef {
  const CritterDef({
    required this.id,
    required this.internalKey,
    required this.displayName,
    required this.locationId,
    required this.description,
  });

  final String id;
  final String internalKey;
  final String displayName;
  final String locationId;
  final String description;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'internalKey': internalKey,
    'displayName': displayName,
    'locationId': locationId,
    'description': description,
  };
}

/// Expandable starter set; new rows go here (or later in data) without schema churn.
const List<CritterDef> critterDefs = <CritterDef>[
  CritterDef(
    id: 'CRT-0001',
    internalKey: 'fly',
    displayName: 'Fly',
    locationId: 'LOC-0001',
    description: 'A buzzing farmyard nuisance.',
  ),
  CritterDef(
    id: 'CRT-0002',
    internalKey: 'rat',
    displayName: 'Rat',
    locationId: 'LOC-0004',
    description: 'A dockside scavenger.',
  ),
  CritterDef(
    id: 'CRT-0003',
    internalKey: 'entling',
    displayName: 'Entling',
    locationId: 'LOC-0018',
    description: 'A tiny forest spirit of bark and leaf.',
  ),
  CritterDef(
    id: 'CRT-0004',
    internalKey: 'mole',
    displayName: 'Mole',
    locationId: 'LOC-0011',
    description: 'A tunnel-dweller from the deep mines.',
  ),
];

CritterDef? critterForLocation(String locationId) {
  return critterDefs.firstWhereOrNull((critter) => critter.locationId == locationId);
}

CritterDef? getCritter(String critterId) {
  return critterDefs.firstWhereOrNull((critter) => critter.id == critterId);
}

num collectionCount(PlayerSave save, String critterId) {
  return save.critterCollections.firstWhereOrNull((row) => row.critterId == critterId)?.count ?? 0;
}

CritterSpawn? activeSpawnAtLocation(PlayerSave save, String locationId) {
  return save.activeCritterSpawns.firstWhereOrNull((spawn) => spawn.locationId == locationId);
}

/// The save after crediting activity time, plus whatever it spawned.
class CritterTimeResult {
  const CritterTimeResult({required this.save, required this.spawned, required this.hoursRolled});

  final PlayerSave save;
  final CritterDef? spawned;
  final num hoursRolled;

  Map<String, Object?> toJson() => <String, Object?>{
    'save': save.toJson(),
    'spawned': spawned?.toJson(),
    'hoursRolled': hoursRolled,
  };
}

/// Credits activity time at a location toward Critter hour-rolls.
///
/// Each full hour rolls once; the remainder is kept for next time. A spawn still
/// waiting to be collected blocks a second one from stacking on top of it.
CritterTimeResult applyActivityTimeTowardCritters(
  PlayerSave save,
  String locationId,
  num elapsedMs,
  num nowMs,
  RandomFn random,
) {
  if (elapsedMs <= 0) {
    return CritterTimeResult(save: save, spawned: null, hoursRolled: 0);
  }
  final critter = critterForLocation(locationId);
  if (critter == null) {
    return CritterTimeResult(save: save, spawned: null, hoursRolled: 0);
  }

  final progress = <String, num>{...save.critterProgressMs};
  final prior = progress[locationId] ?? 0;
  final total = prior + elapsedMs;
  final hoursRolled = (total / critterHourMs).floor();
  progress[locationId] = total % critterHourMs;

  var next = save.copyWith(critterProgressMs: progress);
  if (hoursRolled <= 0) {
    return CritterTimeResult(save: next, spawned: null, hoursRolled: 0);
  }

  if (activeSpawnAtLocation(next, locationId) != null) {
    return CritterTimeResult(save: next, spawned: null, hoursRolled: hoursRolled);
  }

  CritterDef? spawned;
  for (var i = 0; i < hoursRolled; i += 1) {
    if (random() < critterSpawnChance) {
      spawned = critter;
      break;
    }
  }

  if (spawned == null) {
    return CritterTimeResult(save: next, spawned: null, hoursRolled: hoursRolled);
  }

  next = next.copyWith(
    activeCritterSpawns: <CritterSpawn>[
      ...next.activeCritterSpawns.where((row) => row.locationId != locationId),
      CritterSpawn(locationId: locationId, critterId: spawned.id, appearedAt: isoFromMs(nowMs)),
    ],
  );
  return CritterTimeResult(save: next, spawned: spawned, hoursRolled: hoursRolled);
}

/// Either the collected Critter or the reason nothing was collected.
class CritterCollectResult {
  const CritterCollectResult.ok({
    required this.save,
    required this.critter,
    required this.count,
    required this.message,
  }) : reason = null;

  const CritterCollectResult.failed(this.reason)
    : save = null,
      critter = null,
      count = null,
      message = null;

  bool get ok => reason == null;
  final PlayerSave? save;
  final CritterDef? critter;
  final num? count;

  /// What was caught, as the overlay says it.
  final String? message;
  final String? reason;

  Map<String, Object?> toJson() => ok
      ? <String, Object?>{
          'ok': true,
          'save': save!.toJson(),
          'critter': critter!.toJson(),
          'count': count,
          'message': message,
        }
      : <String, Object?>{'ok': false, 'reason': reason};
}

CritterCollectResult collectCritter(PlayerSave save, String locationId) {
  final spawn = activeSpawnAtLocation(save, locationId);
  if (spawn == null) return const CritterCollectResult.failed('No Critter here.');
  final critter = getCritter(spawn.critterId);
  if (critter == null) return const CritterCollectResult.failed('Unknown Critter.');

  final existing = save.critterCollections.firstWhereOrNull((row) => row.critterId == critter.id);
  final count = (existing?.count ?? 0) + 1;
  final collections = existing != null
      ? save.critterCollections
            .map((row) => row.critterId == critter.id ? row.copyWith(count: count) : row)
            .toList()
      : <CritterCollectionEntry>[
          ...save.critterCollections,
          CritterCollectionEntry(critterId: critter.id, count: count),
        ];

  return CritterCollectResult.ok(
    save: save.copyWith(
      critterCollections: collections,
      activeCritterSpawns: save.activeCritterSpawns
          .where((row) => row.locationId != locationId)
          .toList(),
    ),
    critter: critter,
    count: count,
    message: count > 1
        ? 'Collected ${critter.displayName} (×${jsNumberToString(count)}).'
        : 'Collected ${critter.displayName}!',
  );
}

/// Either the forced spawn or the reason it was refused.
class CritterSpawnResult {
  const CritterSpawnResult.ok({required this.save, required this.critter}) : reason = null;

  const CritterSpawnResult.failed(this.reason) : save = null, critter = null;

  bool get ok => reason == null;
  final PlayerSave? save;
  final CritterDef? critter;
  final String? reason;

  Map<String, Object?> toJson() => ok
      ? <String, Object?>{'ok': true, 'save': save!.toJson(), 'critter': critter!.toJson()}
      : <String, Object?>{'ok': false, 'reason': reason};
}

/// Demo and debug hook: force the habitat Critter to appear when none is waiting.
CritterSpawnResult spawnCritterAtLocation(PlayerSave save, String locationId, num nowMs) {
  final critter = critterForLocation(locationId);
  if (critter == null) {
    return const CritterSpawnResult.failed('No Critter is available at this location.');
  }
  if (activeSpawnAtLocation(save, locationId) != null) {
    return const CritterSpawnResult.failed('A Critter is already waiting here.');
  }

  return CritterSpawnResult.ok(
    save: save.copyWith(
      activeCritterSpawns: <CritterSpawn>[
        ...save.activeCritterSpawns.where((row) => row.locationId != locationId),
        CritterSpawn(locationId: locationId, critterId: critter.id, appearedAt: isoFromMs(nowMs)),
      ],
    ),
    critter: critter,
  );
}
