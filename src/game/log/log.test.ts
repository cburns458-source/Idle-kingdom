import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import type { GameDatabase } from '../data/types'
import { applyQuestAutoStartOnSeed, applyQuestProcessProgress, applyQuestVisitProgress } from '../quests/progress'
import { completeQuest, getQuest } from '../quests/quests'
import { isOptionalStep, questStepJournal } from '../quests/steps'
import { createNewSave } from '../save/saveStore'
import type { PlayerSave } from '../save/types'
import {
  achievementLog,
  critterLog,
  logCompletion,
  milestoneLog,
  miniQuestJournal,
  questJournalSteps,
  questLog,
  recipeLog,
} from './log'
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

  it('leaves a skipped cook step unticked until the feast is completed', () => {
    const skipped = {
      ...createNewSave(launch),
      quests: [
        {
          questId: 'QST-0001',
          status: 'active' as const,
          progress: 2,
          counters: { 'talk:NPC-0001': 1, 'step:QSTP-0001': 1 },
        },
      ],
    }
    const active = questLog(launch, skipped).find((entry) => entry.questId === 'QST-0001')!
    expect(active.steps.find((step) => step.key === 'QSTP-0036')).toEqual({
      key: 'QSTP-0036',
      label: 'Cook food for the feast',
      state: 'current',
    })

    const finished = {
      ...skipped,
      quests: [{ questId: 'QST-0001', status: 'completed' as const, progress: 10, counters: {} }],
    }
    const done = questLog(launch, finished).find((entry) => entry.questId === 'QST-0001')!
    expect(done.steps.find((step) => step.key === 'QSTP-0036')).toEqual({
      key: 'QSTP-0036',
      label: 'Cook food for the feast',
      state: 'done',
    })
  })

  it('reveals the hand-in once the King is heard and the food is cooked', () => {
    const save = {
      ...createNewSave(launch),
      quests: [
        {
          questId: 'QST-0001',
          status: 'active' as const,
          progress: 3,
          counters: { 'talk:NPC-0001': 1, 'step:QSTP-0001': 1, 'step:QSTP-0036': 1 },
        },
      ],
    }
    const row = questLog(launch, save).find((entry) => entry.questId === 'QST-0001')!
    // QSTP-0002 is a HandIn step: progress lives in the King's dialogue, not Deliver lines.
    expect(row.steps).toEqual([
      { key: 'QSTP-0001', label: 'Hear what the King needs', state: 'done' },
      { key: 'QSTP-0036', label: 'Cook food for the feast', state: 'done' },
      { key: 'QSTP-0002', label: 'Bring the food to the King', state: 'current' },
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
    expect(row.steps.some((step) => step.state === 'done')).toBe(true)
    expect(row.steps.find((step) => step.key === 'header:rewards')).toEqual({
      key: 'header:rewards',
      label: 'Rewards',
      state: 'header',
    })
    expect(row.steps.some((step) => step.label === '10,000 Cooking XP')).toBe(true)
    expect(row.steps.some((step) => /Golden spud/i.test(step.label))).toBe(true)
    expect(row.steps.filter((step) => step.state !== 'header').every((step) => step.state === 'done')).toBe(
      true,
    )
  })

  it('keeps reward lines off in-progress quests', () => {
    const save = {
      ...createNewSave(launch),
      quests: [{ questId: 'QST-0001', status: 'active' as const, progress: 0, counters: {} }],
    }
    const row = questLog(launch, save).find((entry) => entry.questId === 'QST-0001')!
    expect(row.steps.some((step) => step.key === 'header:rewards')).toBe(false)
    expect(row.steps.some((step) => step.label === 'Rewards')).toBe(false)
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
    expect(row.name).toBe('Chick')
    expect(row.description).not.toBeNull()
    expect(row.count).toBe(4)
    expect(row.found).toBe(true)
  })
})

describe('milestones', () => {
  it('tracks every-skill, kills, gold, gathering, projects, and critter marks', () => {
    const fresh = milestoneLog(launch, createNewSave(launch))
    // 4 skill + 3*3 count tracks + 3 project + 1 critter collector
    expect(fresh).toHaveLength(17)
    expect(fresh.every((row) => !row.unlocked)).toBe(true)
    expect(fresh.some((row) => row.name === 'Every skill 25')).toBe(true)
    expect(fresh.some((row) => row.name === '10,000 monsters slain')).toBe(true)
    expect(fresh.some((row) => row.name === '10,000 gold earned')).toBe(true)
    expect(fresh.some((row) => row.name === '10,000 gatherings')).toBe(true)
    expect(fresh.some((row) => row.name === '100 projects completed')).toBe(true)
    expect(fresh.some((row) => row.name === 'Critter collector')).toBe(true)

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
          projects_completed: 1000,
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
    expect(rows.find((row) => row.milestoneId === 'projects-100')!.unlocked).toBe(true)
    expect(rows.find((row) => row.milestoneId === 'projects-1000')!.unlocked).toBe(true)
    expect(logCompletion(launch, save).sections.find((row) => row.section === 'milestones')!.done).toBe(
      10,
    )
  })
})

const OPTIONAL_MINIQUEST = 'QST-9302'
const OPTIONAL_HOLD = 'QSTP-9312'

function miniquestWithOptionalStep(db: GameDatabase): GameDatabase {
  return {
    ...db,
    Quests: [
      ...db.Quests,
      {
        'Quest ID': OPTIONAL_MINIQUEST,
        'Internal Key': 'miniquest_optional_journal',
        'Display Name': 'Miniquest Optional Journal',
        'NPC ID': 'NPC-0014',
        Summary: 'A test miniquest with a skipped optional step.',
        Pitch: null,
        Status: 'Confirmed',
        'Release Phase': 'Launch',
        Notes: 'Miniquest; HideFromQuestLog',
        'Objective Type': null,
        'Objective Target ID': null,
        'Required Quantity': null,
        Repeatable: null,
        'Reward XP Skill ID': null,
        'Reward XP Amount': null,
        'Reward Item ID': null,
        'Reward Item Quantity': null,
        'Possible Rewards': null,
      },
    ],
    QuestSteps: [
      ...db.QuestSteps,
      {
        'Step ID': 'QSTP-9311',
        'Quest ID': OPTIONAL_MINIQUEST,
        'Step Order': 1,
        'Journal Label': 'Visit the kitchen',
        Notes: 'Visit: LOC-0023',
        'Step Type': null,
        'Step Items': null,
        'Step NPC': null,
        Status: 'Confirmed',
        'Release Phase': 'Launch',
      },
      {
        'Step ID': OPTIONAL_HOLD,
        'Quest ID': OPTIONAL_MINIQUEST,
        'Step Order': 2,
        'Journal Label': 'Hold ten baked potatoes',
        Notes: 'Hold: ITEM-0058 x10; Optional',
        'Step Type': null,
        'Step Items': null,
        'Step NPC': null,
        Status: 'Confirmed',
        'Release Phase': 'Launch',
      },
      {
        'Step ID': 'QSTP-9313',
        'Quest ID': OPTIONAL_MINIQUEST,
        'Step Order': 3,
        'Journal Label': 'Bake a potato',
        Notes: 'Process: RCP-0001 x1',
        'Step Type': null,
        'Step Items': null,
        'Step NPC': null,
        Status: 'Confirmed',
        'Release Phase': 'Launch',
      },
    ],
  }
}

function withActive(save: PlayerSave, questId: string): PlayerSave {
  return {
    ...save,
    quests: [
      ...save.quests.filter((row) => row.questId !== questId),
      { questId, status: 'active', progress: 0, counters: {} },
    ],
  }
}

describe('miniquest journal', () => {
  it('lists Green Thumb steps with the shared journal and keeps them out of quest %', () => {
    let save: PlayerSave = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0001',
      inventory: [{ itemId: 'ITEM-0324', quantity: 1 }],
      quests: [{ questId: 'QST-0006', status: 'completed', progress: 1 }],
    }
    save = applyQuestAutoStartOnSeed(launch, save)
    const quest = getQuest(launch, 'QST-0011')!
    const row = miniQuestJournal(launch, save).find((entry) => entry.questId === 'QST-0011')!
    expect(questLog(launch, save).some((entry) => entry.questId === 'QST-0011')).toBe(false)
    expect(row.steps).toEqual(questJournalSteps(launch, save, quest))
    expect(row.steps).toEqual(questStepJournal(launch, save, quest))
    expect(row.steps[0]?.label).toBe('Speak with Fennel at the farm')
    expect(row.steps[0]?.state).toBe('current')

    const before = logCompletion(launch, save).sections.find((entry) => entry.section === 'quests')!
    const miniDone = {
      ...save,
      quests: save.quests.map((entry) =>
        entry.questId === 'QST-0011' ? { ...entry, status: 'completed' as const } : entry,
      ),
    }
    const afterMini = logCompletion(launch, miniDone).sections.find((entry) => entry.section === 'quests')!
    expect(afterMini).toEqual(before)

    const feastDone = {
      ...miniDone,
      quests: [
        ...miniDone.quests.filter((entry) => entry.questId !== 'QST-0001'),
        { questId: 'QST-0001', status: 'completed' as const, progress: 10 },
      ],
    }
    const afterFeast = logCompletion(launch, feastDone).sections.find((entry) => entry.section === 'quests')!
    expect(afterFeast.done).toBe(before.done + 1)
    expect(afterFeast.total).toBe(before.total)
  })

  it('ticks a skipped optional miniquest step the same way a normal quest does', () => {
    const db = miniquestWithOptionalStep(launch)
    const quest = getQuest(db, OPTIONAL_MINIQUEST)!
    expect(isOptionalStep(db.QuestSteps.find((row) => row['Step ID'] === OPTIONAL_HOLD)!)).toBe(true)
    let save = withActive(createNewSave(db), OPTIONAL_MINIQUEST)
    save = applyQuestVisitProgress(db, save, 'LOC-0023')
    save = applyQuestProcessProgress(db, save, 'RCP-0001')

    const journal = miniQuestJournal(db, save).find((row) => row.questId === OPTIONAL_MINIQUEST)!
    expect(journal.steps).toEqual(questStepJournal(db, save, quest))
    expect(journal.steps.find((step) => step.key === OPTIONAL_HOLD)).toEqual({
      key: OPTIONAL_HOLD,
      label: 'Hold ten baked potatoes',
      state: 'current',
    })
    expect(questLog(db, save).some((row) => row.questId === OPTIONAL_MINIQUEST)).toBe(false)

    const before = logCompletion(db, save).sections.find((row) => row.section === 'quests')!
    const finished = completeQuest(db, save, OPTIONAL_MINIQUEST, { ignoreLocation: true })
    expect(finished.ok).toBe(true)
    if (!finished.ok) return
    const after = logCompletion(db, finished.save).sections.find((row) => row.section === 'quests')!
    expect(after).toEqual(before)
    expect(
      miniQuestJournal(db, finished.save)
        .find((row) => row.questId === OPTIONAL_MINIQUEST)!
        .steps.find((step) => step.key === OPTIONAL_HOLD),
    ).toEqual({
      key: OPTIONAL_HOLD,
      label: 'Hold ten baked potatoes',
      state: 'done',
    })
  })
})
