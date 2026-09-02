export const SAVE_VERSION = 41
export const SAVE_STORAGE_KEY = 'idle-kingdoms.demo.save'
export const STARTING_LOCATION_ID = 'LOC-0001'
/** Base gold before race kit; race starters grant the real starting gold. */
export const STARTING_GOLD = 0
/** Level 1 Hunting Net — granted on older save migration only. */
export const STARTING_HUNTING_TOOL_ID = 'ITEM-0108'
/** Retired fishing-net item. Existing copies become the hunting Net. */
export const RETIRED_FISHING_NET_ITEM_ID = 'ITEM-0104'
export const WEAPON_TOOL_SLOT_ID = 'SLOT-0001'
/** New-player starter kit item IDs. */
export const STARTING_BAKED_POTATO_ID = 'ITEM-0058'
export const STARTING_BAKED_POTATO_QTY = 5
export const STARTING_MINOR_STRENGTH_POTION_ID = 'ITEM-0211'
export const STARTING_WOODEN_AXE_ID = 'ITEM-0100'
export const CHARACTER_NAME_MAX_LENGTH = 24
/** Short profile motto shown under player art. */
export const MOTTO_MAX_LENGTH = 80

// Wardrobe / Cosmetics
export const OUTFIT_COSMETIC_SLOT_ID = 'CSLOT-0001'
export const PET_COSMETIC_SLOT_ID = 'CSLOT-0002'
export const TITLE_COSMETIC_SLOT_ID = 'CSLOT-0003'
export const STARTER_OUTFIT_COSMETIC_ID = 'COS-0001'
export const STARTER_TITLE_COSMETIC_ID = 'COS-0003'

/** Baseline Appearance Option IDs used until the player (or an old save) picks their own. */
export const DEFAULT_SKIN_TONE_ID = 'APR-0001'
export const DEFAULT_HAIRSTYLE_ID = 'APR-0004'
export const DEFAULT_HAIR_COLOR_ID = 'APR-0007'
export const DEFAULT_EXPRESSION_ID = 'APR-0011'
export const DEFAULT_BEARD_ID = 'APR-0014'
export const DEFAULT_GENDER_PRESENTATION_ID = 'APR-0017'

export type PotionConsumeScope =
  | 'one_combat_encounter'
  | 'one_action'
  | 'one_standard_production_action'

/** Data-driven potion effect active for the current eligible action/encounter. */
export interface ActivePotionEffect {
  scope: PotionConsumeScope
  itemId: string
  damageBonusPercent: number | null
  enemyMaxHpDamagePercent: number | null
  relativeDropChanceBonusPercent: number | null
  baseDurationReductionPercent: number | null
}

export interface SkillProgress {
  skillId: string
  level: number
  xp: number
}

export interface InventoryStack {
  itemId: string
  quantity: number
  /** Optional Arcana enchantment applied to this stack. */
  enchantmentId?: string | null
  /** Favorited stacks sort to the top of the bag and cannot be sold. */
  favorite?: boolean
}

/** Equipped contents for one slot. Food and potions may hold any stack size. */
export interface EquippedStack {
  itemId: string
  quantity: number
  /** Optional Arcana enchantment applied to this equipped item. */
  enchantmentId?: string | null
  /** Preserved across equip / unequip with the item. */
  favorite?: boolean
}

export interface EquipmentLoadout {
  /** Slot ID -> equipped stack or null */
  slots: Record<string, EquippedStack | null>
}

/** Icon for an equipment preset button. */
export interface EquipmentPresetIcon {
  /** `roman`, `skill`, or `coin`. */
  kind: string
  /** 1–4 when kind is `roman`. */
  numeral: number | null
  /** Skill ID when kind is `skill`. */
  skillId: string | null
}

/** Named snapshot of all equipment slots (gear, food/potion, spells). */
export interface EquipmentPreset {
  name: string
  icon: EquipmentPresetIcon
  slots: Record<string, EquippedStack | null>
}

export interface QuestProgress {
  questId: string
  status: 'inactive' | 'active' | 'completed'
  progress: number
  /** Typed counters for defeat/process/learn objectives (key → count). */
  counters?: Record<string, number>
}

export interface AchievementProgress {
  achievementId: string
  unlocked: boolean
  unlockedAt: string | null
}

export interface PlayerStatistics {
  values: Record<string, number>
}

export interface PlayerSettings {
  /** Reserved for later Settings/Menu work. */
  soundEnabled: boolean
  /** When false, the on-location activity reward summary is hidden. */
  showActivityRewards: boolean
  /** When true, HUD identity line shows total XP instead of total level. */
  hudShowTotalXp: boolean
  /** When false, the Eat button is hidden on the food item detail sheet. */
  showEatButton: boolean
  /**
   * Auto-eat when current HP is at or below this percent of max HP (1–100).
   * 100 keeps the old rule: eat whenever current HP is below maximum.
   */
  eatHealthThresholdPercent: number
  /** When true, the Equipment eat-at slider is shown as a percent. */
  eatHealthThresholdAsPercent: boolean
}

export const APPEARANCE_CATEGORIES = [
  'skinTone',
  'hairstyle',
  'hairColor',
  'expression',
  'beard',
  'genderPresentation',
] as const

export type AppearanceCategory = (typeof APPEARANCE_CATEGORIES)[number]

/** Selected Appearance Option ID per category. */
export interface PlayerAppearance {
  skinTone: string
  hairstyle: string
  hairColor: string
  expression: string
  beard: string
  genderPresentation: string
}

export interface CosmeticsState {
  /** Cosmetic IDs ever unlocked — owned forever, not consumable/stackable. */
  unlocked: string[]
  /** Cosmetic Slot ID -> equipped Cosmetic ID, or null. */
  equipped: Record<string, string | null>
}

/** Pending Primary Activity start/stop delay. */
export interface ActivityTransition {
  kind: 'starting' | 'stopping'
  activityId: string
  /** After a stop delay completes, begin starting this activity. */
  followUpActivityId: string | null
  /** Optional Standard Production payload applied when the start delay completes. */
  productionRecipeId: string | null
  productionQuantity: number | null
  startedAt: string
  durationMs: number
}

/** One unlocked Critter entry in the Log, with how many have been collected. */
export interface CritterCollectionEntry {
  critterId: string
  count: number
}

/** A Critter waiting to be collected at a location. */
export interface CritterSpawn {
  locationId: string
  critterId: string
  appearedAt: string
}

export interface PlayerSave {
  saveVersion: number
  createdAt: string
  updatedAt: string
  /** Player-chosen display name; null until first set. */
  characterName: string | null
  /** Short public motto under player art; null when unset. */
  motto: string | null
  /** Selected playable Race ID; null until first-run (or one-time) race picker completes. */
  raceId: string | null
  skills: SkillProgress[]
  inventory: InventoryStack[]
  /** Stash at the Town Bank and Citadel Bank. Same slot rules as the bag. */
  bank: InventoryStack[]
  /** One starred activity per location, auto-started on arrival. */
  favoriteActivityByLocationId: Record<string, string>
  /** Last unfinished pool action per activity, reused if that activity starts again. */
  heldActionByActivityId: Record<string, string>
  equipment: EquipmentLoadout
  /** Four named loadout snapshots; preset 1 auto-tracks while active. */
  equipmentPresets: EquipmentPreset[]
  /** Index into equipmentPresets (0–3). */
  activeEquipmentPresetIndex: number
  /** Gold amount; itemized currency uses Config currency_item_id. */
  gold: number
  quests: QuestProgress[]
  achievements: AchievementProgress[]
  statistics: PlayerStatistics
  /** NPC IDs that have granted permanent project knowledge (Master Dwarf / Archmage). */
  unlockedNpcIds: string[]
  /** Recipe IDs unlocked by quests, discoveries, NPCs, or drops (beyond automatic level unlocks). */
  unlockedRecipeIds: string[]
  /** Location IDs unlocked by quests (e.g. Rose's Apothecary). */
  unlockedLocationIds: string[]
  /** UTC hour key for the active Citadel bounty board. */
  bountyHourKey: string | null
  /** Progress counters for the current bounty hour (bountyId → count). */
  bountyProgress: Record<string, number>
  /** Bounty IDs claimed by this character during the current hour. */
  bountyClaimedIds: string[]
  /** UTC date key (`YYYY-MM-DD`) for the ranked PvP daily fight cap. */
  rankedPvpDayKey: string | null
  /** Ranked arena fights already used during [rankedPvpDayKey]. */
  rankedPvpFightsToday: number
  /** Ranked arena wins, which feed the PvP K/D leaderboard. */
  rankedPvpWins: number
  /** Ranked arena losses. */
  rankedPvpLosses: number
  /** UTC date key (`YYYY-MM-DD`) for shop daily purchase caps. */
  shopPurchaseDayKey: string | null
  /** Units bought today, keyed by `shopId:itemId`. */
  shopPurchasesToday: Record<string, number>
  /** Merchant tip rewards already claimed (one-time dialogue grants). */
  claimedMerchantTipIds: string[]
  /** One-time Kingswoods Sling grant. Existing saves keep false until they visit. */
  claimedKingswoodsSling: boolean
  /** Critter collection counts (unlocked entries in the Log). */
  critterCollections: CritterCollectionEntry[]
  /** At most one pending Critter spawn per location until collected. */
  activeCritterSpawns: CritterSpawn[]
  /** Remainder activity ms toward the next Critter hour-roll, keyed by location. */
  critterProgressMs: Record<string, number>
  /** Location Search ID -> ISO timestamp of the last successful search (for cooldowns). */
  locationSearchClaims: Record<string, string>
  /** Owned/equipped Wardrobe Cosmetics. */
  cosmetics: CosmeticsState
  /** Selected character Appearance options. */
  appearance: PlayerAppearance
  /** Whether the player has ever opened the Wardrobe (gates the intro hint highlight). */
  hasSeenWardrobeIntro: boolean
  /** Whether the player has dismissed Fennel's first farm welcome. */
  hasSeenFennelIntro: boolean
  /** ISO timestamps of the last miniquest completion, keyed by Quest ID. */
  miniquestCompletedAt: Record<string, string>
  settings: PlayerSettings
  currentLocationId: string
  currentActivityId: string | null
  activityStartedAt: string | null
  currentActionId: string | null
  actionStartedAt: string | null
  actionDurationMs: number | null
  combatEnemyId: string | null
  combatEnemyHp: number | null
  combatRoundStartedAt: string | null
  /**
   * Staff of Binding: when true, the enemy skips their next attack.
   * Cleared after that skipped swing, or when combat ends.
   */
  combatSkipEnemyAttack: boolean
  /**
   * Boss sleep rounds still remaining, including the current one when > 0.
   * Null when the current enemy is not a sleeping boss.
   */
  combatBossSleepRoundsRemaining: number | null
  /**
   * Boss Enemy ID stored while the player clears add enemies (e.g. squidlings).
   * Null when not in an add phase.
   */
  combatBossPendingId: string | null
  /** Boss HP to restore when all adds are defeated. */
  combatBossPendingHp: number | null
  /** Add enemies still to defeat before the boss resumes. Null outside add phase. */
  combatBossAddsRemaining: number | null
  /** True once the boss has triggered its add phase (prevents re-triggering). */
  combatBossAddsTriggered: boolean
  /** True when ink halved player damage this combat round. */
  combatBossInkActive: boolean
  /** ISO timestamps until a defeated boss can be fought again, keyed by Enemy ID. */
  bossRespawnUntilByEnemyId: Record<string, string>
  /** Potion consumed for the current gathering action, craft, or combat encounter. */
  activePotionEffect: ActivePotionEffect | null
  deathPauseUntil: string | null
  /**
   * Whether this character has ever been beaten in the world. Arena losses do
   * not count. Once true it stays true, which is what makes the Undying title
   * worth holding.
   */
  hasEverDied: boolean
  productionRecipeId: string | null
  productionQuantityTotal: number | null
  productionQuantityRemaining: number | null
  /** Pending start/stop delay for Primary Activities. */
  activityTransition: ActivityTransition | null
  unattendedProgressAt: string | null
  /**
   * Time on this character: live session frames plus unattended catch-up
   * (capped the same way as away progress). Existing saves start at 0.
   */
  playTimeMs: number
  currentHp: number
  maxHp: number
}

export interface SaveMigration {
  fromVersion: number
  toVersion: number
  /** `nowMs` is only consulted by steps that must invent a missing timestamp. */
  migrate: (save: PlayerSave, nowMs: number) => PlayerSave
}
