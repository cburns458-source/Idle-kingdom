import { getSkillProgress } from '../activity/xp'
import { CRITTER_DEFS, collectionCount } from '../critters/critters'
import type { GameDatabase } from '../data/types'
import { itemHasCapability, WEAPON_TOOL_SLOT_ID } from '../equipment/loadout'
import { totalLevel, totalSkillXp } from '../skills/totals'
import type { AchievementProgress, PlayerSave } from '../save/types'

export interface AchievementRow {
  'Achievement ID': string
  'Internal Key': string
  'Display Name': string
  Category: string | null
  Difficulty: string | null
  'Check Type': string | null
  'Target ID': string | null
  'Required Count': number | null
  Status: string
  'Release Phase': string
  Reward: string | null
  'Target Skill ID': string | null
  'Required Level': number | null
  Notes: string | null
}

export const ACHIEVEMENT_DIFFICULTIES = ['Easy', 'Medium', 'Hard'] as const

export function addLifetimeStat(save: PlayerSave, key: string, amount = 1): PlayerSave {
  const current = Number(save.statistics.values[key] ?? 0)
  return {
    ...save,
    statistics: {
      values: {
        ...save.statistics.values,
        [key]: current + amount,
      },
    },
  }
}

export function isSpellProject(project: { 'Internal Key'?: string; 'Display Name'?: string }): boolean {
  const key = String(project['Internal Key'] ?? '')
  const name = String(project['Display Name'] ?? '').toLowerCase()
  return key.includes('_spell') || (name.includes('spell') && !name.includes('enchant'))
}

export function recordProjectMilestones(
  db: GameDatabase,
  save: PlayerSave,
  projectId: string,
  crafts: number,
): PlayerSave {
  const project = db.Projects.find((row) => row['Project ID'] === projectId)
  let next = addLifetimeStat(save, `project_${projectId}`, crafts)
  const locationId = save.currentLocationId
  if (locationId) {
    next = addLifetimeStat(next, `project_${projectId}_at_${locationId}`, crafts)
  }
  const outputId = String(project?.['Output Item / Target ID'] ?? '')
  if (outputId.startsWith('ENCH-')) {
    next = addLifetimeStat(next, 'items_enchanted', crafts)
  }
  if (project && isSpellProject(project)) {
    next = addLifetimeStat(next, 'spell_projects', crafts)
  }
  return next
}

export function recordProductionMilestones(
  db: GameDatabase,
  save: PlayerSave,
  outputItemId: string,
  quantity: number,
): PlayerSave {
  let next = addLifetimeStat(save, `output_${outputItemId}`, quantity)
  const locationId = save.currentLocationId
  if (locationId) {
    next = addLifetimeStat(next, `output_${outputItemId}_at_${locationId}`, quantity)
  }
  const item = db.Items.find((row) => row['Item ID'] === outputItemId)
  if (item?.Category === 'Potion') {
    next = addLifetimeStat(next, 'potions_created', quantity)
  }
  return next
}

export function recordFoodConsumed(save: PlayerSave, itemId: string): PlayerSave {
  return addLifetimeStat(save, `consumed_${itemId}`, 1)
}

export function recordGatheredDrops(
  save: PlayerSave,
  itemIds: Iterable<string>,
  locationId: string,
  weaponId: string | null,
): PlayerSave {
  const wield = weaponId && weaponId.length > 0 ? weaponId : 'none'
  let next = save
  for (const itemId of itemIds) {
    next = addLifetimeStat(next, `gathered_${itemId}_at_${locationId}_wield_${wield}`)
  }
  return next
}

export function recordItemsSoldAtLocation(
  save: PlayerSave,
  items: Iterable<{ itemId: string; quantity: number }>,
  locationId: string,
): PlayerSave {
  let next = save
  for (const item of items) {
    const qty = Math.max(0, Number(item.quantity) || 0)
    if (qty <= 0) continue
    next = addLifetimeStat(next, `sold_${item.itemId}_at_${locationId}`, qty)
  }
  return next
}

function splitTags(value: string | null | undefined): string[] {
  if (typeof value !== 'string') return []
  return value
    .split(';')
    .map((part) => part.trim().toLowerCase())
    .filter(Boolean)
}

/** True when the item carries a class label such as `staff` or `wand`. */
export function itemHasClassLabel(db: GameDatabase, itemId: string, label: string): boolean {
  const wanted = label.trim().toLowerCase()
  if (!wanted) return false
  if (itemHasCapability(db, itemId, wanted)) return true
  const item = db.Items.find((row) => row['Item ID'] === itemId)
  return splitTags(item?.['Functional / Source Tags']).includes(wanted)
}

export function classLabelsFromAchievements(db: GameDatabase): string[] {
  const labels = new Set<string>()
  for (const row of asAchievementRows(db)) {
    if (row['Check Type'] !== 'kill_enemy_class') continue
    const parsed = parseKillEnemyClass(row['Target ID'])
    parsed?.classes.forEach((name) => labels.add(name))
  }
  return [...labels]
}

export function classLabelsOnItem(db: GameDatabase, itemId: string): string[] {
  return classLabelsFromAchievements(db).filter((label) => itemHasClassLabel(db, itemId, label))
}

export function recordEnemyKill(db: GameDatabase, save: PlayerSave, enemyId: string): PlayerSave {
  let next = addLifetimeStat(save, `killed_${enemyId}`)
  const weaponId = save.equipment.slots[WEAPON_TOOL_SLOT_ID]?.itemId
  if (!weaponId) return next
  for (const label of classLabelsOnItem(db, weaponId)) {
    next = addLifetimeStat(next, `killed_${enemyId}_class_${label}`)
  }
  return next
}

function parseAtLocation(target: string | null): { id: string; locationId: string } | null {
  if (!target) return null
  const at = target.indexOf('@')
  if (at <= 0 || at === target.length - 1) return null
  return { id: target.slice(0, at), locationId: target.slice(at + 1) }
}

function parseGatherDrop(
  target: string | null,
): { itemId: string; locationId: string; weaponId: string } | null {
  if (!target) return null
  const [atPart, wieldPart] = target.split('+wield:')
  const parsed = parseAtLocation(atPart ?? null)
  if (!parsed || !wieldPart) return null
  return { itemId: parsed.id, locationId: parsed.locationId, weaponId: wieldPart }
}

function parseKillEnemyClass(
  target: string | null,
): { enemyId: string; classes: string[] } | null {
  if (!target) return null
  const [enemyId, rest] = target.split('+class:')
  if (!enemyId || !rest) return null
  const classes = rest
    .split('|')
    .map((part) => part.trim().toLowerCase())
    .filter(Boolean)
  if (classes.length === 0) return null
  return { enemyId, classes }
}

function equippedItemIds(save: PlayerSave): Set<string> {
  const ids = new Set<string>()
  for (const stack of Object.values(save.equipment.slots)) {
    if (stack?.itemId) ids.add(stack.itemId)
  }
  return ids
}

function holdsEquipSet(save: PlayerSave, target: string | null): boolean {
  if (!target) return false
  const needed = target
    .split(',')
    .map((part) => part.trim())
    .filter(Boolean)
  if (needed.length === 0) return false
  const worn = equippedItemIds(save)
  return needed.every((itemId) => worn.has(itemId))
}

export interface StatisticRow {
  'Statistic ID': string
  'Internal Key': string
  'Display Name': string
  Category: string | null
  Status: string
  'Release Phase': string
  Notes: string | null
}

export function asAchievementRows(db: GameDatabase): AchievementRow[] {
  return db.Achievements as unknown as AchievementRow[]
}

export function asStatisticRows(db: GameDatabase): StatisticRow[] {
  return db.Statistics as unknown as StatisticRow[]
}

/**
 * Achievements in this category are re-checked every sync and can be lost.
 *
 * A skill milestone is a thing the player did once, so it is theirs forever. A
 * collection is a statement about the collection as it stands now, which stops
 * being true the moment the world grows a new critter.
 */
export const REVOCABLE_ACHIEVEMENT_CATEGORY = 'Collections'

export const CRITTER_COLLECTOR_ACHIEVEMENT_ID = 'ACH-0015'

function upsertAchievement(
  list: AchievementProgress[],
  achievementId: string,
  unlockedAt: string,
): AchievementProgress[] {
  const existing = list.find((row) => row.achievementId === achievementId)
  if (existing?.unlocked) return list
  const next = list.filter((row) => row.achievementId !== achievementId)
  next.push({ achievementId, unlocked: true, unlockedAt })
  return next
}

function revokeAchievement(
  list: AchievementProgress[],
  achievementId: string,
): AchievementProgress[] {
  if (!list.some((row) => row.achievementId === achievementId)) return list
  return list.filter((row) => row.achievementId !== achievementId)
}

/** Whether the collection holds at least one of every critter that exists. */
export function hasEveryCritter(save: PlayerSave): boolean {
  if (CRITTER_DEFS.length === 0) return false
  return CRITTER_DEFS.every((critter) => collectionCount(save, critter.id) > 0)
}

/** Whether a save currently qualifies for a category that can be lost again. */
function holdsRevocableAchievement(save: PlayerSave, achievementId: string): boolean {
  return achievementId === CRITTER_COLLECTOR_ACHIEVEMENT_ID && hasEveryCritter(save)
}

function lifetimeCount(values: Record<string, number>, key: string): number {
  return Number(values[key] ?? 0)
}

function holdsMilestone(
  db: GameDatabase,
  save: PlayerSave,
  achievement: AchievementRow,
  values: Record<string, number>,
): boolean {
  const check = achievement['Check Type'] ?? ''
  const target = achievement['Target ID']
  const count = Number(achievement['Required Count'] ?? 1)
  const required = achievement['Required Level']
  switch (check) {
    case 'project':
      return target != null && lifetimeCount(values, `project_${target}`) >= count
    case 'consume':
      return target != null && lifetimeCount(values, `consumed_${target}`) >= count
    case 'output_item':
      return target != null && lifetimeCount(values, `output_${target}`) >= count
    case 'output_at_location': {
      const parsed = parseAtLocation(target)
      return parsed != null && lifetimeCount(values, `output_${parsed.id}_at_${parsed.locationId}`) >= count
    }
    case 'project_at_location': {
      const parsed = parseAtLocation(target)
      return (
        parsed != null && lifetimeCount(values, `project_${parsed.id}_at_${parsed.locationId}`) >= count
      )
    }
    case 'gather_drop': {
      const parsed = parseGatherDrop(target)
      return (
        parsed != null &&
        lifetimeCount(
          values,
          `gathered_${parsed.itemId}_at_${parsed.locationId}_wield_${parsed.weaponId}`,
        ) >= count
      )
    }
    case 'sold_at_location': {
      const parsed = parseAtLocation(target)
      return parsed != null && lifetimeCount(values, `sold_${parsed.id}_at_${parsed.locationId}`) >= count
    }
    case 'kill_enemy':
      return target != null && lifetimeCount(values, `killed_${target}`) >= count
    case 'kill_enemy_class': {
      const parsed = parseKillEnemyClass(target)
      if (!parsed) return false
      return parsed.classes.some(
        (label) => lifetimeCount(values, `killed_${parsed.enemyId}_class_${label}`) >= count,
      )
    }
    case 'equip_set':
      return holdsEquipSet(save, target)
    case 'equip_quiver_bow': {
      if (!target) return false
      const worn = equippedItemIds(save)
      if (!worn.has(target)) return false
      const weaponId = save.equipment.slots[WEAPON_TOOL_SLOT_ID]?.itemId
      return weaponId != null && itemHasCapability(db, weaponId, 'bow_combat_xp')
    }
    case 'enchant':
      return lifetimeCount(values, 'items_enchanted') >= count
    case 'potion':
      return lifetimeCount(values, 'potions_created') >= count
    case 'spell_projects':
      return lifetimeCount(values, 'spell_projects') >= count
    case 'gold':
      return lifetimeCount(values, 'gold_earned') >= count
    case 'skill_all':
      if (typeof required !== 'number') return false
      return db.Skills.every((skill) => getSkillProgress(save, skill['Skill ID']).level >= required)
    default: {
      const skillId = achievement['Target Skill ID']
      if (!skillId || typeof required !== 'number') return false
      return getSkillProgress(save, skillId).level >= required
    }
  }
}

/** Refresh lifetime totals and unlock skill-level achievements. */
export function syncProgressionMeta(db: GameDatabase, save: PlayerSave, now = Date.now()): PlayerSave {
  const crittersCollected = (save.critterCollections ?? []).reduce(
    (sum, row) => sum + Math.max(0, row.count),
    0,
  )
  const values = {
    ...save.statistics.values,
    total_level: totalLevel(save),
    total_experience: totalSkillXp(save),
    gold_earned: Number(save.statistics.values.gold_earned ?? 0),
    monsters_killed: Number(save.statistics.values.monsters_killed ?? 0),
    critters_collected: crittersCollected,
    bounties_completed: Number(save.statistics.values.bounties_completed ?? 0),
  }

  let achievements = [...save.achievements]
  const unlockedAt = new Date(now).toISOString()
  for (const achievement of asAchievementRows(db)) {
    const achievementId = achievement['Achievement ID']
    if (achievement.Category === REVOCABLE_ACHIEVEMENT_CATEGORY) {
      achievements = holdsRevocableAchievement(save, achievementId)
        ? upsertAchievement(achievements, achievementId, unlockedAt)
        : revokeAchievement(achievements, achievementId)
      continue
    }
    if (holdsMilestone(db, save, achievement, values)) {
      achievements = upsertAchievement(achievements, achievementId, unlockedAt)
    }
  }

  return {
    ...save,
    statistics: { values },
    achievements,
  }
}
