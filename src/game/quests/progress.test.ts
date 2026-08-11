import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { parseStructuredObjectives, questObjectiveProgress } from './objectives'
import {
  applyQuestDefeatProgress,
  applyQuestLearnRecipeProgress,
  applyQuestProcessProgress,
} from './progress'
import { acceptQuest, getQuest } from './quests'
import { unlockRecipeId } from '../recipes/knowledge'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

describe('quest objective engine v2', () => {
  it('parses deliver + gold + unlock from Help the aspiring apothecary notes', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const quest = getQuest(launch, 'QST-0002')!
    const structured = parseStructuredObjectives(quest)
    expect(structured.kind).toBe('gather_deliver')
    expect(structured.delivers.length).toBeGreaterThan(0)
    expect(structured.goldCost).toBeGreaterThan(0)
    expect(structured.unlockLocationIds).toContain('LOC-0026')
  })

  it('tracks defeat and process counters on active quests', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      quests: [{ questId: 'QST-TEST', status: 'active', progress: 0, counters: {} }],
    }

    // Inject a synthetic structured quest by patching Notes via a shallow quest row
    // exercise — counters only bump when Notes declare Defeat/Process targets.
    const db = {
      ...launch,
      Quests: [
        ...launch.Quests,
        {
          'Quest ID': 'QST-TEST',
          'Internal Key': 'test',
          'Display Name': 'Test',
          'NPC ID': 'NPC-0001',
          Summary: null,
          Status: 'Complete',
          'Release Phase': 'Launch',
          Notes: 'Defeat: ENM-0001 x3; Process: RCP-0001 x2; LearnRecipe: RCP-0002',
          'Objective Type': 'defeat',
          'Objective Target ID': null,
          'Required Quantity': null,
          Repeatable: 'No',
          'Reward XP Skill ID': null,
          'Reward XP Amount': null,
          'Reward Item ID': null,
          'Reward Item Quantity': null,
          'Possible Rewards': null,
        },
      ],
    }

    save = applyQuestDefeatProgress(db as typeof launch, save, 'ENM-0001', 2)
    save = applyQuestProcessProgress(db as typeof launch, save, 'RCP-0001', 1)
    save = unlockRecipeId(save, 'RCP-0002')
    save = applyQuestLearnRecipeProgress(db as typeof launch, save, 'RCP-0002')

    const progress = save.quests.find((row) => row.questId === 'QST-TEST')!
    expect(progress.counters?.['defeat:ENM-0001']).toBe(2)
    expect(progress.counters?.['process:RCP-0001']).toBe(1)
    expect(progress.counters?.['learn:RCP-0002']).toBe(1)

    const quest = getQuest(db as typeof launch, 'QST-TEST')!
    const status = questObjectiveProgress(db as typeof launch, save, quest)
    expect(status.progressLines.find((line) => line.key === 'defeat:ENM-0001')?.current).toBe(2)
    expect(status.ready).toBe(false)
  })

  it('keeps existing deliver quests accept/turn-in ready when inventory is met', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = { ...createNewSave(launch), currentLocationId: 'LOC-0023', gold: 1500 }
    const accepted = acceptQuest(launch, save, 'QST-0002')
    expect(accepted.ok).toBe(true)
    if (!accepted.ok) return
    save = accepted.save
    const quest = getQuest(launch, 'QST-0002')!
    const before = questObjectiveProgress(launch, save, quest)
    expect(before.ready).toBe(false)
  })
})
