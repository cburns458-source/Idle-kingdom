import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { applyCombatDefeat } from '../combat/engine'
import { equipCosmetic, grantCosmetic } from '../cosmetics/cosmetics'
import { DATABASE_CONTENT_VERSION, prepareDatabase } from '../data/loadDatabase'
import { achievementLog } from '../log/log'
import { isFaithTitleLocked, religions } from './religion'
import { chooseReligion } from './chooseReligion'
import { rankingProfilePatch } from '../server/rankings'
import {
  nameWithTitle,
  titleForCosmeticId,
  titleForSave,
  titlePlacementForCosmetic,
} from '../save/playerTitle'
import { createNewSave } from '../save/saveStore'
import {
  STARTER_TITLE_COSMETIC_ID,
  TITLE_COSMETIC_SLOT_ID,
  type PlayerSave,
} from '../save/types'
import { totalLevel } from '../skills/totals'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

const NOW_MS = Date.parse('2026-10-15T00:00:00.000Z')
const WEEK_MS = 7 * 24 * 60 * 60 * 1000
const TEMPLE = 'LOC-0036'
const FAITH_TITLE_IDS = [
  'COS-0013',
  'COS-0014',
  'COS-0015',
  'COS-0016',
  'COS-0017',
  'COS-0018',
  'COS-0019',
] as const
const FAITH_NAMES = [
  'Vaelithra',
  'Khavessa',
  'Nymorai',
  'Drazhkar',
  'Korvethan',
  'Elyndara',
  'Veyrathi',
] as const
const THEOLOGIAN_NOTE = 'Have chosen all 7 faiths.'

function withTotalLevel(save: PlayerSave, target: number): PlayerSave {
  const bump = target - totalLevel(save)
  if (bump <= 0) return save
  const [first, ...rest] = save.skills
  return { ...save, skills: [{ ...first, level: first.level + bump }, ...rest] }
}

function atTemple(save: PlayerSave, level = 100): PlayerSave {
  return { ...withTotalLevel(save, level), currentLocationId: TEMPLE, gold: save.gold + 100_000 }
}

function versionFromSource(source: string, pattern: RegExp): string {
  const match = source.match(pattern)
  expect(match?.[1], source).toBeTruthy()
  return match![1]!
}

describe('QA: faith pages, HUD title, and Theologian', () => {
  const { launch } = prepareDatabase(rawDatabase)

  function withEquippedFaithTitle(faithIndex = 0): PlayerSave {
    const faith = religions(launch)[faithIndex]!
    const titleId = faith['Title Cosmetic ID']!
    const first = chooseReligion(launch, atTemple(createNewSave(launch, NOW_MS)), faith['Religion ID'], NOW_MS)
    expect(first.ok).toBe(true)
    if (!first.ok) throw new Error(first.reason)
    const granted = grantCosmetic(first.save, titleId).save
    const worn = equipCosmetic(launch, granted, TITLE_COSMETIC_SLOT_ID, titleId)
    expect(worn.ok).toBe(true)
    if (!worn.ok) throw new Error('equip failed')
    return { ...worn.save, characterName: 'Tester' }
  }

  it('lists exactly the seven approved faith names', () => {
    const names = religions(launch).map((row) => row['Display Name'])
    expect(names).toHaveLength(7)
    expect(names).toEqual(expect.arrayContaining([...FAITH_NAMES]))
    expect(new Set(names)).toEqual(new Set(FAITH_NAMES))
  })

  it('marks COS-0013..COS-0019 as prefix titles and keeps The Undying a suffix', () => {
    for (const cosmeticId of FAITH_TITLE_IDS) {
      const cosmetic = launch.Cosmetics.find((row) => row['Cosmetic ID'] === cosmeticId)
      expect(cosmetic, cosmeticId).toBeDefined()
      expect(cosmetic?.['Title Placement']).toBe('prefix')
      expect(titlePlacementForCosmetic(cosmetic)).toBe('prefix')
      expect(titleForCosmeticId(launch, cosmeticId)?.placement).toBe('prefix')
    }
    const undying = launch.Cosmetics.find((row) => row['Cosmetic ID'] === STARTER_TITLE_COSMETIC_ID)
    expect(undying?.['Title Placement']).toBe('suffix')
    expect(titlePlacementForCosmetic(undying)).toBe('suffix')
    expect(titleForCosmeticId(launch, STARTER_TITLE_COSMETIC_ID)).toEqual({
      text: 'The Undying',
      placement: 'suffix',
    })
  })

  it('shows the equipped faith title before the name and drops it when unequipped, locked, or the faith changes', () => {
    const save = withEquippedFaithTitle()
    const title = titleForSave(save, launch)
    expect(title?.placement).toBe('prefix')
    expect(title?.text).toBeTruthy()
    expect(nameWithTitle('Tester', title)).toBe(`${title!.text} Tester`)

    const unequipped = equipCosmetic(launch, save, TITLE_COSMETIC_SLOT_ID, null)
    expect(unequipped.ok).toBe(true)
    if (!unequipped.ok) return
    expect(titleForSave(unequipped.save, launch)).toBeNull()
    expect(nameWithTitle('Tester', titleForSave(unequipped.save, launch))).toBe('Tester')

    const otherFaith = religions(launch)[1]!
    const locked = { ...save, religionId: otherFaith['Religion ID'] }
    expect(isFaithTitleLocked(launch, locked, save.cosmetics.equipped[TITLE_COSMETIC_SLOT_ID])).toBe(
      true,
    )

    const switched = chooseReligion(launch, { ...save, gold: 100_000 }, otherFaith['Religion ID'], NOW_MS + WEEK_MS)
    expect(switched.ok).toBe(true)
    if (!switched.ok) return
    expect(switched.save.cosmetics.equipped[TITLE_COSMETIC_SLOT_ID]).toBeNull()
    expect(isFaithTitleLocked(launch, switched.save, religions(launch)[0]!['Title Cosmetic ID'])).toBe(
      true,
    )
    expect(titleForSave(switched.save, launch)).toBeNull()
  })

  it('keeps the equipped faith title after a world death', () => {
    const save = withEquippedFaithTitle()
    const before = titleForSave(save, launch)
    expect(before?.placement).toBe('prefix')
    const dead = applyCombatDefeat(launch, save, NOW_MS)
    expect(dead.hasEverDied).toBe(true)
    expect(titleForSave(dead, launch)).toEqual(before)
    expect(nameWithTitle('Tester', titleForSave(dead, launch))).toBe(`${before!.text} Tester`)
  })

  it('publishes the equipped titleCosmeticId and writes nothing for a missing or unknown id', () => {
    const save = withEquippedFaithTitle()
    const titleId = religions(launch)[0]!['Title Cosmetic ID']
    expect(rankingProfilePatch(save).appearance_json.titleCosmeticId).toBe(titleId)
    expect(titleForCosmeticId(launch, titleId)?.placement).toBe('prefix')
    expect(titleForCosmeticId(launch, null)).toBeNull()
    expect(titleForCosmeticId(launch, '')).toBeNull()
    expect(titleForCosmeticId(launch, 'COS-9999')).toBeNull()
    expect(nameWithTitle('Mira', titleForCosmeticId(launch, 'COS-9999'))).toBe('Mira')
    expect(nameWithTitle('Mira', titleForCosmeticId(launch, null))).toBe('Mira')
  })

  it('uses Theologian deed text exactly "Have chosen all 7 faiths."', () => {
    const row = launch.Achievements.find((entry) => entry['Achievement ID'] === 'ACH-0051')
    expect(row?.['Display Name']).toBe('Theologian')
    expect(row?.Notes).toBe(THEOLOGIAN_NOTE)
    expect(row?.Notes).not.toMatch(/granted once/i)
    expect(row?.Notes).not.toMatch(/Survives reload/i)

    const log = achievementLog(launch, createNewSave(launch, NOW_MS)).find(
      (entry) => entry.achievementId === 'ACH-0051',
    )
    expect(log?.note).toBe(THEOLOGIAN_NOTE)
    expect(log?.note).not.toMatch(/granted once/i)
    expect(log?.note).not.toMatch(/Survives reload/i)
  })

  it('keeps DATABASE_CONTENT_VERSION in lockstep with the Dart loader', () => {
    const tsSource = readFileSync(resolve(process.cwd(), 'src/game/data/loadDatabase.ts'), 'utf8')
    const dartSource = readFileSync(
      resolve(process.cwd(), 'packages/ik_content/lib/src/load_database.dart'),
      'utf8',
    )
    const tsVersion = versionFromSource(tsSource, /export const DATABASE_CONTENT_VERSION = '([^']+)'/)
    const dartVersion = versionFromSource(
      dartSource,
      /const String databaseContentVersion = '([^']+)';/,
    )
    expect(tsVersion).toBe(DATABASE_CONTENT_VERSION)
    expect(dartVersion).toBe(DATABASE_CONTENT_VERSION)
    expect(tsVersion).toBe(dartVersion)
  })
})
