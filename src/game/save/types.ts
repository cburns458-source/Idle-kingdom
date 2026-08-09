export const SAVE_VERSION = 4
export const SAVE_STORAGE_KEY = 'idle-kingdoms.demo.save'
export const STARTING_LOCATION_ID = 'LOC-0002'
export const STARTING_GOLD = 0

export interface SkillProgress {
  skillId: string
  level: number
  xp: number
}

export interface InventoryStack {
  itemId: string
  quantity: number
}

/** Equipped contents for one slot. Food may hold any stack size. */
export interface EquippedStack {
  itemId: string
  quantity: number
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
}

export interface PlayerSave {
  saveVersion: number
  createdAt: string
  updatedAt: string
  skills: SkillProgress[]
  inventory: InventoryStack[]
  equipment: EquipmentLoadout
  /** Gold amount; itemized currency uses Config currency_item_id. */
  gold: number
  quests: QuestProgress[]
  achievements: AchievementProgress[]
  statistics: PlayerStatistics
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
  unattendedProgressAt: string | null
  currentHp: number
  maxHp: number
}

export interface SaveMigration {
  fromVersion: number
  toVersion: number
  migrate: (save: PlayerSave) => PlayerSave
}
