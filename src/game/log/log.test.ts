import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { achievementLog, critterLog, questLog, recipeLog } from './log'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

const { launch } = prepareDatabase(rawDatabase)

describe('achievement log', () => {
  it('says what an unreached milestone takes', () => {
    const rows = achievementLog(launch, createNewSave(launch))
    expect(rows.length).toBeGreaterThan(0)
    expect(rows.every((row) => !row.unlocked)).toBe(true)
    expect(rows[0]!.note.length).toBeGreaterThan(0)
    expect(rows.some((row) => row.difficulty === 'Easy')).toBe(true)
    expect(rows.some((row) => row.difficulty === 'Hard')).toBe(true)
  })

  it('reads Unlocked once the save has it', () => {
    const save = createNewSave(launch)
    const achievementId = achievementLog(launch, save)[0]!.achievementId
    const unlocked = {
      ...save,
      achievements: [{ achievementId, unlocked: true, unlockedAt: null }],
    }
    expect(achievementLog(launch, unlocked)[0]!.note).toBe('Unlocked')
    expect(achievementLog(launch, unlocked)[0]!.unlocked).toBe(true)
  })
})

describe('quest log', () => {
  it('starts every quest not started, with no steps shown', () => {
    const rows = questLog(launch, createNewSave(launch))
    expect(rows.length).toBeGreaterThan(0)
    expect(rows.every((row) => row.statusLabel === 'Not started')).toBe(true)
    expect(rows.every((row) => row.steps.length === 0)).toBe(true)
    expect(rows[0]!.detail).toContain(' · ')
    expect(rows.find((row) => row.questId === 'QST-0001')!.detail).toContain(
      'new cook for the feast',
    )
  })

  it('reveals journal steps for an active quest without numeric progress', () => {
    const save = createNewSave(launch)
    const active = {
      ...save,
      quests: [{ questId: 'QST-0001', status: 'active' as const, progress: 0, counters: {} }],
    }
    const row = questLog(launch, active).find((entry) => entry.questId === 'QST-0001')!
    expect(row.statusLabel).toBe('Active')
    expect(row.steps).toEqual([
      { key: 'QSTP-0001', label: 'Hear what the King needs', state: 'current' },
    ])
  })

  it('reveals the next feast step after the King is heard', () => {
    const save = {
      ...createNewSave(launch),
      quests: [
        {
          questId: 'QST-0001',
          status: 'active' as const,
          progress: 1,
          counters: { 'talk:NPC-0001': 1 },
        },
      ],
    }
    const row = questLog(launch, save).find((entry) => entry.questId === 'QST-0001')!
    expect(row.steps).toEqual([
      { key: 'QSTP-0001', label: 'Hear what the King needs', state: 'done' },
      { key: 'QSTP-0002', label: 'Prepare food for the feast', state: 'current' },
    ])
  })

  it('marks a finished quest completed', () => {
    const save = createNewSave(launch)
    const done = {
      ...save,
      quests: [{ questId: 'QST-0001', status: 'completed' as const, progress: 10, counters: {} }],
    }
    const row = questLog(launch, done).find((entry) => entry.questId === 'QST-0001')!
    expect(row.statusLabel).toBe('Completed')
    expect(row.completed).toBe(true)
  })
})

describe('recipe log', () => {
  it('describes a known recipe and withholds the rest', () => {
    const rows = recipeLog(launch, createNewSave(launch))
    const known = rows.filter((row) => row.known)
    expect(known.length).toBeGreaterThan(0)
    expect(known[0]!.title).toMatch(/^\d+\. [A-Z][^:]*: .+$/)
    expect(known[0]!.detail).toBe('')
    expect(known[0]!.title.includes(' × ')).toBe(true)

    const locked = rows.filter((row) => !row.known)
    expect(locked.length).toBeGreaterThan(0)
    expect(locked.some((row) => row.title === 'Unknown recipe')).toBe(true)
    expect(locked.some((row) => /^\d+\. /.test(row.title))).toBe(true)
    expect(
      locked.every((row) => row.title === 'Unknown recipe' || /^\d+\. /.test(row.title)),
    ).toBe(true)
  })
})

describe('critter log', () => {
  it('keeps an uncaught critter anonymous', () => {
    const rows = critterLog(createNewSave(launch))
    expect(rows.length).toBeGreaterThan(0)
    expect(rows.every((row) => row.name === 'Unknown')).toBe(true)
    expect(rows.every((row) => row.description === null)).toBe(true)
  })

  it('names and counts one that has been caught', () => {
    const save = createNewSave(launch)
    const caught = { ...save, critterCollections: [{ critterId: 'CRT-0001', count: 4 }] }
    const row = critterLog(caught).find((entry) => entry.critterId === 'CRT-0001')!
    expect(row.name).toBe('Fly')
    expect(row.description).not.toBeNull()
    expect(row.count).toBe(4)
    expect(row.found).toBe(true)
  })
})
