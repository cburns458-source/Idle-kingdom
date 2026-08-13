import 'package:ik_content/ik_content.dart';

import '../config.dart';
import '../time.dart';
import 'generated/save_models.dart';
import 'json_save.dart';
import 'migrations.dart';

/// Thrown when stored bytes cannot be read as a save.
class SaveParseException implements Exception {
  SaveParseException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A fresh character at the starting location, with launch skills at level 1.
///
/// Race-specific starter kits are granted when the player picks a race, so the
/// bag starts empty and gold starts at the pre-race baseline.
PlayerSave createNewSave(GameDatabase db, num nowMs) {
  final maxHp = configNumber(db, 'starting_max_hp', 1000);
  final timestamp = isoFromMs(nowMs);

  final skills = db.skills
      .where((skill) => skill.raw['Release Phase'] == 'Launch')
      .map((skill) => SkillProgress(skillId: skill.raw['Skill ID']! as String, level: 1, xp: 0))
      .toList();

  final slots = <String, EquippedStack?>{
    for (final slot in db.equipmentSlots) slot.raw['Slot ID']! as String: null,
  };

  return PlayerSave(
    saveVersion: saveVersion,
    createdAt: timestamp,
    updatedAt: timestamp,
    characterName: null,
    raceId: null,
    skills: skills,
    inventory: const <InventoryStack>[],
    bank: const <InventoryStack>[],
    equipment: EquipmentLoadout(slots: slots),
    gold: startingGold,
    quests: const <QuestProgress>[],
    achievements: const <AchievementProgress>[],
    statistics: const PlayerStatistics(values: <String, num>{}),
    unlockedNpcIds: const <String>[],
    unlockedRecipeIds: const <String>[],
    unlockedLocationIds: const <String>[],
    bountyHourKey: null,
    bountyProgress: const <String, num>{},
    bountyClaimedIds: const <String>[],
    claimedMerchantTipIds: const <String>[],
    critterCollections: const <CritterCollectionEntry>[],
    activeCritterSpawns: const <CritterSpawn>[],
    critterProgressMs: const <String, num>{},
    locationSearchClaims: const <String, String>{},
    cosmetics: const CosmeticsState(
      unlocked: <String>[starterOutfitCosmeticId],
      equipped: <String, String?>{
        outfitCosmeticSlotId: starterOutfitCosmeticId,
        petCosmeticSlotId: null,
      },
    ),
    appearance: const PlayerAppearance(
      skinTone: defaultSkinToneId,
      hairstyle: defaultHairstyleId,
      hairColor: defaultHairColorId,
      expression: defaultExpressionId,
      beard: defaultBeardId,
      genderPresentation: defaultGenderPresentationId,
    ),
    hasSeenWardrobeIntro: false,
    settings: const PlayerSettings(
      soundEnabled: true,
      showActivityRewards: true,
      hudShowTotalXp: false,
    ),
    currentLocationId: startingLocationId,
    currentActivityId: null,
    activityStartedAt: null,
    currentActionId: null,
    actionStartedAt: null,
    actionDurationMs: null,
    combatEnemyId: null,
    combatEnemyHp: null,
    combatRoundStartedAt: null,
    activePotionEffect: null,
    deathPauseUntil: null,
    productionRecipeId: null,
    productionQuantityTotal: null,
    productionQuantityRemaining: null,
    activityTransition: null,
    unattendedProgressAt: timestamp,
    currentHp: maxHp,
    maxHp: maxHp,
  );
}

/// Validate the few fields a save cannot be read without, then migrate it.
PlayerSave parseSave(Object? raw, num nowMs) {
  final json = asObject(raw);
  if (json == null) {
    throw SaveParseException('Save data must be an object');
  }
  if (json['saveVersion'] is! num) {
    throw SaveParseException('Save missing saveVersion');
  }
  if (json['currentLocationId'] is! String) {
    throw SaveParseException('Save missing currentLocationId');
  }
  // Every save ever written stamped both, and the model below requires them, so
  // a save without them is corrupt rather than merely old.
  if (json['createdAt'] is! String || json['updatedAt'] is! String) {
    throw SaveParseException('Save missing timestamps');
  }
  if (json['skills'] is! List || json['inventory'] is! List) {
    throw SaveParseException('Save missing skills or inventory arrays');
  }
  if (json['gold'] is! num) {
    throw SaveParseException('Save missing gold');
  }

  return PlayerSave.fromJson(migrateSaveJson(json, nowMs));
}

/// The pure half of a save write: stamp the touch time.
PlayerSave touchSave(PlayerSave save, num nowMs) => save.copyWith(updatedAt: isoFromMs(nowMs));
