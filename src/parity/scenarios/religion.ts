import { chooseReligion } from '../../game/religion/chooseReligion'
import {
  alignmentGoldGainMultiplier,
  alignmentSkillDropChanceBonusPercent,
  applyAlignmentGoldGain,
  religionBonusSummaryLines,
  religionBonusesFor,
  religionById,
  religionChangeGoldCost,
  religionDisplayName,
  religions,
} from '../../game/religion/religion'
import { assignRace } from '../../game/races/assignRace'
import type { PlayerSave } from '../../game/save/types'
import { totalLevel } from '../../game/skills/totals'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import { contentDatabase } from './contentDatabase'
import { asJson, baseSave } from './saveFixtures'

const REL_IDS = ['REL-0001', 'REL-0002', 'REL-0003', 'REL-0004', 'REL-0005', 'REL-0006', 'REL-0007']
const SKILL_IDS = ['SKL-0001', 'SKL-0002', 'SKL-0003', 'SKL-0004', 'SKL-0005', 'SKL-0006', 'SKL-0007']
const GOLD_AMOUNTS = [0, 1, 7, 100, 12.5, -20]
const NOW_MS = Date.parse('2026-10-15T00:00:00.000Z')
const WEEK_MS = 7 * 24 * 60 * 60 * 1000
const TEMPLE = 'LOC-0036'

function withTotalLevel(save: PlayerSave, target: number): PlayerSave {
  const bump = target - totalLevel(save)
  if (bump <= 0) return save
  const [first, ...rest] = save.skills
  return { ...save, skills: [{ ...first, level: first.level + bump }, ...rest] }
}

function atTemple(save: PlayerSave, level = 100): PlayerSave {
  return { ...withTotalLevel(save, level), currentLocationId: TEMPLE, gold: 100_000 }
}

function withSave(save: PlayerSave, extra: Record<string, JsonValue> = {}): JsonValue {
  return { source: 'content', save: asJson(save), ...extra }
}

function chooseJson(
  result: ReturnType<typeof chooseReligion>,
): JsonValue {
  if (!result.ok) return { ok: false, reason: result.reason }
  return {
    ok: true,
    goldCost: result.goldCost,
    religionId: result.save.religionId,
    religionChangeCount: result.save.religionChangeCount,
    religionHistory: result.save.religionHistory,
    gold: result.save.gold,
    religionChangedAt: result.save.religionChangedAt,
    unlockedTitles: result.save.cosmetics.unlocked.filter((id) => /^COS-001[3-9]$/.test(id)),
    equippedTitle: result.save.cosmetics.equipped['CSLOT-0003'] ?? null,
    acolyte: result.save.achievements.some((row) => row.achievementId === 'ACH-0050' && row.unlocked),
    theologian: result.save.achievements.some((row) => row.achievementId === 'ACH-0051' && row.unlocked),
  }
}

export const religionScenarios: ParityScenario[] = [
  scenario('religion/catalog', 'sorted', { source: 'content' }, () => {
    const db = contentDatabase()
    return {
      order: religions(db).map((row) => row['Religion ID']),
      names: religions(db).map((row) => religionDisplayName(db, row['Religion ID'])),
      gods: religions(db).map((row) => row.God),
      titleKeys: religions(db).map((row) => {
        const cosmetic = db.Cosmetics.find((c) => c['Cosmetic ID'] === row['Title Cosmetic ID'])
        return db.Items.find((item) => item['Item ID'] === cosmetic?.['Item ID'])?.['Internal Key'] ?? null
      }),
      missing: religionDisplayName(db, 'REL-9999'),
      nullId: religionDisplayName(db, null),
      foundById: REL_IDS.map((id) => religionById(db, id)?.['Religion ID'] ?? null),
    }
  }),

  ...REL_IDS.map((religionId) =>
    scenario(
      'religion/bonuses',
      religionId.toLowerCase(),
      withSave({ ...baseSave(contentDatabase()), religionId }, { religionId }),
      () => {
        const db = contentDatabase()
        const save = { ...baseSave(db), religionId }
        return {
          bonusIds: religionBonusesFor(db, religionId).map((row) => row['Religion Bonus ID']),
          summary: religionBonusSummaryLines(db, religionId),
          skillDropChance: SKILL_IDS.map((skillId) =>
            alignmentSkillDropChanceBonusPercent(db, save, skillId),
          ),
          goldGain: alignmentGoldGainMultiplier(db, save),
          appliedGold: GOLD_AMOUNTS.map((amount) => applyAlignmentGoldGain(db, save, amount)),
        } as unknown as JsonValue
      },
    ),
  ),

  scenario('religion/alignment', 'no-faith-wood-elf', { source: 'content' }, () => {
    const db = contentDatabase()
    const assigned = assignRace(db, baseSave(db), 'RACE-0002')
    if (!assigned.ok) return { ok: false, reason: assigned.reason } as JsonValue
    const save = assigned.save
    return {
      hunting: alignmentSkillDropChanceBonusPercent(db, save, 'SKL-0005'),
      woodcutting: alignmentSkillDropChanceBonusPercent(db, save, 'SKL-0006'),
      gold: applyAlignmentGoldGain(db, save, 100),
    }
  }),

  scenario('religion/alignment', 'faith-replaces-race', { source: 'content' }, () => {
    const db = contentDatabase()
    const assigned = assignRace(db, baseSave(db), 'RACE-0002')
    if (!assigned.ok) return { ok: false, reason: assigned.reason } as JsonValue
    const save = { ...assigned.save, religionId: 'REL-0001' }
    return {
      hunting: alignmentSkillDropChanceBonusPercent(db, save, 'SKL-0005'),
      woodcutting: alignmentSkillDropChanceBonusPercent(db, save, 'SKL-0006'),
      gold: applyAlignmentGoldGain(db, save, 100),
    }
  }),

  scenario('religion/alignment', 'null-null', { source: 'content' }, () => {
    const db = contentDatabase()
    const save = baseSave(db)
    return {
      hunting: alignmentSkillDropChanceBonusPercent(db, save, 'SKL-0005'),
      gold: applyAlignmentGoldGain(db, save, 100),
    }
  }),

  scenario('religion/cost', 'boundaries', { source: 'content' }, () => {
    const db = contentDatabase()
    const none = atTemple(baseSave(db), 100)
    const following = { ...none, religionId: 'REL-0001' }
    return {
      firstPick: religionChangeGoldCost(db, none),
      at100: religionChangeGoldCost(db, following),
      at104: religionChangeGoldCost(db, withTotalLevel(following, 104)),
      at105: religionChangeGoldCost(db, withTotalLevel(following, 105)),
      at250: religionChangeGoldCost(db, withTotalLevel(following, 250)),
      at500: religionChangeGoldCost(db, withTotalLevel(following, 500)),
      at1000: religionChangeGoldCost(db, withTotalLevel(following, 1000)),
    }
  }),

  scenario('religion/choose', 'first-pick-free', { source: 'content', nowMs: NOW_MS }, () => {
    const db = contentDatabase()
    return chooseJson(chooseReligion(db, atTemple(baseSave(db), 100), 'REL-0001', NOW_MS))
  }),

  scenario('religion/choose', 'level-99-refused', { source: 'content', nowMs: NOW_MS }, () => {
    const db = contentDatabase()
    return chooseJson(chooseReligion(db, atTemple(baseSave(db), 99), 'REL-0001', NOW_MS))
  }),

  scenario('religion/choose', 'same-faith-retry', { source: 'content', nowMs: NOW_MS }, () => {
    const db = contentDatabase()
    const first = chooseReligion(db, atTemple(baseSave(db), 100), 'REL-0001', NOW_MS)
    if (!first.ok) return chooseJson(first)
    return chooseJson(chooseReligion(db, first.save, 'REL-0001', NOW_MS + 1000))
  }),

  scenario('religion/choose', 'cooldown-then-change', { source: 'content', nowMs: NOW_MS }, () => {
    const db = contentDatabase()
    const first = chooseReligion(db, atTemple(baseSave(db), 100), 'REL-0001', NOW_MS)
    if (!first.ok) return { first: chooseJson(first) } as JsonValue
    const blocked = chooseReligion(db, first.save, 'REL-0002', NOW_MS + 1000)
    const changed = chooseReligion(db, first.save, 'REL-0002', NOW_MS + WEEK_MS)
    const retried = changed.ok ? chooseReligion(db, changed.save, 'REL-0002', NOW_MS + WEEK_MS + 1) : changed
    return {
      first: chooseJson(first),
      blocked: chooseJson(blocked),
      changed: chooseJson(changed),
      retried: chooseJson(retried),
    }
  }),

  scenario('religion/choose', 'theologian-once', { source: 'content', nowMs: NOW_MS }, () => {
    const db = contentDatabase()
    let next = atTemple(baseSave(db), 100)
    const steps: JsonValue[] = []
    for (const [index, religionId] of REL_IDS.entries()) {
      const result = chooseReligion(db, { ...next, gold: 100_000 }, religionId, NOW_MS + index * WEEK_MS)
      steps.push(chooseJson(result))
      if (!result.ok) break
      next = result.save
    }
    const again = chooseReligion(db, next, 'REL-0001', NOW_MS + REL_IDS.length * WEEK_MS)
    return { steps, again: chooseJson(again) }
  }),
]
