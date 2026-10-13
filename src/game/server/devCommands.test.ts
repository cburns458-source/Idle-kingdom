import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { applyDevCommand, parseDevCommandLine } from './devCommands'
import { getSkillProgress } from '../activity/xp'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)
const { launch: db } = prepareDatabase(rawDatabase)
const START_MS = Date.parse('2026-01-01T00:00:00.000Z')

describe('developer commands', () => {
  it('parses a slash line', () => {
    expect(parseDevCommandLine('/give copper ore 5')).toEqual({
      command: 'give',
      tokens: ['copper', 'ore', '5'],
    })
  })

  it('gives an item by display name', () => {
    const save = createNewSave(db, START_MS)
    const result = applyDevCommand(db, save, 'give', ['potato', '3'], START_MS)
    expect(result.ok).toBe(true)
    expect(result.message).toMatch(/Potato/)
    expect(result.save.inventory.some((stack) => stack.itemId === 'ITEM-0025' && stack.quantity >= 3)).toBe(
      true,
    )
  })

  it('sets a skill level', () => {
    const save = createNewSave(db, START_MS)
    const result = applyDevCommand(db, save, 'setlevel', ['might', '20'], START_MS)
    expect(result.ok).toBe(true)
    expect(getSkillProgress(result.save, 'SKL-0001').level).toBe(20)
  })

  it('requires confirm for resetskills', () => {
    const save = createNewSave(db, START_MS)
    const refused = applyDevCommand(db, save, 'resetskills', [], START_MS)
    expect(refused.ok).toBe(false)
    const ok = applyDevCommand(db, save, 'resetskills', ['confirm'], START_MS)
    expect(ok.ok).toBe(true)
  })

  it('prunes a locked farm timer spot after /abandonquest QST-0011 confirm', () => {
    const growing = {
      locationId: 'LOC-0001',
      kind: 'botany' as const,
      inputItemId: 'ITEM-0324',
      outputItemId: 'ITEM-0025',
      outputQuantity: 1,
      skillId: 'SKL-0014',
      xpReward: 10,
      startedAt: '2026-01-01T00:00:00.000Z',
      durationMs: 60_000,
    }
    const save = {
      ...createNewSave(db, START_MS),
      discoveredTimerSpotIds: ['botany:LOC-0001', 'botany:LOC-0009', 'fishing_pot:LOC-0003'],
      quests: [
        {
          questId: 'QST-0011',
          status: 'active' as const,
          progress: 1,
          counters: { 'talk:NPC-0014': 1, 'step:QSTP-0023': 1 },
        },
      ],
    }
    const abandoned = applyDevCommand(db, save, 'abandonquest', ['QST-0011', 'confirm'], START_MS)
    expect(abandoned.ok).toBe(true)
    expect(abandoned.save.discoveredTimerSpotIds).toEqual(['botany:LOC-0009', 'fishing_pot:LOC-0003'])

    const abandonedGrowing = applyDevCommand(
      db,
      { ...save, locationTimers: [growing] },
      'abandonquest',
      ['QST-0011', 'confirm'],
      START_MS,
    )
    expect(abandonedGrowing.ok).toBe(true)
    expect(abandonedGrowing.save.discoveredTimerSpotIds).toContain('botany:LOC-0001')
    expect(abandonedGrowing.save.discoveredTimerSpotIds).toContain('botany:LOC-0009')
    expect(abandonedGrowing.save.discoveredTimerSpotIds).toContain('fishing_pot:LOC-0003')
    expect(abandonedGrowing.save.locationTimers).toEqual([growing])
  })
})
