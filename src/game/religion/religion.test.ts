import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { equipCosmetic } from '../cosmetics/cosmetics'
import { prepareDatabase } from '../data/loadDatabase'
import { assignRace } from '../races/assignRace'
import { raceSkillDropChanceBonusPercent, applyRaceGoldGain } from '../races/races'
import { createNewSave, parseSave } from '../save/saveStore'
import { SAVE_VERSION, TITLE_COSMETIC_SLOT_ID, type PlayerSave } from '../save/types'
import { totalLevel } from '../skills/totals'
import { chooseReligion } from './chooseReligion'
import {
  alignmentGoldGainMultiplier,
  alignmentSkillDropChanceBonusPercent,
  applyAlignmentGoldGain,
    RELIGION_CHOOSE_TOTAL_LEVEL,
    religionChangeGoldCost,
    religionChangeGoldSettings,
    religions,
  } from './religion'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

const NOW_MS = Date.parse('2026-10-15T00:00:00.000Z')
const WEEK_MS = 7 * 24 * 60 * 60 * 1000
const TEMPLE = 'LOC-0036'
const WOODCUTTING_FAITH = 'REL-0001'
const HUNTING_FAITH = 'REL-0002'
const GOLD_FAITH = 'REL-0005'
const WOODCUTTING_TITLE = 'COS-0013'
const HUNTING_TITLE = 'COS-0014'

function withTotalLevel(save: PlayerSave, target: number): PlayerSave {
  const bump = target - totalLevel(save)
  if (bump <= 0) return save
  const [first, ...rest] = save.skills
  return { ...save, skills: [{ ...first, level: first.level + bump }, ...rest] }
}

function atTemple(save: PlayerSave, level = RELIGION_CHOOSE_TOTAL_LEVEL): PlayerSave {
  return { ...withTotalLevel(save, level), currentLocationId: TEMPLE, gold: save.gold + 100_000 }
}

describe('religion', () => {
  const { launch } = prepareDatabase(rawDatabase)

  it('loads a v63 save with no faith and keeps the race bonus', () => {
    const assigned = assignRace(launch, createNewSave(launch, NOW_MS), 'RACE-0002')
    expect(assigned.ok).toBe(true)
    if (!assigned.ok) return
    const raw = JSON.parse(JSON.stringify(assigned.save)) as Record<string, unknown>
    delete raw.religionId
    delete raw.religionChangedAt
    delete raw.religionChangeCount
    delete raw.religionHistory
    raw.saveVersion = 63
    const loaded = parseSave(raw, NOW_MS)
    expect(loaded.saveVersion).toBe(SAVE_VERSION)
    expect(loaded.religionId).toBeNull()
    expect(loaded.religionChangeCount).toBe(0)
    expect(loaded.religionHistory).toEqual([])
    expect(loaded.raceId).toBe('RACE-0002')
    expect(alignmentSkillDropChanceBonusPercent(launch, loaded, 'SKL-0005')).toBe(5)
  })

  it('loads seven Launch faiths, one per race bonus type', () => {
    const rows = religions(launch)
    expect(rows.map((row) => row['Religion ID'])).toEqual([
      'REL-0001',
      'REL-0002',
      'REL-0003',
      'REL-0004',
      'REL-0005',
      'REL-0006',
      'REL-0007',
    ])
    expect(rows.map((row) => row['Display Name'])).toEqual([
      'Vaelithra',
      'Khavessa',
      'Nymorai',
      'Drazhkar',
      'Veyrathi',
      'Korvethan',
      'Elyndara',
    ])
    expect(rows.map((row) => row.God)).toEqual([
      'Oruveth',
      'Theryvak',
      'Ulvaryn',
      'Azhurak',
      'Zorvael',
      'Gorveth',
      'Saelun',
    ])
    expect(
      rows.map((row) => {
        const cosmetic = launch.Cosmetics.find((c) => c['Cosmetic ID'] === row['Title Cosmetic ID'])
        return launch.Items.find((item) => item['Item ID'] === cosmetic?.['Item ID'])?.['Internal Key']
      }),
    ).toEqual([
      'cosmetic_faith_vaelithra_title',
      'cosmetic_faith_khavessa_title',
      'cosmetic_faith_nymorai_title',
      'cosmetic_faith_drazhkar_title',
      'cosmetic_faith_veyrathi_title',
      'cosmetic_faith_korvethan_title',
      'cosmetic_faith_elyndara_title',
    ])
    expect(rows.map((row) => row.Description)).toEqual([
      'Followers of Oruveth fell timber as stewards, knowing every stump makes room for the forest to rise again.',
      'Theryvak teaches the patience of the stalker and respect for the quarry: take only what the wild can spare.',
      "Sailors and coastal folk pray to Ulvaryn, keeper of the deep, who gives back the sea's bounty and its lost things.",
      'Azhurak honours those who endure, for discipline breeds strength and victory is only earned through struggle.',
      'Zorvael holds that wealth is held in trust, and that generosity and wise dealing are sacred duties.',
      'Gorveth guards the stone and its buried riches, and gives the secrets of the deep earth only to honest labour.',
      'Saelun turns the seasons and renews the tilled land, blessing herb, crop and orchard alike.',
    ])
    expect(
      rows.map((row) => {
        const cosmetic = launch.Cosmetics.find((c) => c['Cosmetic ID'] === row['Title Cosmetic ID'])
        return launch.Items.find((item) => item['Item ID'] === cosmetic?.['Item ID'])?.['Display Name']
      }),
    ).toEqual(['Oruvani', 'Khareth', 'Nymorathen', 'Drazhari', 'Veyrathel', 'Korvathi', 'Elyndri'])
  })

  it('uses the race bonus when no faith is chosen, and never stacks both', () => {
    const assigned = assignRace(launch, createNewSave(launch, NOW_MS), 'RACE-0002')
    expect(assigned.ok).toBe(true)
    if (!assigned.ok) return
    const noFaith = assigned.save
    expect(raceSkillDropChanceBonusPercent(launch, noFaith, 'SKL-0005')).toBe(5)
    expect(alignmentSkillDropChanceBonusPercent(launch, noFaith, 'SKL-0005')).toBe(5)
    expect(alignmentSkillDropChanceBonusPercent(launch, noFaith, 'SKL-0006')).toBe(0)

    const ready = atTemple(noFaith)
    const picked = chooseReligion(launch, ready, WOODCUTTING_FAITH, NOW_MS)
    expect(picked.ok).toBe(true)
    if (!picked.ok) return
    expect(alignmentSkillDropChanceBonusPercent(launch, picked.save, 'SKL-0006')).toBe(5)
    expect(alignmentSkillDropChanceBonusPercent(launch, picked.save, 'SKL-0005')).toBe(0)
    expect(raceSkillDropChanceBonusPercent(launch, picked.save, 'SKL-0005')).toBe(5)
  })

  it('replaces goblin gold gain with the gold faith, and leaves race gold when unchosen', () => {
    const assigned = assignRace(launch, createNewSave(launch, NOW_MS), 'RACE-0005')
    expect(assigned.ok).toBe(true)
    if (!assigned.ok) return
    expect(applyAlignmentGoldGain(launch, assigned.save, 100)).toBe(105)
    expect(applyRaceGoldGain(launch, assigned.save, 100)).toBe(105)

    const picked = chooseReligion(launch, atTemple(assigned.save), WOODCUTTING_FAITH, NOW_MS)
    expect(picked.ok).toBe(true)
    if (!picked.ok) return
    expect(applyAlignmentGoldGain(launch, picked.save, 100)).toBe(100)
    expect(alignmentGoldGainMultiplier(launch, picked.save)).toBe(1)

    const afterCooldown = chooseReligion(launch, { ...picked.save, gold: 100_000 }, GOLD_FAITH, NOW_MS + WEEK_MS)
    expect(afterCooldown.ok).toBe(true)
    if (!afterCooldown.ok) return
    expect(applyAlignmentGoldGain(launch, afterCooldown.save, 100)).toBe(105)
  })

  it('reads the multiplier and rounding step from one Config value', () => {
    expect(launch.Config.find((row) => row.Key === 'religion_change_gold')?.Value).toBe('10:50')
    expect(religionChangeGoldSettings(launch)).toEqual({ multiplier: 10, roundingStep: 50 })
  })

  it('refuses total level 99 and charges nothing on the first pick at 100', () => {
    const save = atTemple(createNewSave(launch, NOW_MS), 99)
    const refused = chooseReligion(launch, save, WOODCUTTING_FAITH, NOW_MS)
    expect(refused.ok).toBe(false)
    if (refused.ok) return
    expect(refused.reason).toMatch(/100/)

    const ready = atTemple(createNewSave(launch, NOW_MS), 100)
    const goldBefore = ready.gold
    const first = chooseReligion(launch, ready, WOODCUTTING_FAITH, NOW_MS)
    expect(first.ok).toBe(true)
    if (!first.ok) return
    expect(first.goldCost).toBe(0)
    expect(first.save.gold).toBe(goldBefore)
    expect(first.save.religionId).toBe(WOODCUTTING_FAITH)
    expect(first.save.achievements.some((row) => row.achievementId === 'ACH-0050' && row.unlocked)).toBe(
      true,
    )
  })

  it('costs 1000, 2500, 5000 and 10000 gold at total levels 100, 250, 500 and 1000', () => {
    const first = chooseReligion(launch, atTemple(createNewSave(launch, NOW_MS), 100), WOODCUTTING_FAITH, NOW_MS)
    expect(first.ok).toBe(true)
    if (!first.ok) return
    expect(religionChangeGoldCost(launch, first.save)).toBe(1000)
    expect(religionChangeGoldCost(launch, withTotalLevel(first.save, 250))).toBe(2500)
    expect(religionChangeGoldCost(launch, withTotalLevel(first.save, 500))).toBe(5000)
    expect(religionChangeGoldCost(launch, withTotalLevel(first.save, 1000))).toBe(10000)

    const changed = chooseReligion(
      launch,
      { ...withTotalLevel(first.save, 250), gold: 2500 },
      HUNTING_FAITH,
      NOW_MS + WEEK_MS,
    )
    expect(changed.ok).toBe(true)
    if (!changed.ok) return
    expect(changed.goldCost).toBe(2500)
    expect(changed.save.gold).toBe(0)
  })

  it('rounds 104 down to 1000 gold and 105 up to 1050 gold', () => {
    const first = chooseReligion(launch, atTemple(createNewSave(launch, NOW_MS), 100), WOODCUTTING_FAITH, NOW_MS)
    expect(first.ok).toBe(true)
    if (!first.ok) return
    expect(religionChangeGoldCost(launch, withTotalLevel(first.save, 104))).toBe(1000)
    expect(religionChangeGoldCost(launch, withTotalLevel(first.save, 105))).toBe(1050)
  })

  it('does not double-charge or reset cooldown on a same-faith retry', () => {
    const first = chooseReligion(launch, atTemple(createNewSave(launch, NOW_MS), 100), WOODCUTTING_FAITH, NOW_MS)
    expect(first.ok).toBe(true)
    if (!first.ok) return
    const retry = chooseReligion(launch, first.save, WOODCUTTING_FAITH, NOW_MS + 1_000)
    expect(retry.ok).toBe(true)
    if (!retry.ok) return
    expect(retry.goldCost).toBe(0)
    expect(retry.save.gold).toBe(first.save.gold)
    expect(retry.save.religionChangedAt).toBe(first.save.religionChangedAt)
    expect(retry.save.religionChangeCount).toBe(first.save.religionChangeCount)

    const tooSoon = chooseReligion(launch, first.save, HUNTING_FAITH, NOW_MS + 1_000)
    expect(tooSoon.ok).toBe(false)
  })

  it('grants Acolyte once and Theologian once after all seven faiths', () => {
    let next = atTemple(createNewSave(launch, NOW_MS), 100)
    const ids = religions(launch).map((row) => row['Religion ID'])
    for (const [index, religionId] of ids.entries()) {
      const at = NOW_MS + index * WEEK_MS
      const result = chooseReligion(launch, { ...next, gold: 100_000 }, religionId, at)
      expect(result.ok).toBe(true)
      if (!result.ok) return
      next = result.save
    }
    const acolyte = next.achievements.filter((row) => row.achievementId === 'ACH-0050' && row.unlocked)
    const theologian = next.achievements.filter((row) => row.achievementId === 'ACH-0051' && row.unlocked)
    expect(acolyte).toHaveLength(1)
    expect(theologian).toHaveLength(1)
    const again = chooseReligion(launch, next, WOODCUTTING_FAITH, NOW_MS + 7 * WEEK_MS)
    expect(again.ok).toBe(true)
    if (!again.ok) return
    expect(again.save.achievements.filter((row) => row.achievementId === 'ACH-0051' && row.unlocked)).toHaveLength(
      1,
    )
    expect(again.save.achievements.find((row) => row.achievementId === 'ACH-0051')?.unlockedAt).toBe(
      theologian[0].unlockedAt,
    )
  })

  it('keeps owned faith titles locked until the player returns to that faith', () => {
    const first = chooseReligion(launch, atTemple(createNewSave(launch, NOW_MS), 100), WOODCUTTING_FAITH, NOW_MS)
    expect(first.ok).toBe(true)
    if (!first.ok) return
    const worn = equipCosmetic(launch, first.save, TITLE_COSMETIC_SLOT_ID, WOODCUTTING_TITLE)
    expect(worn.ok).toBe(true)
    if (!worn.ok) return

    const switched = chooseReligion(launch, worn.save, HUNTING_FAITH, NOW_MS + WEEK_MS)
    expect(switched.ok).toBe(true)
    if (!switched.ok) return
    expect(switched.save.cosmetics.unlocked).toContain(WOODCUTTING_TITLE)
    expect(switched.save.cosmetics.unlocked).toContain(HUNTING_TITLE)
    expect(switched.save.cosmetics.equipped[TITLE_COSMETIC_SLOT_ID]).not.toBe(WOODCUTTING_TITLE)
    const locked = equipCosmetic(launch, switched.save, TITLE_COSMETIC_SLOT_ID, WOODCUTTING_TITLE)
    expect(locked.ok).toBe(false)

    const returned = chooseReligion(launch, switched.save, WOODCUTTING_FAITH, NOW_MS + 2 * WEEK_MS)
    expect(returned.ok).toBe(true)
    if (!returned.ok) return
    const reworn = equipCosmetic(launch, returned.save, TITLE_COSMETIC_SLOT_ID, WOODCUTTING_TITLE)
    expect(reworn.ok).toBe(true)
  })
})
