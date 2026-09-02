import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { achievementLog, critterLog, logCompletion, milestoneLog, questLog, recipeLog } from './log'
import { GATHERING_ACTIONS_STAT } from './milestones'

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

  it('keeps the requirement and marks the deed completed', () => {
    const save = createNewSave(launch)
    const first = achievementLog(launch, save)[0]!
    const unlocked = {
      ...save,
      achievements: [{ achievementId: first.achievementId, unlocked: true, unlockedAt: null }],
    }
    const row = achievementLog(launch, unlocked)[0]!
    expect(row.note).toBe(first.note)
    expect(row.note).not.toBe('Unlocked')
    expect(row.note.length).toBeGreaterThan(0)
    expect(row.unlocked).toBe(true)
  })
})

describe('quest log', () => {
  it('starts every quest not started, and lists gates on locked ones', () => {
    const rows = questLog(launch, createNewSave(launch))
    expect(rows.length).toBeGreaterThan(0)
    expect(rows.every((row) => row.statusLabel === 'Not started')).toBe(true)
    expect(rows[0]!.detail).toContain(' · ')
    expect(rows.find((row) => row.questId === 'QST-0001')!.detail).toContain(
      'new cook for the feast',
    )
    expect(rows.find((row) => row.questId === 'QST-0003')!.name).toBe('Lowly Beggar')
    expect(rows.find((row) => row.questId === 'QST-0003')!.detail).toContain(
      'asking for help in the town',
    )
    expect(rows.find((row) => row.questId === 'QST-0004')!.detail).toContain(
      'guide was waiting in the Citadel plaza',
    )
    expect(rows.find((row) => row.questId === 'QST-0005')!.detail).toContain(
      'Archmage wants an apprentice',
    )
    expect(rows.find((row) => row.questId === 'QST-0001')!.steps).toEqual([])
    expect(rows.find((row) => row.questId === 'QST-0007')!.steps).toEqual([
      { key: 'header:required', label: 'Required', state: 'header' },
      { key: 'skill:SKL-0008', label: 'Reach Metallurgy 35 (1 / 35)', state: 'current' },
      { key: 'skill:SKL-0011', label: 'Reach Smithing 35 (1 / 35)', state: 'current' },
    ])
    expect(rows.find((row) => row.questId === 'QST-0008')!.steps).toEqual([
      { key: 'header:required', label: 'Required', state: 'header' },
      { key: 'skill:SKL-0002', label: 'Reach Mining 60 (1 / 60)', state: 'current' },
      { key: 'quest:QST-0007', label: 'Complete Forged in Fire', state: 'current' },
    ])
    expect(rows.find((row) => row.questId === 'QST-0001')!.steps.map((step) => step.state)).not.toContain(
      'header',
    )
    expect(rows.find((row) => row.questId === 'QST-0006')!.steps).toEqual([])
  })

  it('reveals journal steps for an active quest with talk progress', () => {
    const save = createNewSave(launch)
    const active = {
      ...save,
      quests: [{ questId: 'QST-0001', status: 'active' as const, progress: 0, counters: {} }],
    }
    const row = questLog(launch, active).find((entry) => entry.questId === 'QST-0001')!
    expect(row.statusLabel).toBe('Active')
    expect(row.steps).toEqual([
      { key: 'QSTP-0001', label: 'Hear what the King needs', state: 'current' },
      { key: 'talk:NPC-0001', label: 'Talk to King 0 / 1', state: 'current' },
    ])
  })

  it('lists only Citadel visit stops while the tour is active', () => {
    const save = {
      ...createNewSave(launch),
      quests: [{ questId: 'QST-0004', status: 'active' as const, progress: 0, counters: {} }],
    }
    const row = questLog(launch, save).find((entry) => entry.questId === 'QST-0004')!
    expect(row.steps.map((step) => step.label)).toEqual([
      'Look around the Citadel',
      'Visit Grand Bazaar 0 / 1',
      'Visit Processing District 0 / 1',
      'Visit Citadel Bank 0 / 1',
      'Visit Gathering Outskirts 0 / 1',
      'Visit Combat Training Grounds 0 / 1',
    ])
    expect(row.steps.map((step) => step.label).join('\n')).not.toMatch(/Talk|Inspect|Guild Hall/)
  })

  it('opens Getting Started on gathering potatoes, not talking to Fennel', () => {
    const save = {
      ...createNewSave(launch),
      quests: [{ questId: 'QST-0006', status: 'active' as const, progress: 0, counters: {} }],
    }
    const row = questLog(launch, save).find((entry) => entry.questId === 'QST-0006')!
    expect(row.steps[0]).toEqual({
      key: 'QSTP-0013',
      label: 'Gather five potatoes',
      state: 'current',
    })
    expect(row.steps.map((step) => step.label).join('\n')).not.toMatch(/Talk to Fennel|Hear Fennel/)
    expect(row.steps.map((step) => step.label)).not.toContain('Cook the potatoes in town')
  })

  it('opens Wizard Studies on Hear the shopkeeper out', () => {
    const save = {
      ...createNewSave(launch),
      quests: [{ questId: 'QST-0005', status: 'active' as const, progress: 0, counters: {} }],
    }
    const row = questLog(launch, save).find((entry) => entry.questId === 'QST-0005')!
    expect(row.steps).toEqual([
      { key: 'QSTP-0010', label: 'Hear the shopkeeper out', state: 'current' },
      { key: 'talk:NPC-0009', label: 'Talk to Wizard Shopkeeper 0 / 1', state: 'current' },
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
      { key: 'deliver:ITEM-0058', label: 'Deliver Baked Potato 0 / 10', state: 'current' },
      { key: 'deliver:ITEM-0059', label: 'Deliver Cooked Crawfish 0 / 10', state: 'current' },
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
    expect(row.steps.length).toBeGreaterThan(0)
    expect(row.steps.every((step) => step.state === 'done')).toBe(true)
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

describe('milestones', () => {
  it('tracks every-skill, kills, gold, and gathering marks', () => {
    const fresh = milestoneLog(launch, createNewSave(launch))
    expect(fresh).toHaveLength(13)
    expect(fresh.every((row) => !row.unlocked)).toBe(true)
    expect(fresh.some((row) => row.name === 'Every skill 25')).toBe(true)
    expect(fresh.some((row) => row.name === '10,000 monsters slain')).toBe(true)
    expect(fresh.some((row) => row.name === '10,000 gold earned')).toBe(true)
    expect(fresh.some((row) => row.name === '10,000 gatherings')).toBe(true)

    const save = {
      ...createNewSave(launch),
      skills: launch.Skills.map((skill) => ({
        skillId: skill['Skill ID'],
        level: 50,
        xp: 0,
      })),
      statistics: {
        values: {
          monsters_killed: 10_000,
          gold_earned: 1_000_000,
          [GATHERING_ACTIONS_STAT]: 100_000,
        },
      },
    }
    const rows = milestoneLog(launch, save)
    expect(rows.filter((row) => row.track === 'skills' && row.unlocked).map((row) => row.required)).toEqual([
      25, 50,
    ])
    expect(rows.find((row) => row.milestoneId === 'kills-10000')!.unlocked).toBe(true)
    expect(rows.find((row) => row.milestoneId === 'gold-1000000')!.unlocked).toBe(true)
    expect(rows.find((row) => row.milestoneId === 'gatherings-100000')!.unlocked).toBe(true)
    expect(logCompletion(launch, save).sections.find((row) => row.section === 'milestones')!.done).toBe(
      8,
    )
  })
})
