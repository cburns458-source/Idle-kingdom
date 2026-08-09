import type { ActionRow, GameDatabase, PoolEntryRow } from '../data/types'

export type RandomFn = () => number

/** Step 3: Gathering actions with complete runtime data only. */
export function isStep3SelectableAction(action: ActionRow): boolean {
  if (action.Status === 'Needs Data') return false
  if (action.Category !== 'Gathering') return false
  if (typeof action['Base Duration Seconds'] !== 'number') return false
  if (typeof action['XP Reward'] !== 'number') return false
  return true
}

export function eligiblePoolEntries(
  db: GameDatabase,
  poolId: string,
): Array<{ entry: PoolEntryRow; action: ActionRow }> {
  const pairs: Array<{ entry: PoolEntryRow; action: ActionRow }> = []
  for (const entry of db.PoolEntries) {
    if (entry['Pool ID'] !== poolId) continue
    if (entry.Status === 'Needs Data') continue
    if (typeof entry.Weight !== 'number' || entry.Weight <= 0) continue
    const action = db.Actions.find((row) => row['Action ID'] === entry['Action ID'])
    if (!action || !isStep3SelectableAction(action)) continue
    pairs.push({ entry, action })
  }
  return pairs
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
