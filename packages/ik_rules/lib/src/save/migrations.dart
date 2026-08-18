import 'dart:math' as math;

import 'package:collection/collection.dart';

import '../js_compat.dart';
import '../time.dart';
import 'generated/save_models.dart';
import 'json_save.dart';
import 'starting_gear.dart';

const String _foodSlotId = 'SLOT-0011';

/// One step of the upgrade chain, keyed by the version it consumes.
class SaveMigration {
  const SaveMigration({required this.fromVersion, required this.toVersion, required this.migrate});

  final int fromVersion;

  final int toVersion;

  /// `nowMs` is only consulted by steps that must invent a missing timestamp.
  final SaveJson Function(SaveJson save, num nowMs) migrate;
}

SaveJson _bumped(SaveJson save, int version) {
  final next = copySave(save);
  next['saveVersion'] = version;
  return next;
}

/// `save.field ?? null`: keep what is there, otherwise store an explicit null.
///
/// Assigning an absent key writes the null the TypeScript spread would, which is
/// what the schema expects — these fields are nullable, not optional.
SaveJson _backfillNulls(SaveJson save, int version, List<String> fields) {
  final next = _bumped(save, version);
  for (final field in fields) {
    next[field] = save[field];
  }
  return next;
}

/// Quantity for a legacy equipped stack: `Math.max(1, Number(quantity) || 1)`.
num _stackQuantity(Object? raw) {
  final coerced = jsNumberOrZero(raw);
  return math.max(1, coerced == 0 ? 1 : coerced);
}

SaveJson _migrateEquipmentSlotsToStacks(SaveJson save) {
  final rawSlots = objectOrEmpty(objectAt(save, 'equipment') ?? <String, Object?>{}, 'slots');
  final nextSlots = <String, Object?>{};
  var inventory = arrayOrEmpty(save, 'inventory');

  for (final entry in rawSlots.entries) {
    final slotId = entry.key;
    final value = entry.value;
    if (value == null) {
      nextSlots[slotId] = null;
      continue;
    }
    final stack = asObject(value);
    if (stack != null && stack.containsKey('itemId')) {
      nextSlots[slotId] = <String, Object?>{
        'itemId': stack['itemId'],
        'quantity': _stackQuantity(stack['quantity']),
      };
      continue;
    }
    if (value is! String) {
      nextSlots[slotId] = null;
      continue;
    }

    // A legacy slot held a bare item ID. Food kept its count in the bag, so the
    // stack moves into the slot rather than being duplicated.
    final itemId = value;
    if (slotId == _foodSlotId) {
      final owned = inventory.firstWhereOrNull(
        (candidate) => candidate is SaveJson && candidate['itemId'] == itemId,
      );
      final quantity = owned is SaveJson ? (owned['quantity'] ?? 1) : 1;
      inventory = inventory
          .where((candidate) => !(candidate is SaveJson && candidate['itemId'] == itemId))
          .toList();
      nextSlots[slotId] = <String, Object?>{'itemId': itemId, 'quantity': quantity};
    } else {
      nextSlots[slotId] = <String, Object?>{'itemId': itemId, 'quantity': 1};
    }
  }

  final next = copySave(save);
  next['inventory'] = inventory;
  next['equipment'] = <String, Object?>{'slots': nextSlots};
  return next;
}

Object? _normalizeFavorite(Object? stack) {
  final entry = asObject(stack);
  if (entry == null) return stack;
  if (entry['favorite'] == true) {
    entry['favorite'] = true;
    return entry;
  }
  entry.remove('favorite');
  return entry;
}

SaveJson _normalizeSettings(SaveJson save, int version) {
  final settings = objectAt(save, 'settings') ?? <String, Object?>{};
  final next = _bumped(save, version);
  next['settings'] = <String, Object?>{
    'soundEnabled': settings['soundEnabled'] ?? true,
    'showActivityRewards': settings['showActivityRewards'] ?? true,
    'hudShowTotalXp': settings['hudShowTotalXp'] ?? false,
  };
  return next;
}

/// Ordered migrations from older save versions up to [saveVersion].
final List<SaveMigration> saveMigrations = <SaveMigration>[
  SaveMigration(
    fromVersion: 1,
    toVersion: 2,
    migrate: (save, nowMs) =>
        _backfillNulls(save, 2, const ['currentActionId', 'actionStartedAt', 'actionDurationMs']),
  ),
  SaveMigration(
    fromVersion: 2,
    toVersion: 3,
    migrate: (save, nowMs) => _backfillNulls(save, 3, const [
      'combatEnemyId',
      'combatEnemyHp',
      'combatRoundStartedAt',
      'deathPauseUntil',
    ]),
  ),
  SaveMigration(
    fromVersion: 3,
    toVersion: 4,
    migrate: (save, nowMs) => _bumped(_migrateEquipmentSlotsToStacks(save), 4),
  ),
  SaveMigration(
    fromVersion: 4,
    toVersion: 5,
    migrate: (save, nowMs) => _bumped(ensureStartingHuntingToolJson(save), 5),
  ),
  SaveMigration(
    fromVersion: 5,
    toVersion: 6,
    migrate: (save, nowMs) => _backfillNulls(save, 6, const ['characterName']),
  ),
  SaveMigration(
    fromVersion: 6,
    toVersion: 7,
    migrate: (save, nowMs) => _backfillNulls(save, 7, const [
      'productionRecipeId',
      'productionQuantityTotal',
      'productionQuantityRemaining',
    ]),
  ),
  SaveMigration(
    fromVersion: 7,
    toVersion: 8,
    migrate: (save, nowMs) {
      final next = _bumped(save, 8);
      next['unlockedNpcIds'] = arrayOrEmpty(save, 'unlockedNpcIds');
      return next;
    },
  ),
  SaveMigration(
    fromVersion: 8,
    toVersion: 9,
    // Anchor absence catch-up to the last save touch so old creates do not grant
    // a free 24h. A save with no touch either cannot be anchored from data, so
    // the caller's clock stands in.
    migrate: (save, nowMs) {
      final next = _bumped(save, 9);
      final anchor = save['unattendedProgressAt'];
      next['unattendedProgressAt'] = anchor is String && anchor.isNotEmpty
          ? anchor
          : (save['updatedAt'] ?? isoFromMs(nowMs));
      return next;
    },
  ),
  SaveMigration(
    fromVersion: 9,
    toVersion: 10,
    migrate: (save, nowMs) => _backfillNulls(save, 10, const ['activityTransition']),
  ),
  SaveMigration(
    fromVersion: 10,
    toVersion: 11,
    migrate: (save, nowMs) => _normalizeSettings(save, 11),
  ),
  SaveMigration(
    fromVersion: 11,
    toVersion: 12,
    migrate: (save, nowMs) => _backfillNulls(save, 12, const ['combatPotionDamageBonusPercent']),
  ),
  SaveMigration(
    fromVersion: 12,
    toVersion: 13,
    // The flat damage bonus becomes one shape of the general potion effect.
    migrate: (save, nowMs) {
      final next = _bumped(save, 13);
      final bonus = save['combatPotionDamageBonusPercent'];
      final existing = asObject(save['activePotionEffect']);
      next['activePotionEffect'] =
          existing ??
          (bonus is num && bonus > 0
              ? <String, Object?>{
                  'scope': 'one_combat_encounter',
                  'itemId': '',
                  'damageBonusPercent': bonus,
                  'enemyMaxHpDamagePercent': null,
                  'relativeDropChanceBonusPercent': null,
                  'baseDurationReductionPercent': null,
                }
              : null);
      next.remove('combatPotionDamageBonusPercent');
      return next;
    },
  ),
  SaveMigration(
    fromVersion: 13,
    toVersion: 14,
    migrate: (save, nowMs) => _normalizeSettings(save, 14),
  ),
  SaveMigration(
    fromVersion: 14,
    toVersion: 15,
    migrate: (save, nowMs) {
      final next = _bumped(save, 15);
      next['unlockedLocationIds'] = arrayOrEmpty(save, 'unlockedLocationIds');
      next['claimedMerchantTipIds'] = arrayOrEmpty(save, 'claimedMerchantTipIds');
      return next;
    },
  ),
  SaveMigration(
    fromVersion: 15,
    toVersion: 16,
    migrate: (save, nowMs) {
      final next = _bumped(save, 16);
      next['critterCollections'] = arrayOrEmpty(save, 'critterCollections');
      next['activeCritterSpawns'] = arrayOrEmpty(save, 'activeCritterSpawns');
      next['critterProgressMs'] = objectOrEmpty(save, 'critterProgressMs');
      return next;
    },
  ),
  SaveMigration(
    fromVersion: 16,
    toVersion: 17,
    migrate: (save, nowMs) {
      final cosmetics = objectAt(save, 'cosmetics') ?? <String, Object?>{};
      final unlocked = arrayOrEmpty(cosmetics, 'unlocked');
      final equipped = objectAt(cosmetics, 'equipped') ?? <String, Object?>{};
      // Every character (new or migrated) starts fully dressed with the default
      // starter outfit unless something else is already equipped.
      equipped[outfitCosmeticSlotId] = equipped[outfitCosmeticSlotId] ?? starterOutfitCosmeticId;
      equipped[petCosmeticSlotId] = equipped[petCosmeticSlotId];

      final appearance = objectAt(save, 'appearance') ?? <String, Object?>{};
      final next = _bumped(save, 17);
      next['cosmetics'] = <String, Object?>{
        'unlocked': unlocked.contains(starterOutfitCosmeticId)
            ? unlocked
            : <Object?>[...unlocked, starterOutfitCosmeticId],
        'equipped': equipped,
      };
      next['appearance'] = <String, Object?>{
        'skinTone': appearance['skinTone'] ?? defaultSkinToneId,
        'hairstyle': appearance['hairstyle'] ?? defaultHairstyleId,
        'hairColor': appearance['hairColor'] ?? defaultHairColorId,
        'expression': appearance['expression'] ?? defaultExpressionId,
        'beard': appearance['beard'] ?? defaultBeardId,
        'genderPresentation': appearance['genderPresentation'] ?? defaultGenderPresentationId,
      };
      next['hasSeenWardrobeIntro'] = save['hasSeenWardrobeIntro'] ?? false;
      return next;
    },
  ),
  SaveMigration(
    fromVersion: 17,
    toVersion: 18,
    migrate: (save, nowMs) {
      final next = _bumped(save, 18);
      next['locationSearchClaims'] = objectOrEmpty(save, 'locationSearchClaims');
      return next;
    },
  ),
  SaveMigration(
    fromVersion: 18,
    toVersion: 19,
    // Existing named characters are forced through a one-time race picker.
    migrate: (save, nowMs) {
      final next = _bumped(save, 19);
      final raceId = save['raceId'];
      next['raceId'] = raceId is String && raceId.isNotEmpty ? raceId : null;
      return next;
    },
  ),
  SaveMigration(
    fromVersion: 19,
    toVersion: 20,
    // Normalize favorite flags; omit false so older stack shapes stay unchanged.
    migrate: (save, nowMs) {
      final next = _bumped(save, 20);
      next['inventory'] = arrayOrEmpty(save, 'inventory').map(_normalizeFavorite).toList();
      final equipment = objectAt(save, 'equipment') ?? <String, Object?>{};
      equipment['slots'] = objectOrEmpty(
        equipment,
        'slots',
      ).map((slotId, stack) => MapEntry(slotId, stack == null ? null : _normalizeFavorite(stack)));
      next['equipment'] = equipment;
      return next;
    },
  ),
  SaveMigration(
    fromVersion: 20,
    toVersion: 21,
    migrate: (save, nowMs) {
      final next = _bumped(save, 21);
      next['unlockedRecipeIds'] = arrayOrEmpty(save, 'unlockedRecipeIds');
      next['quests'] = arrayOrEmpty(save, 'quests').map((entry) {
        final quest = asObject(entry);
        if (quest == null) return entry;
        // An untyped or missing counter map is dropped rather than stored empty.
        if (quest['counters'] is! Map) quest.remove('counters');
        return quest;
      }).toList();
      return next;
    },
  ),
  SaveMigration(
    fromVersion: 21,
    toVersion: 22,
    migrate: (save, nowMs) {
      final next = _bumped(save, 22);
      next['bountyHourKey'] = stringOrNull(save['bountyHourKey']);
      next['bountyProgress'] = objectOrEmpty(save, 'bountyProgress');
      next['bountyClaimedIds'] = arrayOrEmpty(save, 'bountyClaimedIds');
      return next;
    },
  ),
  SaveMigration(
    fromVersion: 22,
    toVersion: 23,
    migrate: (save, nowMs) {
      final next = _bumped(save, 23);
      next['bank'] = arrayOrEmpty(save, 'bank');
      return next;
    },
  ),
  SaveMigration(
    fromVersion: 23,
    toVersion: 24,
    migrate: (save, nowMs) {
      final next = _bumped(save, 24);
      next['rankedPvpDayKey'] = stringOrNull(save['rankedPvpDayKey']);
      next['rankedPvpFightsToday'] = jsNumber(save['rankedPvpFightsToday'] ?? 0);
      next['rankedPvpWins'] = jsNumber(save['rankedPvpWins'] ?? 0);
      next['rankedPvpLosses'] = jsNumber(save['rankedPvpLosses'] ?? 0);
      return next;
    },
  ),
  SaveMigration(
    fromVersion: 24,
    toVersion: 25,
    migrate: (save, nowMs) {
      final next = _bumped(save, 25);
      next['favoriteActivityByLocationId'] = objectOrEmpty(save, 'favoriteActivityByLocationId');
      return next;
    },
  ),
  SaveMigration(
    fromVersion: 25,
    toVersion: 26,
    migrate: (save, nowMs) {
      final next = _bumped(save, 26);
      next['heldActionByActivityId'] = objectOrEmpty(save, 'heldActionByActivityId');
      return next;
    },
  ),
  SaveMigration(
    fromVersion: 26,
    toVersion: 27,
    // Characters that already exist keep the title: nothing recorded their
    // deaths before now, so the kindest reading is that they have not died.
    migrate: (save, nowMs) {
      final next = _bumped(save, 27);
      next['hasEverDied'] = save['hasEverDied'] == true;
      return next;
    },
  ),
];

/// Thrown when a save cannot be brought to the current version.
class SaveMigrationException implements Exception {
  SaveMigrationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Upgrade loose save JSON to [saveVersion], one registered step at a time.
SaveJson migrateSaveJson(SaveJson save, num nowMs) {
  var current = copySave(save);
  final version = jsNumber(current['saveVersion']);
  if (version > saveVersion) {
    throw SaveMigrationException(
      'Save version ${jsNumberToString(version)} is newer than supported version $saveVersion',
    );
  }

  while (jsNumber(current['saveVersion']) < saveVersion) {
    final from = jsNumber(current['saveVersion']);
    final migration = saveMigrations.firstWhereOrNull((entry) => entry.fromVersion == from);
    if (migration == null) {
      throw SaveMigrationException(
        'No save migration registered from version ${jsNumberToString(from)}',
      );
    }
    current = copySave(migration.migrate(current, nowMs));
    current['saveVersion'] = migration.toVersion;
  }

  return current;
}

/// Upgrade a save already known to match the schema.
PlayerSave migrateSave(PlayerSave save, num nowMs) =>
    PlayerSave.fromJson(migrateSaveJson(save.toJson(), nowMs));
