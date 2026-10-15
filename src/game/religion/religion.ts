import { configNumber, configString } from '../activity/gathering'
import type { GameDatabase, ReligionBonusRow, ReligionRow } from '../data/types'
import type { PlayerSave } from '../save/types'
import { totalLevel } from '../skills/totals'

export const RELIGION_CHOOSE_TOTAL_LEVEL = 100
export const RELIGION_CHANGE_GOLD_BASE_KEY = 'religion_change_gold_base'
export const RELIGION_CHANGE_GOLD_GROWTH_KEY = 'religion_change_gold_growth'
export const RELIGION_CHANGE_GOLD_CAP_KEY = 'religion_change_gold_cap'
export const RELIGION_CHANGE_COOLDOWN_MS_KEY = 'religion_change_cooldown_ms'
export const RELIGION_CHOOSE_LOCATION_ID_KEY = 'religion_choose_location_id'
export const TEMPLE_LOCATION_ID_FALLBACK = 'LOC-0036'
/** PLACEHOLDER: Economy will replace. Base gold at total level 100. */
export const RELIGION_CHANGE_GOLD_BASE_FALLBACK = 1000
/**
 * PLACEHOLDER: Economy will replace. Same IEEE double as Config
 * `religion_change_gold_growth` (`50^(1/900)`), so level 1000 ~= 50000.
 */
export const RELIGION_CHANGE_GOLD_GROWTH_FALLBACK = 1.0043561527973446
/** PLACEHOLDER: Economy will replace. 0 or null on the Config row means no cap. */
export const RELIGION_CHANGE_GOLD_CAP_FALLBACK = 50000
export const RELIGION_CHANGE_COOLDOWN_MS_FALLBACK = 7 * 24 * 60 * 60 * 1000

export function religions(db: GameDatabase): ReligionRow[] {
  return [...db.Religions].sort(
    (a, b) =>
      (a['Sort Order'] ?? 0) - (b['Sort Order'] ?? 0) ||
      a['Display Name'].localeCompare(b['Display Name']),
  )
}

export function religionById(
  db: GameDatabase,
  religionId: string | null | undefined,
): ReligionRow | undefined {
  if (!religionId) return undefined
  return db.Religions.find((row) => row['Religion ID'] === religionId)
}

export function religionDisplayName(
  db: GameDatabase,
  religionId: string | null | undefined,
): string | null {
  return religionById(db, religionId)?.['Display Name'] ?? null
}

export function religionBonusesFor(
  db: GameDatabase,
  religionId: string | null | undefined,
): ReligionBonusRow[] {
  if (!religionId) return []
  return db.ReligionBonuses.filter(
    (row) => row['Religion ID'] === religionId && row.Status !== 'Needs Data',
  )
}

function matchingBonusPercent(
  bonuses: Array<{
    'Bonus Type': string
    'Reference ID': string | null
    'Bonus Value': number
  }>,
  bonusType: string,
  referenceId: string | null = null,
): number {
  let total = 0
  for (const bonus of bonuses) {
    if (bonus['Bonus Type'] !== bonusType) continue
    if (referenceId != null && bonus['Reference ID'] !== referenceId) continue
    if (referenceId == null && bonus['Reference ID'] != null) continue
    const value = Number(bonus['Bonus Value'] ?? 0)
    if (Number.isFinite(value)) total += value
  }
  return total
}

/** Sum of matching percent bonuses on one faith (e.g. two +5 rows → 10). */
function totalReligionBonusPercent(
  db: GameDatabase,
  religionId: string | null | undefined,
  bonusType: string,
  referenceId: string | null = null,
): number {
  return matchingBonusPercent(religionBonusesFor(db, religionId), bonusType, referenceId)
}

/**
 * Race bonus fallback, inlined so this module does not import `races.ts`
 * (that file imports rewards, which imports religion).
 */
function totalRaceBonusPercent(
  db: GameDatabase,
  raceId: string | null | undefined,
  bonusType: string,
  referenceId: string | null = null,
): number {
  if (!raceId) return 0
  const bonuses = db.RaceBonuses.filter(
    (row) => row['Race ID'] === raceId && row.Status !== 'Needs Data',
  )
  return matchingBonusPercent(bonuses, bonusType, referenceId)
}

export function religionSkillDropChanceBonusPercent(
  db: GameDatabase,
  save: PlayerSave,
  skillId: string,
): number {
  return totalReligionBonusPercent(db, save.religionId, 'skill_drop_chance_percent', skillId)
}

export function religionMaxHpMultiplier(db: GameDatabase, save: PlayerSave): number {
  return 1 + totalReligionBonusPercent(db, save.religionId, 'max_hp_percent') / 100
}

export function religionGoldGainMultiplier(db: GameDatabase, save: PlayerSave): number {
  return 1 + totalReligionBonusPercent(db, save.religionId, 'gold_gain_percent') / 100
}

/**
 * Faith bonus if a faith is chosen, otherwise the race bonus. Never both for
 * one bonus type: following a faith replaces the race +5% entirely.
 */
export function alignmentSkillDropChanceBonusPercent(
  db: GameDatabase,
  save: PlayerSave,
  skillId: string,
): number {
  if (save.religionId) return religionSkillDropChanceBonusPercent(db, save, skillId)
  return totalRaceBonusPercent(db, save.raceId, 'skill_drop_chance_percent', skillId)
}

export function alignmentMaxHpMultiplier(db: GameDatabase, save: PlayerSave): number {
  if (save.religionId) return religionMaxHpMultiplier(db, save)
  return 1 + totalRaceBonusPercent(db, save.raceId, 'max_hp_percent') / 100
}

export function alignmentGoldGainMultiplier(db: GameDatabase, save: PlayerSave): number {
  if (save.religionId) return religionGoldGainMultiplier(db, save)
  return 1 + totalRaceBonusPercent(db, save.raceId, 'gold_gain_percent') / 100
}

export function applyAlignmentGoldGain(
  db: GameDatabase,
  save: PlayerSave,
  baseGold: number,
): number {
  const amount = Math.max(0, Number(baseGold) || 0)
  if (amount <= 0) return 0
  return Math.floor(amount * alignmentGoldGainMultiplier(db, save))
}

export function religionBonusSummaryLines(db: GameDatabase, religionId: string): string[] {
  const lines: string[] = []
  for (const bonus of religionBonusesFor(db, religionId)) {
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
  return lines
}

export function religionChooseLocationId(db: GameDatabase): string {
  return configString(db, RELIGION_CHOOSE_LOCATION_ID_KEY, TEMPLE_LOCATION_ID_FALLBACK)
}

export function religionChangeCooldownMs(db: GameDatabase): number {
  return configNumber(db, RELIGION_CHANGE_COOLDOWN_MS_KEY, RELIGION_CHANGE_COOLDOWN_MS_FALLBACK)
}

export function religionChooseUnlocked(save: PlayerSave): boolean {
  return totalLevel(save) >= RELIGION_CHOOSE_TOTAL_LEVEL
}

/**
 * PLACEHOLDER exponential curve for Economy to replace.
 *
 * First pick (no current faith) is free. Later changes cost
 * `min(floor(round(base * growth^(totalLevel-100)) / 50) * 50, cap)`.
 * Round is whole gold (JS `Math.round`) before the floor-to-50.
 * `growth^n` is `exp(n * ln(growth))` so TS and Dart match.
 * Cap 0 or null means no cap; missing Config uses 50000.
 */
export function religionChangeGoldCost(db: GameDatabase, save: PlayerSave): number {
  if (!save.religionId) return 0
  const base = configNumber(db, RELIGION_CHANGE_GOLD_BASE_KEY, RELIGION_CHANGE_GOLD_BASE_FALLBACK)
  const growth = configNumber(
    db,
    RELIGION_CHANGE_GOLD_GROWTH_KEY,
    RELIGION_CHANGE_GOLD_GROWTH_FALLBACK,
  )
  const exponent = totalLevel(save) - RELIGION_CHOOSE_TOTAL_LEVEL
  const raw = base * Math.exp(exponent * Math.log(growth))
  if (!Number.isFinite(raw) || raw <= 0) {
    const cap = religionChangeGoldCap(db)
    if (!Number.isFinite(raw) && cap != null) return cap
    return 0
  }
  const wholeGold = Math.round(raw)
  let cost = Math.max(0, Math.floor(wholeGold / 50) * 50)
  const cap = religionChangeGoldCap(db)
  if (cap != null) cost = Math.min(cost, cap)
  return cost
}

/** Positive cap, or null when Config is 0/null (uncapped). Missing row → 50000. */
export function religionChangeGoldCap(db: GameDatabase): number | null {
  const row = db.Config.find((entry) => entry.Key === RELIGION_CHANGE_GOLD_CAP_KEY)
  if (!row) return RELIGION_CHANGE_GOLD_CAP_FALLBACK
  const value = row.Value
  if (value == null) return null
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) return null
  return value
}

export function religionChangeReadyAt(db: GameDatabase, save: PlayerSave): number | null {
  if (save.religionChangedAt == null) return null
  const at = Number(save.religionChangedAt)
  if (!Number.isFinite(at)) return null
  return at + religionChangeCooldownMs(db)
}

export function religionIdForTitleCosmetic(
  db: GameDatabase,
  cosmeticId: string | null | undefined,
): string | null {
  if (!cosmeticId) return null
  return (
    db.Religions.find((row) => row['Title Cosmetic ID'] === cosmeticId)?.['Religion ID'] ?? null
  )
}

/** Faith titles stay owned after a switch but can only be equipped while following that faith. */
export function isFaithTitleLocked(
  db: GameDatabase,
  save: PlayerSave,
  cosmeticId: string | null | undefined,
): boolean {
  const faithId = religionIdForTitleCosmetic(db, cosmeticId)
  if (!faithId) return false
  return save.religionId !== faithId
}
