import { addItemToInventory } from '../activity/rewards'
import type {
  GameDatabase,
  RaceBonusRow,
  RaceRow,
  RaceStartingItemRow,
} from '../data/types'
import type { PlayerSave } from '../save/types'

export const DWARF_RACE_ID = 'RACE-0006'
export const DWARVEN_MINING_STORE_FACILITY_ID = 'FAC-0009'

function parseIdList(raw: string | null | undefined): string[] {
  if (typeof raw !== 'string' || !raw.trim()) return []
  return raw
    .split(';')
    .map((part) => part.trim())
    .filter(Boolean)
}

export function races(db: GameDatabase): RaceRow[] {
  return [...db.Races].sort(
    (a, b) =>
      (a['Sort Order'] ?? 0) - (b['Sort Order'] ?? 0) ||
      a['Display Name'].localeCompare(b['Display Name']),
  )
}

export function raceById(db: GameDatabase, raceId: string | null | undefined): RaceRow | undefined {
  if (!raceId) return undefined
  return db.Races.find((row) => row['Race ID'] === raceId)
}

export function raceDisplayName(db: GameDatabase, raceId: string | null | undefined): string | null {
  return raceById(db, raceId)?.['Display Name'] ?? null
}

export function raceBonusesFor(db: GameDatabase, raceId: string | null | undefined): RaceBonusRow[] {
  if (!raceId) return []
  return db.RaceBonuses.filter(
    (row) => row['Race ID'] === raceId && row.Status !== 'Needs Data',
  )
}

export function raceStartingItems(
  db: GameDatabase,
  raceId: string,
): RaceStartingItemRow[] {
  return db.RaceStartingItems.filter((row) => row['Race ID'] === raceId).sort(
    (a, b) =>
      (a['Sort Order'] ?? 0) - (b['Sort Order'] ?? 0) ||
      a['Race Starting Item ID'].localeCompare(b['Race Starting Item ID']),
  )
}

/** Sum of matching percent bonuses (e.g. two +5 rows → 10). */
function totalBonusPercent(
  db: GameDatabase,
  save: PlayerSave,
  bonusType: string,
  referenceId: string | null = null,
): number {
  let total = 0
  for (const bonus of raceBonusesFor(db, save.raceId)) {
    if (bonus['Bonus Type'] !== bonusType) continue
    if (referenceId != null && bonus['Reference ID'] !== referenceId) continue
    if (referenceId == null && bonus['Reference ID'] != null) continue
    const value = Number(bonus['Bonus Value'] ?? 0)
    if (Number.isFinite(value)) total += value
  }
  return total
}

export function raceSkillDropChanceBonusPercent(
  db: GameDatabase,
  save: PlayerSave,
  skillId: string,
): number {
  return totalBonusPercent(db, save, 'skill_drop_chance_percent', skillId)
}

export function raceMaxHpMultiplier(db: GameDatabase, save: PlayerSave): number {
  return 1 + totalBonusPercent(db, save, 'max_hp_percent') / 100
}

export function raceGoldGainMultiplier(db: GameDatabase, save: PlayerSave): number {
  return 1 + totalBonusPercent(db, save, 'gold_gain_percent') / 100
}

/** Mining level required for the Dwarven Mining Store (35 for Dwarves, 40 otherwise). */
export function dwarvenMiningStoreRequiredLevel(save: PlayerSave): number {
  return save.raceId === DWARF_RACE_ID ? 35 : 40
}

/** Apply race gold percent (floored). Used for action and combat gold only. */
export function applyRaceGoldGain(
  db: GameDatabase,
  save: PlayerSave,
  baseGold: number,
): number {
  const amount = Math.max(0, Number(baseGold) || 0)
  if (amount <= 0) return 0
  return Math.floor(amount * raceGoldGainMultiplier(db, save))
}

export function raceBypassesForcedHostilityAt(
  db: GameDatabase,
  save: PlayerSave,
  locationId: string,
): boolean {
  const race = raceById(db, save.raceId)
  if (!race) return false
  return parseIdList(race['Hostility Immunity Location IDs']).includes(locationId)
}

export function raceBonusSummaryLines(db: GameDatabase, raceId: string): string[] {
  const lines: string[] = []
  for (const bonus of raceBonusesFor(db, raceId)) {
    const value = Number(bonus['Bonus Value'] ?? 0)
    if (!Number.isFinite(value) || value === 0) continue
    if (bonus['Bonus Type'] === 'skill_drop_chance_percent' && bonus['Reference ID']) {
      const skill =
        db.Skills.find((row) => row['Skill ID'] === bonus['Reference ID'])?.['Display Name'] ??
        'skill'
      lines.push(`+${value}% ${skill} drop chance`)
      continue
    }
    if (bonus['Bonus Type'] === 'max_hp_percent') {
      lines.push(`+${value}% maximum HP`)
      continue
    }
    if (bonus['Bonus Type'] === 'gold_gain_percent') {
      lines.push(`+${value}% gold from enemies and actions`)
    }
  }
  const race = raceById(db, raceId)
  for (const locationId of parseIdList(race?.['Hostility Immunity Location IDs'])) {
    const location =
      db.Locations.find((row) => row['Location ID'] === locationId)?.['Display Name'] ??
      locationId
    lines.push(`Welcome at ${location} (no forced hostility)`)
  }
  if (raceId === DWARF_RACE_ID) {
    lines.push('Dwarven Mining Store at Mining level 35')
  }
  return lines
}

/**
 * Grant a race's starting item kit. Idempotent only in the sense that callers
 * should invoke this when first selecting a race (not on every race change).
 */
export function grantRaceStartingItems(
  db: GameDatabase,
  save: PlayerSave,
  raceId: string,
): PlayerSave {
  let next = save
  for (const row of raceStartingItems(db, raceId)) {
    const qty = Math.max(0, Math.floor(Number(row.Quantity) || 0))
    if (qty <= 0) continue
    next = addItemToInventory(next, row['Item ID'], qty)
  }
  return next
}
