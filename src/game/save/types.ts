export const SAVE_VERSION = 16
export const SAVE_STORAGE_KEY = 'idle-kingdoms.demo.save'
export const STARTING_LOCATION_ID = 'LOC-0002'
export const STARTING_GOLD = 25
/** Level 1 Hunting Net — granted on older save migration only. */
export const STARTING_HUNTING_TOOL_ID = 'ITEM-0108'
export const WEAPON_TOOL_SLOT_ID = 'SLOT-0001'
/** New-player starter kit item IDs. */
export const STARTING_BAKED_POTATO_ID = 'ITEM-0058'
export const STARTING_BAKED_POTATO_QTY = 5
export const STARTING_MINOR_STRENGTH_POTION_ID = 'ITEM-0211'
export const STARTING_WOODEN_AXE_ID = 'ITEM-0100'
export const CHARACTER_NAME_MAX_LENGTH = 24

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
}

/** Equipped contents for one slot. Food and potions may hold any stack size. */
export interface EquippedStack {
  itemId: string
  quantity: number
  /** Optional Arcana enchantment applied to this equipped item. */
  enchantmentId?: string | null
}

export interface EquipmentLoadout {
  /** Slot ID -> equipped stack or null */
  slots: Record<string, EquippedStack | null>
}

export interface QuestProgress {
  questId: string
  status: 'inactive' | 'active' | 'completed'
  progress: number
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

export interface PlayerSave {
  saveVersion: number
  createdAt: string
  updatedAt: string
  /** Player-chosen display name; null until first set. */
  characterName: string | null
  skills: SkillProgress[]
  inventory: InventoryStack[]
  equipment: EquipmentLoadout
  /** Gold amount; itemized currency uses Config currency_item_id. */
  gold: number
  quests: QuestProgress[]
  achievements: AchievementProgress[]
  statistics: PlayerStatistics
  /** NPC IDs that have granted permanent project knowledge (Master Dwarf / Archmage). */
  unlockedNpcIds: string[]
  /** Location IDs unlocked by quests (e.g. Rose's Apothecary). */
  unlockedLocationIds: string[]
  /** Merchant tip rewards already claimed (one-time dialogue grants). */
  claimedMerchantTipIds: string[]
  /** Critter collection counts (unlocked entries in the Log). */
  critterCollections: Array<{ critterId: string; count: number }>
  /** At most one pending Critter spawn per location until collected. */
  activeCritterSpawns: Array<{ locationId: string; critterId: string; appearedAt: string }>
  /** Remainder activity ms toward the next Critter hour-roll, keyed by location. */
  critterProgressMs: Record<string, number>
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
  migrate: (save: PlayerSave) => PlayerSave
}
