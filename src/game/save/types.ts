export const SAVE_VERSION = 28
export const SAVE_STORAGE_KEY = 'idle-kingdoms.demo.save'
export const STARTING_LOCATION_ID = 'LOC-0002'
/** Base gold before race kit; race starters grant the real starting gold. */
export const STARTING_GOLD = 0
/** Level 1 Hunting Net — granted on older save migration only. */
export const STARTING_HUNTING_TOOL_ID = 'ITEM-0108'
export const WEAPON_TOOL_SLOT_ID = 'SLOT-0001'
/** New-player starter kit item IDs. */
export const STARTING_BAKED_POTATO_ID = 'ITEM-0058'
export const STARTING_BAKED_POTATO_QTY = 5
export const STARTING_MINOR_STRENGTH_POTION_ID = 'ITEM-0211'
export const STARTING_WOODEN_AXE_ID = 'ITEM-0100'
export const CHARACTER_NAME_MAX_LENGTH = 24

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
  /** Merchant tip rewards already claimed (one-time dialogue grants). */
  claimedMerchantTipIds: string[]
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
  currentHp: number
  maxHp: number
}

export interface SaveMigration {
  fromVersion: number
  toVersion: number
  /** `nowMs` is only consulted by steps that must invent a missing timestamp. */
  migrate: (save: PlayerSave, nowMs: number) => PlayerSave
}
