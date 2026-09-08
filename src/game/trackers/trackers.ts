import type { ActionRow } from '../data/types'
import type { LootGrant } from '../activity/types'
import type { LootTrackerEntry, PlayerSave, XpTrackerEntry } from '../save/types'
import { TOTAL_XP_TRACKER_ID } from '../save/types'

export { TOTAL_XP_TRACKER_ID }

export function lootTrackerKey(kind: LootTrackerEntry['kind'], sourceId: string): string {
  return `${kind}:${sourceId}`
}

/** Combat actions key by enemy so Cow and Bull stay separate. */
export function lootSourceForAction(action: ActionRow): {
  kind: LootTrackerEntry['kind']
  sourceId: string
} {
  const targetId = action['Target ID']
  if ((action.Category === 'Combat' || action['Target Type'] === 'Enemy') && targetId) {
    return { kind: 'enemy', sourceId: targetId }
  }
  return { kind: 'action', sourceId: action['Action ID'] }
}

export function creditLootTracker(
  save: PlayerSave,
  kind: LootTrackerEntry['kind'],
  sourceId: string,
  loot: LootGrant[],
  gold: number,
  nowMs: number,
): PlayerSave {
  const key = lootTrackerKey(kind, sourceId)
  const existing = save.lootTrackers[key]
  const items = { ...(existing?.items ?? {}) }
  for (const grant of loot) {
    if (!grant.itemId || grant.quantity <= 0) continue
    items[grant.itemId] = (items[grant.itemId] ?? 0) + grant.quantity
  }
  const next: LootTrackerEntry = {
    key,
    kind,
    sourceId,
    startedAtMs: existing?.startedAtMs ?? nowMs,
    completions: (existing?.completions ?? 0) + 1,
    gold: (existing?.gold ?? 0) + gold,
    items,
  }
  return { ...save, lootTrackers: { ...save.lootTrackers, [key]: next } }
}

export function creditXpTracker(
  save: PlayerSave,
  skillId: string,
  xp: number,
  nowMs: number,
): PlayerSave {
  if (xp <= 0) return save
  const existing = save.xpTrackers[skillId]
  const next: XpTrackerEntry = {
    skillId,
    startedAtMs: existing?.startedAtMs ?? nowMs,
    xpGained: (existing?.xpGained ?? 0) + xp,
  }
  return { ...save, xpTrackers: { ...save.xpTrackers, [skillId]: next } }
}

export function creditXpAwards(
  save: PlayerSave,
  awards: Array<{ skillId: string; xp: number }>,
  nowMs: number,
): PlayerSave {
  let next = save
  let total = 0
  for (const award of awards) {
    if (award.xp <= 0) continue
    next = creditXpTracker(next, award.skillId, award.xp, nowMs)
    total += award.xp
  }
  if (total > 0) next = creditXpTracker(next, TOTAL_XP_TRACKER_ID, total, nowMs)
  return next
}

export function resetLootTracker(save: PlayerSave, key: string): PlayerSave {
  if (!save.lootTrackers[key]) return save
  const lootTrackers = { ...save.lootTrackers }
  delete lootTrackers[key]
  return { ...save, lootTrackers }
}

export function resetAllLootTrackers(save: PlayerSave): PlayerSave {
  if (Object.keys(save.lootTrackers).length === 0) return save
  return { ...save, lootTrackers: {} }
}

export function resetXpTracker(save: PlayerSave, skillId: string): PlayerSave {
  if (!save.xpTrackers[skillId]) return save
  const xpTrackers = { ...save.xpTrackers }
  delete xpTrackers[skillId]
  return { ...save, xpTrackers }
}

export function resetAllXpTrackers(save: PlayerSave): PlayerSave {
  if (Object.keys(save.xpTrackers).length === 0) return save
  return { ...save, xpTrackers: {} }
}

export function xpPerHour(entry: XpTrackerEntry, nowMs: number): number {
  const elapsed = Math.max(1, nowMs - entry.startedAtMs)
  return (entry.xpGained / elapsed) * 3_600_000
}

export function sortedLootTrackers(save: PlayerSave): LootTrackerEntry[] {
  return Object.values(save.lootTrackers).sort((a, b) => a.startedAtMs - b.startedAtMs)
}

export function sortedXpTrackers(save: PlayerSave): XpTrackerEntry[] {
  return Object.values(save.xpTrackers).sort((a, b) => {
    if (a.skillId === TOTAL_XP_TRACKER_ID) return -1
    if (b.skillId === TOTAL_XP_TRACKER_ID) return 1
    return a.startedAtMs - b.startedAtMs
  })
}
