// GENERATED FILE - DO NOT EDIT.
//
// Generated from:
//   src/game/data/types.ts
//   src/game/data/enemyTypes.ts
//   src/game/data/projectTypes.ts
//   src/game/data/recipeTypes.ts
//
// Regenerate with: npm run gen:dart

import '../db_row.dart';

class ActionRow extends DbRow {
  const ActionRow(super.raw);

  String get actionId => stringValue('Action ID');

  String get internalKey => stringValue('Internal Key');

  String get displayName => stringValue('Display Name');

  String get category => stringValue('Category');

  String get relevantSkillId => stringValue('Relevant Skill ID');

  String? get targetType => stringOrNull('Target Type');

  String? get targetId => stringOrNull('Target ID');

  num? get proficiencyLevel => numberOrNull('Proficiency Level');

  num? get baseDurationSeconds => numberOrNull('Base Duration Seconds');

  num? get xpReward => numberOrNull('XP Reward');

  num? get guaranteedGold => numberOrNull('Guaranteed Gold');

  num? get dropChance => numberOrNull('Drop Chance');

  String? get rewardTableId => stringOrNull('Reward Table ID');

  num? get secondaryDropChance => numberOrNull('Secondary Drop Chance');

  String? get secondaryRewardTableId => stringOrNull('Secondary Reward Table ID');

  String get status => stringValue('Status');

  String get releasePhase => stringValue('Release Phase');

  String? get notes => stringOrNull('Notes');
}

class ActivityRow extends DbRow {
  const ActivityRow(super.raw);

  String get activityId => stringValue('Activity ID');

  String get internalKey => stringValue('Internal Key');

  String? get contextualName => stringOrNull('Contextual Name');

  String get locationId => stringValue('Location ID');

  String? get poolId => stringOrNull('Pool ID');

  String? get poolInternalKey => stringOrNull('Pool Internal Key');

  String? get description => stringOrNull('Description');

  num? get dangerWarningCombatLevel => numberOrNull('Danger Warning Combat Level');

  String get status => stringValue('Status');

  String get releasePhase => stringValue('Release Phase');

  String? get notes => stringOrNull('Notes');
}

class AppearanceOptionRow extends DbRow {
  const AppearanceOptionRow(super.raw);

  String get appearanceOptionId => stringValue('Appearance Option ID');

  String get category => stringValue('Category');

  String get displayName => stringValue('Display Name');

  /// Hex swatch color for swatch-style categories (skin tone, hair color); null otherwise.
  String? get swatchColor => stringOrNull('Swatch Color');

  num? get sortOrder => numberOrNull('Sort Order');

  String get status => stringValue('Status');

  String get releasePhase => stringValue('Release Phase');

  String? get notes => stringOrNull('Notes');
}

class ConfigRow extends DbRow {
  const ConfigRow(super.raw);

  String get key => stringValue('Key');

  Object? get value => anyOrNull('Value');

  String? get unit => stringOrNull('Unit');

  String? get notes => stringOrNull('Notes');
}

class CosmeticRow extends DbRow {
  const CosmeticRow(super.raw);

  String get cosmeticId => stringValue('Cosmetic ID');

  String get itemId => stringValue('Item ID');

  String get cosmeticSlotId => stringValue('Cosmetic Slot ID');

  /// Semicolon-separated: crafting; unlock; shop_gold; shop_real_money; starter.
  String? get acquisitionTags => stringOrNull('Acquisition Tags');

  String get status => stringValue('Status');

  String get releasePhase => stringValue('Release Phase');

  String? get notes => stringOrNull('Notes');
}

class CosmeticSlotRow extends DbRow {
  const CosmeticSlotRow(super.raw);

  String get cosmeticSlotId => stringValue('Cosmetic Slot ID');

  String get internalKey => stringValue('Internal Key');

  String get displayName => stringValue('Display Name');

  String? get slotGroup => stringOrNull('Slot Group');

  String get status => stringValue('Status');

  String get releasePhase => stringValue('Release Phase');

  String? get notes => stringOrNull('Notes');
}

class EnchantmentRow extends DbRow {
  const EnchantmentRow(super.raw);

  String get enchantmentId => stringValue('Enchantment ID');

  String get internalKey => stringValue('Internal Key');

  String get displayName => stringValue('Display Name');

  String? get validTarget => stringOrNull('Valid Target');

  String? get effect => stringOrNull('Effect');

  String? get requiredMaterials => stringOrNull('Required Materials');

  String get status => stringValue('Status');

  String get releasePhase => stringValue('Release Phase');

  String? get notes => stringOrNull('Notes');
}

class EnemyRow extends DbRow {
  const EnemyRow(super.raw);

  String get enemyId => stringValue('Enemy ID');

  String get internalKey => stringValue('Internal Key');

  String get displayName => stringValue('Display Name');

  String? get locationId => stringOrNull('Location ID');

  num? get combatLevel => numberOrNull('Combat Level');

  num get maximumHp => numberValue('Maximum HP');

  num get minDamage => numberValue('Min Damage');

  num get maxDamage => numberValue('Max Damage');

  num? get combatXp => numberOrNull('Combat XP');

  num? get minimumGold => numberOrNull('Minimum Gold');

  num? get maximumGold => numberOrNull('Maximum Gold');

  num? get dropChance => numberOrNull('Drop Chance');

  String? get rewardTableId => stringOrNull('Reward Table ID');

  String? get spriteAssetKey => stringOrNull('Sprite Asset Key');

  String get status => stringValue('Status');

  String get releasePhase => stringValue('Release Phase');

  String? get notes => stringOrNull('Notes');
}

class EquipmentRow extends DbRow {
  const EquipmentRow(super.raw);

  String get equipmentId => stringValue('Equipment ID');

  String get itemId => stringValue('Item ID');

  String? get slotId => stringOrNull('Slot ID');

  String? get requiredSkillId => stringOrNull('Required Skill ID');

  num? get requiredLevel => numberOrNull('Required Level');

  String? get secondaryRequiredSkillId => stringOrNull('Secondary Required Skill ID');

  num? get secondaryRequiredLevel => numberOrNull('Secondary Required Level');

  num? get minDamage => numberOrNull('Min Damage');

  num? get maxDamage => numberOrNull('Max Damage');

  num? get damageReduction => numberOrNull('Damage Reduction');

  num? get hpBonus => numberOrNull('HP Bonus');

  num? get healingAmount => numberOrNull('Healing Amount');

  num? get actionTimeReductionPercent => numberOrNull('Action Time Reduction %');

  String? get capabilitiesEffects => stringOrNull('Capabilities / Effects');

  String get status => stringValue('Status');

  String? get notes => stringOrNull('Notes');
}

class EquipmentSlotRow extends DbRow {
  const EquipmentSlotRow(super.raw);

  String get slotId => stringValue('Slot ID');

  String get internalKey => stringValue('Internal Key');

  String get displayName => stringValue('Display Name');

  String? get slotGroup => stringOrNull('Slot Group');

  String get status => stringValue('Status');

  String? get notes => stringOrNull('Notes');
}

class FacilityRow extends DbRow {
  const FacilityRow(super.raw);

  String get facilityId => stringValue('Facility ID');

  String get internalKey => stringValue('Internal Key');

  String get displayName => stringValue('Display Name');

  String? get facilityType => stringOrNull('Facility Type');

  String get locationId => stringValue('Location ID');

  String? get skillId => stringOrNull('Skill ID');

  String get status => stringValue('Status');

  String get releasePhase => stringValue('Release Phase');

  String? get description => stringOrNull('Description');

  String? get notes => stringOrNull('Notes');
}

class ItemRow extends DbRow {
  const ItemRow(super.raw);

  String get itemId => stringValue('Item ID');

  String get internalKey => stringValue('Internal Key');

  String get displayName => stringValue('Display Name');

  String? get category => stringOrNull('Category');

  String? get subtype => stringOrNull('Subtype');

  String get status => stringValue('Status');

  String get releasePhase => stringValue('Release Phase');

  String? get associatedSkillId => stringOrNull('Associated Skill ID');

  String? get equipmentSlotId => stringOrNull('Equipment Slot ID');

  num? get baseSellValue => numberOrNull('Base Sell Value');

  String? get iconAssetKey => stringOrNull('Icon Asset Key');

  String? get description => stringOrNull('Description');

  String? get functionalSourceTags => stringOrNull('Functional / Source Tags');

  String? get notes => stringOrNull('Notes');
}

class LocationRow extends DbRow {
  const LocationRow(super.raw);

  String get locationId => stringValue('Location ID');

  String get internalKey => stringValue('Internal Key');

  String get displayName => stringValue('Display Name');

  String? get mapId => stringOrNull('Map ID');

  String? get locationType => stringOrNull('Location Type');

  String? get parentLocationId => stringOrNull('Parent Location ID');

  String? get nodeId => stringOrNull('Node ID');

  String get status => stringValue('Status');

  String get releasePhase => stringValue('Release Phase');

  String? get description => stringOrNull('Description');

  String? get dangerHostility => stringOrNull('Danger / Hostility');

  String? get backgroundAssetKey => stringOrNull('Background Asset Key');

  /// Label used when this location is the gateway node on a child sub-map.
  String? get mapNodeName => stringOrNull('Map Node Name');

  /// Semicolon-separated Map IDs that must not show this location.
  String? get hiddenOnMapIDs => stringOrNull('Hidden On Map IDs');

  String? get notes => stringOrNull('Notes');
}

/// A one-click "search this spot" interaction at a Location, on a cooldown (e.g. once per day).
class LocationSearchRow extends DbRow {
  const LocationSearchRow(super.raw);

  String get searchId => stringValue('Search ID');

  String get internalKey => stringValue('Internal Key');

  String get locationId => stringValue('Location ID');

  String get displayName => stringValue('Display Name');

  String get buttonLabel => stringValue('Button Label');

  String get rewardItemId => stringValue('Reward Item ID');

  num get rewardQuantity => numberValue('Reward Quantity');

  num get cooldownHours => numberValue('Cooldown Hours');

  String get status => stringValue('Status');

  String get releasePhase => stringValue('Release Phase');

  String? get notes => stringOrNull('Notes');
}

class MapRow extends DbRow {
  const MapRow(super.raw);

  String get mapId => stringValue('Map ID');

  String get internalKey => stringValue('Internal Key');

  String get displayName => stringValue('Display Name');

  String? get mapType => stringOrNull('Map Type');

  String? get assetKey => stringOrNull('Asset Key');

  String get status => stringValue('Status');

  String get releasePhase => stringValue('Release Phase');

  String? get description => stringOrNull('Description');
}

class NpcRow extends DbRow {
  const NpcRow(super.raw);

  String get npcId => stringValue('NPC ID');

  String get internalKey => stringValue('Internal Key');

  String get displayName => stringValue('Display Name');

  String get locationId => stringValue('Location ID');

  String? get role => stringOrNull('Role');

  String get status => stringValue('Status');

  String get releasePhase => stringValue('Release Phase');

  String? get description => stringOrNull('Description');

  String? get notes => stringOrNull('Notes');
}

class PoolEntryRow extends DbRow {
  const PoolEntryRow(super.raw);

  String get poolEntryId => stringValue('Pool Entry ID');

  String get poolId => stringValue('Pool ID');

  String get actionId => stringValue('Action ID');

  num? get weight => numberOrNull('Weight');

  String get status => stringValue('Status');

  String? get notes => stringOrNull('Notes');
}

class ProjectRow extends DbRow {
  const ProjectRow(super.raw);

  String get projectId => stringValue('Project ID');

  String get internalKey => stringValue('Internal Key');

  String get displayName => stringValue('Display Name');

  String get skillId => stringValue('Skill ID');

  String get outputItemTargetId => stringValue('Output Item / Target ID');

  num get outputQuantity => numberValue('Output Quantity');

  String get facilityId => stringValue('Facility ID');

  String? get recipeId => stringOrNull('Recipe ID');

  num get xpReward => numberValue('XP Reward');

  num get goldCost => numberValue('Gold Cost');

  String get instant => stringValue('Instant');

  String get status => stringValue('Status');

  String get releasePhase => stringValue('Release Phase');

  String? get notes => stringOrNull('Notes');

  String? get input1ItemId => stringOrNull('Input 1 Item ID');

  num? get input1Quantity => numberOrNull('Input 1 Quantity');

  String? get input2ItemId => stringOrNull('Input 2 Item ID');

  num? get input2Quantity => numberOrNull('Input 2 Quantity');

  String? get input3ItemId => stringOrNull('Input 3 Item ID');

  num? get input3Quantity => numberOrNull('Input 3 Quantity');

  String? get input4ItemId => stringOrNull('Input 4 Item ID');

  num? get input4Quantity => numberOrNull('Input 4 Quantity');

  String? get requiredSkill1Id => stringOrNull('Required Skill 1 ID');

  num? get requiredSkill1Level => numberOrNull('Required Skill 1 Level');

  String? get requiredSkill2Id => stringOrNull('Required Skill 2 ID');

  num? get requiredSkill2Level => numberOrNull('Required Skill 2 Level');

  String? get requiredSkill3Id => stringOrNull('Required Skill 3 ID');

  num? get requiredSkill3Level => numberOrNull('Required Skill 3 Level');
}

class QuestDialogueRow extends DbRow {
  const QuestDialogueRow(super.raw);

  String get dialogueId => stringValue('Dialogue ID');

  String get questId => stringValue('Quest ID');

  String get npcId => stringValue('NPC ID');

  String get line => stringValue('Line');

  String get status => stringValue('Status');

  String get releasePhase => stringValue('Release Phase');

  String? get notes => stringOrNull('Notes');
}

class RaceBonusRow extends DbRow {
  const RaceBonusRow(super.raw);

  String get raceBonusId => stringValue('Race Bonus ID');

  String get raceId => stringValue('Race ID');

  String get bonusType => stringValue('Bonus Type');

  /// Skill ID for skill_xp_percent; null for global bonuses.
  String? get referenceId => stringOrNull('Reference ID');

  num get bonusValue => numberValue('Bonus Value');

  String get status => stringValue('Status');

  String? get notes => stringOrNull('Notes');
}

class RaceRow extends DbRow {
  const RaceRow(super.raw);

  String get raceId => stringValue('Race ID');

  String get internalKey => stringValue('Internal Key');

  String get displayName => stringValue('Display Name');

  String? get description => stringOrNull('Description');

  num? get sortOrder => numberOrNull('Sort Order');

  String? get portraitAssetKey => stringOrNull('Portrait Asset Key');

  /// Semicolon-separated Location IDs where forced hostility is skipped for this race.
  String? get hostilityImmunityLocationIDs => stringOrNull('Hostility Immunity Location IDs');

  String get status => stringValue('Status');

  String get releasePhase => stringValue('Release Phase');

  String? get notes => stringOrNull('Notes');
}

class RaceStartingItemRow extends DbRow {
  const RaceStartingItemRow(super.raw);

  String get raceStartingItemId => stringValue('Race Starting Item ID');

  String get raceId => stringValue('Race ID');

  String get itemId => stringValue('Item ID');

  num get quantity => numberValue('Quantity');

  num? get sortOrder => numberOrNull('Sort Order');

  String get status => stringValue('Status');

  String? get notes => stringOrNull('Notes');
}

class RecipeRow extends DbRow {
  const RecipeRow(super.raw);

  String get recipeId => stringValue('Recipe ID');

  String get internalKey => stringValue('Internal Key');

  String get displayName => stringValue('Display Name');

  String get skillId => stringValue('Skill ID');

  String get outputItemId => stringValue('Output Item ID');

  num get outputQuantity => numberValue('Output Quantity');

  String get facilityId => stringValue('Facility ID');

  num get proficiencyLevel => numberValue('Proficiency Level');

  num get baseDurationSeconds => numberValue('Base Duration Seconds');

  num get xpReward => numberValue('XP Reward');

  String? get knowledgeSource => stringOrNull('Knowledge Source');

  String get actionId => stringValue('Action ID');

  String get status => stringValue('Status');

  String get releasePhase => stringValue('Release Phase');

  String? get notes => stringOrNull('Notes');

  String? get ingredient1ItemId => stringOrNull('Ingredient 1 Item ID');

  num? get ingredient1Quantity => numberOrNull('Ingredient 1 Quantity');

  String? get ingredient2ItemId => stringOrNull('Ingredient 2 Item ID');

  num? get ingredient2Quantity => numberOrNull('Ingredient 2 Quantity');

  String? get ingredient3ItemId => stringOrNull('Ingredient 3 Item ID');

  num? get ingredient3Quantity => numberOrNull('Ingredient 3 Quantity');
}

class RequirementRow extends DbRow {
  const RequirementRow(super.raw);

  String get requirementId => stringValue('Requirement ID');

  String get entityType => stringValue('Entity Type');

  String get entityId => stringValue('Entity ID');

  String? get requirementGroup => stringOrNull('Requirement Group');

  String? get groupLogic => stringOrNull('Group Logic');

  String get requirementType => stringValue('Requirement Type');

  Object? get referenceIdValue => anyOrNull('Reference ID / Value');

  String? get operatorValue => stringOrNull('Operator');

  num? get requiredValue => numberOrNull('Required Value');

  String get status => stringValue('Status');

  String? get notes => stringOrNull('Notes');
}

class RewardEntryRow extends DbRow {
  const RewardEntryRow(super.raw);

  String get rewardEntryId => stringValue('Reward Entry ID');

  String get rewardTableId => stringValue('Reward Table ID');

  String? get rewardTableName => stringOrNull('Reward Table Name');

  String? get purpose => stringOrNull('Purpose');

  String get rewardType => stringValue('Reward Type');

  String? get rewardIdValue => stringOrNull('Reward ID / Value');

  num? get weight => numberOrNull('Weight');

  num? get minimumQuantity => numberOrNull('Minimum Quantity');

  num? get maximumQuantity => numberOrNull('Maximum Quantity');

  String? get skillId => stringOrNull('Skill ID');

  num? get xpAmount => numberOrNull('XP Amount');

  String get status => stringValue('Status');

  String? get notes => stringOrNull('Notes');
}

/// Carries extra columns beyond the typed accessors; read them from [raw].
class ShopRow extends DbRow {
  const ShopRow(super.raw);

  String get shopId => stringValue('Shop ID');

  String get internalKey => stringValue('Internal Key');

  String get displayName => stringValue('Display Name');

  String get locationId => stringValue('Location ID');

  String? get shopType => stringOrNull('Shop Type');

  String get status => stringValue('Status');

  String get releasePhase => stringValue('Release Phase');

  String? get description => stringOrNull('Description');

  String? get notes => stringOrNull('Notes');
}

class SkillRow extends DbRow {
  const SkillRow(super.raw);

  String get skillId => stringValue('Skill ID');

  String get internalKey => stringValue('Internal Key');

  String get displayName => stringValue('Display Name');

  String get category => stringValue('Category');

  String? get description => stringOrNull('Description');

  String get status => stringValue('Status');

  String get releasePhase => stringValue('Release Phase');

  String? get rulesNotes => stringOrNull('Rules / Notes');
}

class TravelConnectionRow extends DbRow {
  const TravelConnectionRow(super.raw);

  String get connectionId => stringValue('Connection ID');

  String get fromLocationId => stringValue('From Location ID');

  String get toLocationId => stringValue('To Location ID');

  String? get method => stringOrNull('Method');

  String? get direction => stringOrNull('Direction');

  num? get baseDuration => numberOrNull('Base Duration');

  String? get requiredMountStatus => stringOrNull('Required Mount / Status');

  String get status => stringValue('Status');

  String get releasePhase => stringValue('Release Phase');

  String? get notes => stringOrNull('Notes');
}

class XPCurveRow extends DbRow {
  const XPCurveRow(super.raw);

  num get level => numberValue('Level');

  num get totalXpAtLevel => numberValue('Total XP at Level');

  num? get xpToNextLevel => numberOrNull('XP to Next Level');
}

/// Table names in database order, mirroring `DATABASE_TABLES`.
const List<String> databaseTables = <String>[
  'Config',
  'Skills',
  'XPCurve',
  'EquipmentSlots',
  'Items',
  'Equipment',
  'Statistics',
  'Enchantments',
  'Maps',
  'Locations',
  'TravelConnections',
  'Facilities',
  'Activities',
  'PoolEntries',
  'Actions',
  'Requirements',
  'Enemies',
  'RewardEntries',
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
  'RaceBonuses',
  'RaceStartingItems',
];

/// Typed view over the parsed `game-database.json` root object.
///
/// Wraps [raw] without copying, so a filtered or reloaded database keeps the
/// exact JSON shape the TypeScript client sees.
class GameDatabase {
  GameDatabase(this.raw);

  final Map<String, Object?> raw;

  late final List<ConfigRow> config = typedRows(raw, 'Config', ConfigRow.new);

  late final List<SkillRow> skills = typedRows(raw, 'Skills', SkillRow.new);

  late final List<XPCurveRow> xpCurve = typedRows(raw, 'XPCurve', XPCurveRow.new);

  late final List<EquipmentSlotRow> equipmentSlots = typedRows(
    raw,
    'EquipmentSlots',
    EquipmentSlotRow.new,
  );

  late final List<ItemRow> items = typedRows(raw, 'Items', ItemRow.new);

  late final List<EquipmentRow> equipment = typedRows(raw, 'Equipment', EquipmentRow.new);

  late final List<Map<String, Object?>> statistics = untypedRows(raw, 'Statistics');

  late final List<EnchantmentRow> enchantments = typedRows(raw, 'Enchantments', EnchantmentRow.new);

  late final List<MapRow> maps = typedRows(raw, 'Maps', MapRow.new);

  late final List<LocationRow> locations = typedRows(raw, 'Locations', LocationRow.new);

  late final List<TravelConnectionRow> travelConnections = typedRows(
    raw,
    'TravelConnections',
    TravelConnectionRow.new,
  );

  late final List<FacilityRow> facilities = typedRows(raw, 'Facilities', FacilityRow.new);

  late final List<ActivityRow> activities = typedRows(raw, 'Activities', ActivityRow.new);

  late final List<PoolEntryRow> poolEntries = typedRows(raw, 'PoolEntries', PoolEntryRow.new);

  late final List<ActionRow> actions = typedRows(raw, 'Actions', ActionRow.new);

  late final List<RequirementRow> requirements = typedRows(raw, 'Requirements', RequirementRow.new);

  late final List<EnemyRow> enemies = typedRows(raw, 'Enemies', EnemyRow.new);

  late final List<RewardEntryRow> rewardEntries = typedRows(
    raw,
    'RewardEntries',
    RewardEntryRow.new,
  );

  late final List<RecipeRow> recipes = typedRows(raw, 'Recipes', RecipeRow.new);

  late final List<ProjectRow> projects = typedRows(raw, 'Projects', ProjectRow.new);

  late final List<NpcRow> npcs = typedRows(raw, 'NPCs', NpcRow.new);

  late final List<ShopRow> shops = typedRows(raw, 'Shops', ShopRow.new);

  late final List<Map<String, Object?>> quests = untypedRows(raw, 'Quests');

  late final List<QuestDialogueRow> questDialogue = typedRows(
    raw,
    'QuestDialogue',
    QuestDialogueRow.new,
  );

  late final List<Map<String, Object?>> achievements = untypedRows(raw, 'Achievements');

  late final List<CosmeticSlotRow> cosmeticSlots = typedRows(
    raw,
    'CosmeticSlots',
    CosmeticSlotRow.new,
  );

  late final List<CosmeticRow> cosmetics = typedRows(raw, 'Cosmetics', CosmeticRow.new);

  late final List<AppearanceOptionRow> appearanceOptions = typedRows(
    raw,
    'AppearanceOptions',
    AppearanceOptionRow.new,
  );

  late final List<LocationSearchRow> locationSearches = typedRows(
    raw,
    'LocationSearches',
    LocationSearchRow.new,
  );

  late final List<RaceRow> races = typedRows(raw, 'Races', RaceRow.new);

  late final List<RaceBonusRow> raceBonuses = typedRows(raw, 'RaceBonuses', RaceBonusRow.new);

  late final List<RaceStartingItemRow> raceStartingItems = typedRows(
    raw,
    'RaceStartingItems',
    RaceStartingItemRow.new,
  );

  /// Raw row maps for [table], for code that works across tables.
  List<Map<String, Object?>> rowsOf(String table) => untypedRows(raw, table);
}
