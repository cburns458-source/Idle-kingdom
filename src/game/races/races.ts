import { addItemToInventory } from '../activity/rewards'
import type {
  GameDatabase,
  RaceBonusRow,
  RaceRow,
  RaceStartingItemRow,
} from '../data/types'
import type { PlayerSave } from '../save/types'

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

export function raceSkillXpMultiplier(
  db: GameDatabase,
  save: PlayerSave,
  skillId: string,
): number {
  const percent = totalBonusPercent(db, save, 'skill_xp_percent', skillId)
  return 1 + percent / 100
}

export function raceCombatDamageMultiplier(db: GameDatabase, save: PlayerSave): number {
  return 1 + totalBonusPercent(db, save, 'combat_damage_percent') / 100
}

export function raceMaxHpMultiplier(db: GameDatabase, save: PlayerSave): number {
  return 1 + totalBonusPercent(db, save, 'max_hp_percent') / 100
}

export function raceGoldGainMultiplier(db: GameDatabase, save: PlayerSave): number {
  return 1 + totalBonusPercent(db, save, 'gold_gain_percent') / 100
}

/** Apply race skill XP percent (floored). */
export function applyRaceSkillXp(
  db: GameDatabase,
  save: PlayerSave,
  skillId: string,
  baseXp: number,
): number {
  const amount = Math.max(0, Number(baseXp) || 0)
  if (amount <= 0) return 0
  return Math.floor(amount * raceSkillXpMultiplier(db, save, skillId))
}

/** Apply race gold percent (floored). */
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
    if (bonus['Bonus Type'] === 'skill_xp_percent' && bonus['Reference ID']) {
      const skill =
        db.Skills.find((row) => row['Skill ID'] === bonus['Reference ID'])?.['Display Name'] ??
        'skill'
      lines.push(`+${value}% ${skill} XP`)
      continue
    }
    if (bonus['Bonus Type'] === 'max_hp_percent') {
      lines.push(`+${value}% maximum HP`)
      continue
    }
    if (bonus['Bonus Type'] === 'combat_damage_percent') {
      lines.push(`+${value}% combat damage`)
      continue
    }
    if (bonus['Bonus Type'] === 'gold_gain_percent') {
      lines.push(`+${value}% gold gains`)
    }
  }
  const race = raceById(db, raceId)
  for (const locationId of parseIdList(race?.['Hostility Immunity Location IDs'])) {
    const location =
      db.Locations.find((row) => row['Location ID'] === locationId)?.['Display Name'] ??
      locationId
    lines.push(`Welcome at ${location} (no forced hostility)`)
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
