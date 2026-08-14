// GENERATED FILE - DO NOT EDIT.
//
// Generated from:
//   src/game/save/types.ts
//
// Regenerate with: npm run gen:dart

import '../../json_support.dart';

const int saveVersion = 25;

const String saveStorageKey = 'idle-kingdoms.demo.save';

const String startingLocationId = 'LOC-0002';

/// Base gold before race kit; race starters grant the real starting gold.
const int startingGold = 0;

/// Level 1 Hunting Net — granted on older save migration only.
const String startingHuntingToolId = 'ITEM-0108';

const String weaponToolSlotId = 'SLOT-0001';

/// New-player starter kit item IDs.
const String startingBakedPotatoId = 'ITEM-0058';

const int startingBakedPotatoQty = 5;

const String startingMinorStrengthPotionId = 'ITEM-0211';

const String startingWoodenAxeId = 'ITEM-0100';

const int characterNameMaxLength = 24;

const String outfitCosmeticSlotId = 'CSLOT-0001';

const String petCosmeticSlotId = 'CSLOT-0002';

const String titleCosmeticSlotId = 'CSLOT-0003';

const String starterOutfitCosmeticId = 'COS-0001';

/// Baseline Appearance Option IDs used until the player (or an old save) picks their own.
const String defaultSkinToneId = 'APR-0001';

const String defaultHairstyleId = 'APR-0004';

const String defaultHairColorId = 'APR-0007';

const String defaultExpressionId = 'APR-0011';

const String defaultBeardId = 'APR-0014';

const String defaultGenderPresentationId = 'APR-0017';

const List<String> appearanceCategories = <String>[
  'skinTone',
  'hairstyle',
  'hairColor',
  'expression',
  'beard',
  'genderPresentation',
];

/// Distinguishes "leave unchanged" from "set to null" in copyWith.
const Object _unset = Object();

class AchievementProgress {
  const AchievementProgress({required this.achievementId, required this.unlocked, this.unlockedAt});

  factory AchievementProgress.fromJson(Map<String, Object?> json) {
    return AchievementProgress(
      achievementId: json['achievementId'] as String,
      unlocked: json['unlocked'] as bool,
      unlockedAt: json['unlockedAt'] as String?,
    );
  }

  final String achievementId;

  final bool unlocked;

  final String? unlockedAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'achievementId': achievementId,
      'unlocked': unlocked,
      'unlockedAt': unlockedAt,
    };
  }

  AchievementProgress copyWith({
    String? achievementId,
    bool? unlocked,
    Object? unlockedAt = _unset,
  }) {
    return AchievementProgress(
      achievementId: achievementId ?? this.achievementId,
      unlocked: unlocked ?? this.unlocked,
      unlockedAt: unlockedAt == _unset ? this.unlockedAt : unlockedAt as String?,
    );
  }
}

/// Data-driven potion effect active for the current eligible action/encounter.
class ActivePotionEffect {
  const ActivePotionEffect({
    required this.scope,
    required this.itemId,
    this.damageBonusPercent,
    this.enemyMaxHpDamagePercent,
    this.relativeDropChanceBonusPercent,
    this.baseDurationReductionPercent,
  });

  factory ActivePotionEffect.fromJson(Map<String, Object?> json) {
    return ActivePotionEffect(
      scope: json['scope'] as String,
      itemId: json['itemId'] as String,
      damageBonusPercent: json['damageBonusPercent'] as num?,
      enemyMaxHpDamagePercent: json['enemyMaxHpDamagePercent'] as num?,
      relativeDropChanceBonusPercent: json['relativeDropChanceBonusPercent'] as num?,
      baseDurationReductionPercent: json['baseDurationReductionPercent'] as num?,
    );
  }

  final String scope;

  final String itemId;

  final num? damageBonusPercent;

  final num? enemyMaxHpDamagePercent;

  final num? relativeDropChanceBonusPercent;

  final num? baseDurationReductionPercent;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'scope': scope,
      'itemId': itemId,
      'damageBonusPercent': damageBonusPercent,
      'enemyMaxHpDamagePercent': enemyMaxHpDamagePercent,
      'relativeDropChanceBonusPercent': relativeDropChanceBonusPercent,
      'baseDurationReductionPercent': baseDurationReductionPercent,
    };
  }

  ActivePotionEffect copyWith({
    String? scope,
    String? itemId,
    Object? damageBonusPercent = _unset,
    Object? enemyMaxHpDamagePercent = _unset,
    Object? relativeDropChanceBonusPercent = _unset,
    Object? baseDurationReductionPercent = _unset,
  }) {
    return ActivePotionEffect(
      scope: scope ?? this.scope,
      itemId: itemId ?? this.itemId,
      damageBonusPercent: damageBonusPercent == _unset
          ? this.damageBonusPercent
          : damageBonusPercent as num?,
      enemyMaxHpDamagePercent: enemyMaxHpDamagePercent == _unset
          ? this.enemyMaxHpDamagePercent
          : enemyMaxHpDamagePercent as num?,
      relativeDropChanceBonusPercent: relativeDropChanceBonusPercent == _unset
          ? this.relativeDropChanceBonusPercent
          : relativeDropChanceBonusPercent as num?,
      baseDurationReductionPercent: baseDurationReductionPercent == _unset
          ? this.baseDurationReductionPercent
          : baseDurationReductionPercent as num?,
    );
  }
}

/// Pending Primary Activity start/stop delay.
class ActivityTransition {
  const ActivityTransition({
    required this.kind,
    required this.activityId,
    this.followUpActivityId,
    this.productionRecipeId,
    this.productionQuantity,
    required this.startedAt,
    required this.durationMs,
  });

  factory ActivityTransition.fromJson(Map<String, Object?> json) {
    return ActivityTransition(
      kind: json['kind'] as String,
      activityId: json['activityId'] as String,
      followUpActivityId: json['followUpActivityId'] as String?,
      productionRecipeId: json['productionRecipeId'] as String?,
      productionQuantity: json['productionQuantity'] as num?,
      startedAt: json['startedAt'] as String,
      durationMs: json['durationMs'] as num,
    );
  }

  final String kind;

  final String activityId;

  /// After a stop delay completes, begin starting this activity.
  final String? followUpActivityId;

  /// Optional Standard Production payload applied when the start delay completes.
  final String? productionRecipeId;

  final num? productionQuantity;

  final String startedAt;

  final num durationMs;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind,
      'activityId': activityId,
      'followUpActivityId': followUpActivityId,
      'productionRecipeId': productionRecipeId,
      'productionQuantity': productionQuantity,
      'startedAt': startedAt,
      'durationMs': durationMs,
    };
  }

  ActivityTransition copyWith({
    String? kind,
    String? activityId,
    Object? followUpActivityId = _unset,
    Object? productionRecipeId = _unset,
    Object? productionQuantity = _unset,
    String? startedAt,
    num? durationMs,
  }) {
    return ActivityTransition(
      kind: kind ?? this.kind,
      activityId: activityId ?? this.activityId,
      followUpActivityId: followUpActivityId == _unset
          ? this.followUpActivityId
          : followUpActivityId as String?,
      productionRecipeId: productionRecipeId == _unset
          ? this.productionRecipeId
          : productionRecipeId as String?,
      productionQuantity: productionQuantity == _unset
          ? this.productionQuantity
          : productionQuantity as num?,
      startedAt: startedAt ?? this.startedAt,
      durationMs: durationMs ?? this.durationMs,
    );
  }
}

class CosmeticsState {
  const CosmeticsState({required this.unlocked, required this.equipped});

  factory CosmeticsState.fromJson(Map<String, Object?> json) {
    return CosmeticsState(
      unlocked: listOf(json['unlocked'], (Object? entry) => entry as String),
      equipped: mapOf(json['equipped'], (Object? value) => value as String?),
    );
  }

  /// Cosmetic IDs ever unlocked — owned forever, not consumable/stackable.
  final List<String> unlocked;

  /// Cosmetic Slot ID -> equipped Cosmetic ID, or null.
  final Map<String, String?> equipped;

  Map<String, Object?> toJson() {
    return <String, Object?>{'unlocked': unlocked, 'equipped': equipped};
  }

  CosmeticsState copyWith({List<String>? unlocked, Map<String, String?>? equipped}) {
    return CosmeticsState(unlocked: unlocked ?? this.unlocked, equipped: equipped ?? this.equipped);
  }
}

/// One unlocked Critter entry in the Log, with how many have been collected.
class CritterCollectionEntry {
  const CritterCollectionEntry({required this.critterId, required this.count});

  factory CritterCollectionEntry.fromJson(Map<String, Object?> json) {
    return CritterCollectionEntry(
      critterId: json['critterId'] as String,
      count: json['count'] as num,
    );
  }

  final String critterId;

  final num count;

  Map<String, Object?> toJson() {
    return <String, Object?>{'critterId': critterId, 'count': count};
  }

  CritterCollectionEntry copyWith({String? critterId, num? count}) {
    return CritterCollectionEntry(
      critterId: critterId ?? this.critterId,
      count: count ?? this.count,
    );
  }
}

/// A Critter waiting to be collected at a location.
class CritterSpawn {
  const CritterSpawn({required this.locationId, required this.critterId, required this.appearedAt});

  factory CritterSpawn.fromJson(Map<String, Object?> json) {
    return CritterSpawn(
      locationId: json['locationId'] as String,
      critterId: json['critterId'] as String,
      appearedAt: json['appearedAt'] as String,
    );
  }

  final String locationId;

  final String critterId;

  final String appearedAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'locationId': locationId,
      'critterId': critterId,
      'appearedAt': appearedAt,
    };
  }

  CritterSpawn copyWith({String? locationId, String? critterId, String? appearedAt}) {
    return CritterSpawn(
      locationId: locationId ?? this.locationId,
      critterId: critterId ?? this.critterId,
      appearedAt: appearedAt ?? this.appearedAt,
    );
  }
}

class EquipmentLoadout {
  const EquipmentLoadout({required this.slots});

  factory EquipmentLoadout.fromJson(Map<String, Object?> json) {
    return EquipmentLoadout(
      slots: mapOf(json['slots'], (Object? value) => mapOrNull(value, EquippedStack.fromJson)),
    );
  }

  /// Slot ID -> equipped stack or null
  final Map<String, EquippedStack?> slots;

  Map<String, Object?> toJson() {
    return <String, Object?>{'slots': slots.map((key, value) => MapEntry(key, value?.toJson()))};
  }

  EquipmentLoadout copyWith({Map<String, EquippedStack?>? slots}) {
    return EquipmentLoadout(slots: slots ?? this.slots);
  }
}

/// Equipped contents for one slot. Food and potions may hold any stack size.
class EquippedStack {
  const EquippedStack({
    required this.itemId,
    required this.quantity,
    this.enchantmentId,
    this.favorite,
  });

  factory EquippedStack.fromJson(Map<String, Object?> json) {
    return EquippedStack(
      itemId: json['itemId'] as String,
      quantity: json['quantity'] as num,
      enchantmentId: json['enchantmentId'] as String?,
      favorite: json['favorite'] as bool?,
    );
  }

  final String itemId;

  final num quantity;

  /// Optional Arcana enchantment applied to this equipped item.
  final String? enchantmentId;

  /// Preserved across equip / unequip with the item.
  final bool? favorite;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'itemId': itemId,
      'quantity': quantity,
      if (enchantmentId != null) 'enchantmentId': enchantmentId,
      if (favorite != null) 'favorite': favorite,
    };
  }

  EquippedStack copyWith({
    String? itemId,
    num? quantity,
    Object? enchantmentId = _unset,
    Object? favorite = _unset,
  }) {
    return EquippedStack(
      itemId: itemId ?? this.itemId,
      quantity: quantity ?? this.quantity,
      enchantmentId: enchantmentId == _unset ? this.enchantmentId : enchantmentId as String?,
      favorite: favorite == _unset ? this.favorite : favorite as bool?,
    );
  }
}

class InventoryStack {
  const InventoryStack({
    required this.itemId,
    required this.quantity,
    this.enchantmentId,
    this.favorite,
  });

  factory InventoryStack.fromJson(Map<String, Object?> json) {
    return InventoryStack(
      itemId: json['itemId'] as String,
      quantity: json['quantity'] as num,
      enchantmentId: json['enchantmentId'] as String?,
      favorite: json['favorite'] as bool?,
    );
  }

  final String itemId;

  final num quantity;

  /// Optional Arcana enchantment applied to this stack.
  final String? enchantmentId;

  /// Favorited stacks sort to the top of the bag and cannot be sold.
  final bool? favorite;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'itemId': itemId,
      'quantity': quantity,
      if (enchantmentId != null) 'enchantmentId': enchantmentId,
      if (favorite != null) 'favorite': favorite,
    };
  }

  InventoryStack copyWith({
    String? itemId,
    num? quantity,
    Object? enchantmentId = _unset,
    Object? favorite = _unset,
  }) {
    return InventoryStack(
      itemId: itemId ?? this.itemId,
      quantity: quantity ?? this.quantity,
      enchantmentId: enchantmentId == _unset ? this.enchantmentId : enchantmentId as String?,
      favorite: favorite == _unset ? this.favorite : favorite as bool?,
    );
  }
}

/// Selected Appearance Option ID per category.
class PlayerAppearance {
  const PlayerAppearance({
    required this.skinTone,
    required this.hairstyle,
    required this.hairColor,
    required this.expression,
    required this.beard,
    required this.genderPresentation,
  });

  factory PlayerAppearance.fromJson(Map<String, Object?> json) {
    return PlayerAppearance(
      skinTone: json['skinTone'] as String,
      hairstyle: json['hairstyle'] as String,
      hairColor: json['hairColor'] as String,
      expression: json['expression'] as String,
      beard: json['beard'] as String,
      genderPresentation: json['genderPresentation'] as String,
    );
  }

  final String skinTone;

  final String hairstyle;

  final String hairColor;

  final String expression;

  final String beard;

  final String genderPresentation;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'skinTone': skinTone,
      'hairstyle': hairstyle,
      'hairColor': hairColor,
      'expression': expression,
      'beard': beard,
      'genderPresentation': genderPresentation,
    };
  }

  PlayerAppearance copyWith({
    String? skinTone,
    String? hairstyle,
    String? hairColor,
    String? expression,
    String? beard,
    String? genderPresentation,
  }) {
    return PlayerAppearance(
      skinTone: skinTone ?? this.skinTone,
      hairstyle: hairstyle ?? this.hairstyle,
      hairColor: hairColor ?? this.hairColor,
      expression: expression ?? this.expression,
      beard: beard ?? this.beard,
      genderPresentation: genderPresentation ?? this.genderPresentation,
    );
  }
}

class PlayerSave {
  const PlayerSave({
    required this.saveVersion,
    required this.createdAt,
    required this.updatedAt,
    this.characterName,
    this.raceId,
    required this.skills,
    required this.inventory,
    required this.bank,
    required this.favoriteActivityByLocationId,
    required this.equipment,
    required this.gold,
    required this.quests,
    required this.achievements,
    required this.statistics,
    required this.unlockedNpcIds,
    required this.unlockedRecipeIds,
    required this.unlockedLocationIds,
    this.bountyHourKey,
    required this.bountyProgress,
    required this.bountyClaimedIds,
    this.rankedPvpDayKey,
    required this.rankedPvpFightsToday,
    required this.rankedPvpWins,
    required this.rankedPvpLosses,
    required this.claimedMerchantTipIds,
    required this.critterCollections,
    required this.activeCritterSpawns,
    required this.critterProgressMs,
    required this.locationSearchClaims,
    required this.cosmetics,
    required this.appearance,
    required this.hasSeenWardrobeIntro,
    required this.settings,
    required this.currentLocationId,
    this.currentActivityId,
    this.activityStartedAt,
    this.currentActionId,
    this.actionStartedAt,
    this.actionDurationMs,
    this.combatEnemyId,
    this.combatEnemyHp,
    this.combatRoundStartedAt,
    this.activePotionEffect,
    this.deathPauseUntil,
    this.productionRecipeId,
    this.productionQuantityTotal,
    this.productionQuantityRemaining,
    this.activityTransition,
    this.unattendedProgressAt,
    required this.currentHp,
    required this.maxHp,
  });

  factory PlayerSave.fromJson(Map<String, Object?> json) {
    return PlayerSave(
      saveVersion: json['saveVersion'] as num,
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String,
      characterName: json['characterName'] as String?,
      raceId: json['raceId'] as String?,
      skills: listOf(json['skills'], (Object? entry) => SkillProgress.fromJson(asJsonMap(entry))),
      inventory: listOf(
        json['inventory'],
        (Object? entry) => InventoryStack.fromJson(asJsonMap(entry)),
      ),
      bank: listOf(json['bank'], (Object? entry) => InventoryStack.fromJson(asJsonMap(entry))),
      favoriteActivityByLocationId: mapOf(
        json['favoriteActivityByLocationId'],
        (Object? value) => value as String,
      ),
      equipment: EquipmentLoadout.fromJson(asJsonMap(json['equipment'])),
      gold: json['gold'] as num,
      quests: listOf(json['quests'], (Object? entry) => QuestProgress.fromJson(asJsonMap(entry))),
      achievements: listOf(
        json['achievements'],
        (Object? entry) => AchievementProgress.fromJson(asJsonMap(entry)),
      ),
      statistics: PlayerStatistics.fromJson(asJsonMap(json['statistics'])),
      unlockedNpcIds: listOf(json['unlockedNpcIds'], (Object? entry) => entry as String),
      unlockedRecipeIds: listOf(json['unlockedRecipeIds'], (Object? entry) => entry as String),
      unlockedLocationIds: listOf(json['unlockedLocationIds'], (Object? entry) => entry as String),
      bountyHourKey: json['bountyHourKey'] as String?,
      bountyProgress: mapOf(json['bountyProgress'], (Object? value) => value as num),
      bountyClaimedIds: listOf(json['bountyClaimedIds'], (Object? entry) => entry as String),
      rankedPvpDayKey: json['rankedPvpDayKey'] as String?,
      rankedPvpFightsToday: json['rankedPvpFightsToday'] as num,
      rankedPvpWins: json['rankedPvpWins'] as num,
      rankedPvpLosses: json['rankedPvpLosses'] as num,
      claimedMerchantTipIds: listOf(
        json['claimedMerchantTipIds'],
        (Object? entry) => entry as String,
      ),
      critterCollections: listOf(
        json['critterCollections'],
        (Object? entry) => CritterCollectionEntry.fromJson(asJsonMap(entry)),
      ),
      activeCritterSpawns: listOf(
        json['activeCritterSpawns'],
        (Object? entry) => CritterSpawn.fromJson(asJsonMap(entry)),
      ),
      critterProgressMs: mapOf(json['critterProgressMs'], (Object? value) => value as num),
      locationSearchClaims: mapOf(json['locationSearchClaims'], (Object? value) => value as String),
      cosmetics: CosmeticsState.fromJson(asJsonMap(json['cosmetics'])),
      appearance: PlayerAppearance.fromJson(asJsonMap(json['appearance'])),
      hasSeenWardrobeIntro: json['hasSeenWardrobeIntro'] as bool,
      settings: PlayerSettings.fromJson(asJsonMap(json['settings'])),
      currentLocationId: json['currentLocationId'] as String,
      currentActivityId: json['currentActivityId'] as String?,
      activityStartedAt: json['activityStartedAt'] as String?,
      currentActionId: json['currentActionId'] as String?,
      actionStartedAt: json['actionStartedAt'] as String?,
      actionDurationMs: json['actionDurationMs'] as num?,
      combatEnemyId: json['combatEnemyId'] as String?,
      combatEnemyHp: json['combatEnemyHp'] as num?,
      combatRoundStartedAt: json['combatRoundStartedAt'] as String?,
      activePotionEffect: mapOrNull(json['activePotionEffect'], ActivePotionEffect.fromJson),
      deathPauseUntil: json['deathPauseUntil'] as String?,
      productionRecipeId: json['productionRecipeId'] as String?,
      productionQuantityTotal: json['productionQuantityTotal'] as num?,
      productionQuantityRemaining: json['productionQuantityRemaining'] as num?,
      activityTransition: mapOrNull(json['activityTransition'], ActivityTransition.fromJson),
      unattendedProgressAt: json['unattendedProgressAt'] as String?,
      currentHp: json['currentHp'] as num,
      maxHp: json['maxHp'] as num,
    );
  }

  final num saveVersion;

  final String createdAt;

  final String updatedAt;

  /// Player-chosen display name; null until first set.
  final String? characterName;

  /// Selected playable Race ID; null until first-run (or one-time) race picker completes.
  final String? raceId;

  final List<SkillProgress> skills;

  final List<InventoryStack> inventory;

  /// Stash at the Town Bank and Citadel Bank. Same slot rules as the bag.
  final List<InventoryStack> bank;

  /// One starred activity per location, auto-started on arrival.
  final Map<String, String> favoriteActivityByLocationId;

  final EquipmentLoadout equipment;

  /// Gold amount; itemized currency uses Config currency_item_id.
  final num gold;

  final List<QuestProgress> quests;

  final List<AchievementProgress> achievements;

  final PlayerStatistics statistics;

  /// NPC IDs that have granted permanent project knowledge (Master Dwarf / Archmage).
  final List<String> unlockedNpcIds;

  /// Recipe IDs unlocked by quests, discoveries, NPCs, or drops (beyond automatic level unlocks).
  final List<String> unlockedRecipeIds;

  /// Location IDs unlocked by quests (e.g. Rose's Apothecary).
  final List<String> unlockedLocationIds;

  /// UTC hour key for the active Citadel bounty board.
  final String? bountyHourKey;

  /// Progress counters for the current bounty hour (bountyId → count).
  final Map<String, num> bountyProgress;

  /// Bounty IDs claimed by this character during the current hour.
  final List<String> bountyClaimedIds;

  /// UTC date key (`YYYY-MM-DD`) for the ranked PvP daily fight cap.
  final String? rankedPvpDayKey;

  /// Ranked arena fights already used during [rankedPvpDayKey].
  final num rankedPvpFightsToday;

  /// Ranked arena wins, which feed the PvP K/D leaderboard.
  final num rankedPvpWins;

  /// Ranked arena losses.
  final num rankedPvpLosses;

  /// Merchant tip rewards already claimed (one-time dialogue grants).
  final List<String> claimedMerchantTipIds;

  /// Critter collection counts (unlocked entries in the Log).
  final List<CritterCollectionEntry> critterCollections;

  /// At most one pending Critter spawn per location until collected.
  final List<CritterSpawn> activeCritterSpawns;

  /// Remainder activity ms toward the next Critter hour-roll, keyed by location.
  final Map<String, num> critterProgressMs;

  /// Location Search ID -> ISO timestamp of the last successful search (for cooldowns).
  final Map<String, String> locationSearchClaims;

  /// Owned/equipped Wardrobe Cosmetics.
  final CosmeticsState cosmetics;

  /// Selected character Appearance options.
  final PlayerAppearance appearance;

  /// Whether the player has ever opened the Wardrobe (gates the intro hint highlight).
  final bool hasSeenWardrobeIntro;

  final PlayerSettings settings;

  final String currentLocationId;

  final String? currentActivityId;

  final String? activityStartedAt;

  final String? currentActionId;

  final String? actionStartedAt;

  final num? actionDurationMs;

  final String? combatEnemyId;

  final num? combatEnemyHp;

  final String? combatRoundStartedAt;

  /// Potion consumed for the current gathering action, craft, or combat encounter.
  final ActivePotionEffect? activePotionEffect;

  final String? deathPauseUntil;

  final String? productionRecipeId;

  final num? productionQuantityTotal;

  final num? productionQuantityRemaining;

  /// Pending start/stop delay for Primary Activities.
  final ActivityTransition? activityTransition;

  final String? unattendedProgressAt;

  final num currentHp;

  final num maxHp;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'saveVersion': saveVersion,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'characterName': characterName,
      'raceId': raceId,
      'skills': skills.map((entry) => entry.toJson()).toList(),
      'inventory': inventory.map((entry) => entry.toJson()).toList(),
      'bank': bank.map((entry) => entry.toJson()).toList(),
      'favoriteActivityByLocationId': favoriteActivityByLocationId,
      'equipment': equipment.toJson(),
      'gold': gold,
      'quests': quests.map((entry) => entry.toJson()).toList(),
      'achievements': achievements.map((entry) => entry.toJson()).toList(),
      'statistics': statistics.toJson(),
      'unlockedNpcIds': unlockedNpcIds,
      'unlockedRecipeIds': unlockedRecipeIds,
      'unlockedLocationIds': unlockedLocationIds,
      'bountyHourKey': bountyHourKey,
      'bountyProgress': bountyProgress,
      'bountyClaimedIds': bountyClaimedIds,
      'rankedPvpDayKey': rankedPvpDayKey,
      'rankedPvpFightsToday': rankedPvpFightsToday,
      'rankedPvpWins': rankedPvpWins,
      'rankedPvpLosses': rankedPvpLosses,
      'claimedMerchantTipIds': claimedMerchantTipIds,
      'critterCollections': critterCollections.map((entry) => entry.toJson()).toList(),
      'activeCritterSpawns': activeCritterSpawns.map((entry) => entry.toJson()).toList(),
      'critterProgressMs': critterProgressMs,
      'locationSearchClaims': locationSearchClaims,
      'cosmetics': cosmetics.toJson(),
      'appearance': appearance.toJson(),
      'hasSeenWardrobeIntro': hasSeenWardrobeIntro,
      'settings': settings.toJson(),
      'currentLocationId': currentLocationId,
      'currentActivityId': currentActivityId,
      'activityStartedAt': activityStartedAt,
      'currentActionId': currentActionId,
      'actionStartedAt': actionStartedAt,
      'actionDurationMs': actionDurationMs,
      'combatEnemyId': combatEnemyId,
      'combatEnemyHp': combatEnemyHp,
      'combatRoundStartedAt': combatRoundStartedAt,
      'activePotionEffect': activePotionEffect?.toJson(),
      'deathPauseUntil': deathPauseUntil,
      'productionRecipeId': productionRecipeId,
      'productionQuantityTotal': productionQuantityTotal,
      'productionQuantityRemaining': productionQuantityRemaining,
      'activityTransition': activityTransition?.toJson(),
      'unattendedProgressAt': unattendedProgressAt,
      'currentHp': currentHp,
      'maxHp': maxHp,
    };
  }

  PlayerSave copyWith({
    num? saveVersion,
    String? createdAt,
    String? updatedAt,
    Object? characterName = _unset,
    Object? raceId = _unset,
    List<SkillProgress>? skills,
    List<InventoryStack>? inventory,
    List<InventoryStack>? bank,
    Map<String, String>? favoriteActivityByLocationId,
    EquipmentLoadout? equipment,
    num? gold,
    List<QuestProgress>? quests,
    List<AchievementProgress>? achievements,
    PlayerStatistics? statistics,
    List<String>? unlockedNpcIds,
    List<String>? unlockedRecipeIds,
    List<String>? unlockedLocationIds,
    Object? bountyHourKey = _unset,
    Map<String, num>? bountyProgress,
    List<String>? bountyClaimedIds,
    Object? rankedPvpDayKey = _unset,
    num? rankedPvpFightsToday,
    num? rankedPvpWins,
    num? rankedPvpLosses,
    List<String>? claimedMerchantTipIds,
    List<CritterCollectionEntry>? critterCollections,
    List<CritterSpawn>? activeCritterSpawns,
    Map<String, num>? critterProgressMs,
    Map<String, String>? locationSearchClaims,
    CosmeticsState? cosmetics,
    PlayerAppearance? appearance,
    bool? hasSeenWardrobeIntro,
    PlayerSettings? settings,
    String? currentLocationId,
    Object? currentActivityId = _unset,
    Object? activityStartedAt = _unset,
    Object? currentActionId = _unset,
    Object? actionStartedAt = _unset,
    Object? actionDurationMs = _unset,
    Object? combatEnemyId = _unset,
    Object? combatEnemyHp = _unset,
    Object? combatRoundStartedAt = _unset,
    Object? activePotionEffect = _unset,
    Object? deathPauseUntil = _unset,
    Object? productionRecipeId = _unset,
    Object? productionQuantityTotal = _unset,
    Object? productionQuantityRemaining = _unset,
    Object? activityTransition = _unset,
    Object? unattendedProgressAt = _unset,
    num? currentHp,
    num? maxHp,
  }) {
    return PlayerSave(
      saveVersion: saveVersion ?? this.saveVersion,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      characterName: characterName == _unset ? this.characterName : characterName as String?,
      raceId: raceId == _unset ? this.raceId : raceId as String?,
      skills: skills ?? this.skills,
      inventory: inventory ?? this.inventory,
      bank: bank ?? this.bank,
      favoriteActivityByLocationId:
          favoriteActivityByLocationId ?? this.favoriteActivityByLocationId,
      equipment: equipment ?? this.equipment,
      gold: gold ?? this.gold,
      quests: quests ?? this.quests,
      achievements: achievements ?? this.achievements,
      statistics: statistics ?? this.statistics,
      unlockedNpcIds: unlockedNpcIds ?? this.unlockedNpcIds,
      unlockedRecipeIds: unlockedRecipeIds ?? this.unlockedRecipeIds,
      unlockedLocationIds: unlockedLocationIds ?? this.unlockedLocationIds,
      bountyHourKey: bountyHourKey == _unset ? this.bountyHourKey : bountyHourKey as String?,
      bountyProgress: bountyProgress ?? this.bountyProgress,
      bountyClaimedIds: bountyClaimedIds ?? this.bountyClaimedIds,
      rankedPvpDayKey: rankedPvpDayKey == _unset
          ? this.rankedPvpDayKey
          : rankedPvpDayKey as String?,
      rankedPvpFightsToday: rankedPvpFightsToday ?? this.rankedPvpFightsToday,
      rankedPvpWins: rankedPvpWins ?? this.rankedPvpWins,
      rankedPvpLosses: rankedPvpLosses ?? this.rankedPvpLosses,
      claimedMerchantTipIds: claimedMerchantTipIds ?? this.claimedMerchantTipIds,
      critterCollections: critterCollections ?? this.critterCollections,
      activeCritterSpawns: activeCritterSpawns ?? this.activeCritterSpawns,
      critterProgressMs: critterProgressMs ?? this.critterProgressMs,
      locationSearchClaims: locationSearchClaims ?? this.locationSearchClaims,
      cosmetics: cosmetics ?? this.cosmetics,
      appearance: appearance ?? this.appearance,
      hasSeenWardrobeIntro: hasSeenWardrobeIntro ?? this.hasSeenWardrobeIntro,
      settings: settings ?? this.settings,
      currentLocationId: currentLocationId ?? this.currentLocationId,
      currentActivityId: currentActivityId == _unset
          ? this.currentActivityId
          : currentActivityId as String?,
      activityStartedAt: activityStartedAt == _unset
          ? this.activityStartedAt
          : activityStartedAt as String?,
      currentActionId: currentActionId == _unset
          ? this.currentActionId
          : currentActionId as String?,
      actionStartedAt: actionStartedAt == _unset
          ? this.actionStartedAt
          : actionStartedAt as String?,
      actionDurationMs: actionDurationMs == _unset
          ? this.actionDurationMs
          : actionDurationMs as num?,
      combatEnemyId: combatEnemyId == _unset ? this.combatEnemyId : combatEnemyId as String?,
      combatEnemyHp: combatEnemyHp == _unset ? this.combatEnemyHp : combatEnemyHp as num?,
      combatRoundStartedAt: combatRoundStartedAt == _unset
          ? this.combatRoundStartedAt
          : combatRoundStartedAt as String?,
      activePotionEffect: activePotionEffect == _unset
          ? this.activePotionEffect
          : activePotionEffect as ActivePotionEffect?,
      deathPauseUntil: deathPauseUntil == _unset
          ? this.deathPauseUntil
          : deathPauseUntil as String?,
      productionRecipeId: productionRecipeId == _unset
          ? this.productionRecipeId
          : productionRecipeId as String?,
      productionQuantityTotal: productionQuantityTotal == _unset
          ? this.productionQuantityTotal
          : productionQuantityTotal as num?,
      productionQuantityRemaining: productionQuantityRemaining == _unset
          ? this.productionQuantityRemaining
          : productionQuantityRemaining as num?,
      activityTransition: activityTransition == _unset
          ? this.activityTransition
          : activityTransition as ActivityTransition?,
      unattendedProgressAt: unattendedProgressAt == _unset
          ? this.unattendedProgressAt
          : unattendedProgressAt as String?,
      currentHp: currentHp ?? this.currentHp,
      maxHp: maxHp ?? this.maxHp,
    );
  }
}

class PlayerSettings {
  const PlayerSettings({
    required this.soundEnabled,
    required this.showActivityRewards,
    required this.hudShowTotalXp,
  });

  factory PlayerSettings.fromJson(Map<String, Object?> json) {
    return PlayerSettings(
      soundEnabled: json['soundEnabled'] as bool,
      showActivityRewards: json['showActivityRewards'] as bool,
      hudShowTotalXp: json['hudShowTotalXp'] as bool,
    );
  }

  /// Reserved for later Settings/Menu work.
  final bool soundEnabled;

  /// When false, the on-location activity reward summary is hidden.
  final bool showActivityRewards;

  /// When true, HUD identity line shows total XP instead of total level.
  final bool hudShowTotalXp;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'soundEnabled': soundEnabled,
      'showActivityRewards': showActivityRewards,
      'hudShowTotalXp': hudShowTotalXp,
    };
  }

  PlayerSettings copyWith({bool? soundEnabled, bool? showActivityRewards, bool? hudShowTotalXp}) {
    return PlayerSettings(
      soundEnabled: soundEnabled ?? this.soundEnabled,
      showActivityRewards: showActivityRewards ?? this.showActivityRewards,
      hudShowTotalXp: hudShowTotalXp ?? this.hudShowTotalXp,
    );
  }
}

class PlayerStatistics {
  const PlayerStatistics({required this.values});

  factory PlayerStatistics.fromJson(Map<String, Object?> json) {
    return PlayerStatistics(values: mapOf(json['values'], (Object? value) => value as num));
  }

  final Map<String, num> values;

  Map<String, Object?> toJson() {
    return <String, Object?>{'values': values};
  }

  PlayerStatistics copyWith({Map<String, num>? values}) {
    return PlayerStatistics(values: values ?? this.values);
  }
}

class QuestProgress {
  const QuestProgress({
    required this.questId,
    required this.status,
    required this.progress,
    this.counters,
  });

  factory QuestProgress.fromJson(Map<String, Object?> json) {
    return QuestProgress(
      questId: json['questId'] as String,
      status: json['status'] as String,
      progress: json['progress'] as num,
      counters: mapOrNullOf(json['counters'], (Object? value) => value as num),
    );
  }

  final String questId;

  final String status;

  final num progress;

  /// Typed counters for defeat/process/learn objectives (key → count).
  final Map<String, num>? counters;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'questId': questId,
      'status': status,
      'progress': progress,
      if (counters != null) 'counters': counters,
    };
  }

  QuestProgress copyWith({
    String? questId,
    String? status,
    num? progress,
    Object? counters = _unset,
  }) {
    return QuestProgress(
      questId: questId ?? this.questId,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      counters: counters == _unset ? this.counters : counters as Map<String, num>?,
    );
  }
}

class SkillProgress {
  const SkillProgress({required this.skillId, required this.level, required this.xp});

  factory SkillProgress.fromJson(Map<String, Object?> json) {
    return SkillProgress(
      skillId: json['skillId'] as String,
      level: json['level'] as num,
      xp: json['xp'] as num,
    );
  }

  final String skillId;

  final num level;

  final num xp;

  Map<String, Object?> toJson() {
    return <String, Object?>{'skillId': skillId, 'level': level, 'xp': xp};
  }

  SkillProgress copyWith({String? skillId, num? level, num? xp}) {
    return SkillProgress(
      skillId: skillId ?? this.skillId,
      level: level ?? this.level,
      xp: xp ?? this.xp,
    );
  }
}
