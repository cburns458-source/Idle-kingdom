export const SAVE_VERSION = 11
export const SAVE_STORAGE_KEY = 'idle-kingdoms.demo.save'
export const STARTING_LOCATION_ID = 'LOC-0002'
export const STARTING_GOLD = 0
/** Level 1 Hunting Net — demo starting tool for hunting tests. */
export const STARTING_HUNTING_TOOL_ID = 'ITEM-0108'
export const WEAPON_TOOL_SLOT_ID = 'SLOT-0001'
export const CHARACTER_NAME_MAX_LENGTH = 24

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

/** Equipped contents for one slot. Food may hold any stack size. */
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
