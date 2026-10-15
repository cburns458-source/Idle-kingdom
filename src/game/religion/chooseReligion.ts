import { syncProgressionMeta } from '../achievements/progress'
import { grantCosmetic } from '../cosmetics/cosmetics'
import type { GameDatabase } from '../data/types'
import { withRecalculatedVitals } from '../equipment/vitals'
import { formatDurationRemaining } from '../quests/miniquests'
import { TITLE_COSMETIC_SLOT_ID, type PlayerSave } from '../save/types'
import {
  isFaithTitleLocked,
  religionById,
  religionChangeGoldCost,
  religionChangeReadyAt,
  religionChooseLocationId,
  religionChooseUnlocked,
} from './religion'

export type ChooseReligionResult =
  | { ok: true; save: PlayerSave; goldCost: number }
  | { ok: false; reason: string }

function withReligionHistory(save: PlayerSave, religionId: string): string[] {
  const current = Array.isArray(save.religionHistory) ? save.religionHistory : []
  if (current.includes(religionId)) return current
  return [...current, religionId]
}

function unequipLockedFaithTitle(db: GameDatabase, save: PlayerSave): PlayerSave {
  const equippedId = save.cosmetics?.equipped?.[TITLE_COSMETIC_SLOT_ID] ?? null
  if (!equippedId || !isFaithTitleLocked(db, save, equippedId)) return save
  return {
    ...save,
    cosmetics: {
      ...save.cosmetics,
      unlocked: save.cosmetics?.unlocked ?? [],
      equipped: { ...save.cosmetics?.equipped, [TITLE_COSMETIC_SLOT_ID]: null },
    },
  }
}

/**
 * Pick or change faith at the Temple.
 *
 * Same-faith retry is a no-op (no gold, no cooldown reset) so a queued hosted
 * command cannot double-charge. First pick is free; later changes cost gold
 * from `religionChangeGoldCost` and share a 7-day server-clock cooldown.
 */
export function chooseReligion(
  db: GameDatabase,
  save: PlayerSave,
  religionId: string,
  nowMs: number = Date.now(),
): ChooseReligionResult {
  if (save.religionId === religionId) {
    return { ok: true, save, goldCost: 0 }
  }

  const religion = religionById(db, religionId)
  if (!religion) return { ok: false, reason: 'Unknown faith.' }

  const templeId = religionChooseLocationId(db)
  if (save.currentLocationId !== templeId) {
    return { ok: false, reason: 'Choose a faith at the Temple.' }
  }
  if (!religionChooseUnlocked(save)) {
    return { ok: false, reason: 'Reach total level 100 to choose a faith.' }
  }

  const readyAt = religionChangeReadyAt(db, save)
  if (readyAt != null && nowMs < readyAt) {
    return {
      ok: false,
      reason: `Wait ${formatDurationRemaining(readyAt - nowMs)}.`,
    }
  }

  const goldCost = religionChangeGoldCost(db, save)
  if (save.gold < goldCost) {
    return { ok: false, reason: `Need ${goldCost.toLocaleString()} gold.` }
  }

  let next: PlayerSave = {
    ...save,
    gold: save.gold - goldCost,
    religionId,
    religionChangedAt: nowMs,
    religionChangeCount: Math.max(0, Math.floor(Number(save.religionChangeCount) || 0)) + 1,
    religionHistory: withReligionHistory(save, religionId),
  }

  const titleId = religion['Title Cosmetic ID']
  if (typeof titleId === 'string' && titleId.length > 0) {
    next = grantCosmetic(next, titleId).save
  }
  next = unequipLockedFaithTitle(db, next)
  next = withRecalculatedVitals(db, next)
  next = syncProgressionMeta(db, next, nowMs)
  return { ok: true, save: next, goldCost }
}
