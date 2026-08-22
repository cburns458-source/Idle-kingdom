import type { ActionRow, GameDatabase, PoolEntryRow } from '../data/types'
import { isBelowProficiency } from './gathering'
import type { PlayerSave } from '../save/types'

export type RandomFn = () => number

export type PoolCandidate = { entry: PoolEntryRow; action: ActionRow }

/** Gathering or Combat actions with complete runtime data. */
export function isSelectableAction(action: ActionRow): boolean {
  if (action.Status === 'Needs Data') return false
  if (action.Category === 'Gathering') {
    return typeof action['Base Duration Seconds'] === 'number' && typeof action['XP Reward'] === 'number'
  }
  if (action.Category === 'Combat') {
    return typeof action['Target ID'] === 'string' && action['Target ID'].length > 0
  }
  return false
}

/** @deprecated use isSelectableAction */
export const isStep3SelectableAction = isSelectableAction

export function eligiblePoolEntries(db: GameDatabase, poolId: string): PoolCandidate[] {
  const pairs: PoolCandidate[] = []
  for (const entry of db.PoolEntries) {
    if (entry['Pool ID'] !== poolId) continue
    if (entry.Status === 'Needs Data') continue
    if (typeof entry.Weight !== 'number' || entry.Weight <= 0) continue
    const action = db.Actions.find((row) => row['Action ID'] === entry['Action ID'])
    if (!action || !isSelectableAction(action)) continue
    pairs.push({ entry, action })
  }
  return pairs
}

/** Pool actions the player can do at full speed, or the whole pool if none. */
export function preferredPoolEntries(
  db: GameDatabase,
  save: PlayerSave,
  poolId: string,
): PoolCandidate[] {
  const all = eligiblePoolEntries(db, poolId)
  const ready = all.filter((pair) => !isBelowProficiency(save, pair.action))
  return ready.length > 0 ? ready : all
}

export function pickWeightedAction(
  entries: Array<{ entry: PoolEntryRow; action: ActionRow }>,
  random: RandomFn = Math.random,
): ActionRow | null {
  if (entries.length === 0) return null
  const total = entries.reduce((sum, pair) => sum + (pair.entry.Weight ?? 0), 0)
  if (total <= 0) return null
  let roll = random() * total
  for (const pair of entries) {
    roll -= pair.entry.Weight ?? 0
    if (roll <= 0) return pair.action
  }
  return entries[entries.length - 1]?.action ?? null
}
