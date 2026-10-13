import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { addItemToInventory } from '../activity/rewards'
import { prepareDatabase } from '../data/loadDatabase'
import type { GameDatabase } from '../data/types'
import { chooseDialogue } from '../dialogue/engine'
import { inventoryCount } from '../production/recipes'
import { createNewSave } from '../save/saveStore'
import type { PlayerSave } from '../save/types'
import {
  applyQuestProcessProgress,
  applyQuestTalkProgress,
  applyQuestVisitProgress,
} from './progress'
import { getQuest, getQuestProgress } from './quests'
import { applyQuestStepUnlocks, getCurrentStepIndex } from './steps'

// BUG-01: completed quest steps latch via a `step:<stepId>` counter so live
// `Hold:` checks can't send Getting Started (QST-0006) back to step 1.

const QUEST = 'QST-0006'
const FENNEL = 'NPC-0014'
const RAW = 'ITEM-0025'
const COOKED = 'ITEM-0058'
const KITCHEN = 'LOC-0023'
const RECIPE = 'RCP-0001'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

function setCount(save: PlayerSave, itemId: string, quantity: number): PlayerSave {
  const cleared = { ...save, inventory: save.inventory.filter((stack) => stack.itemId !== itemId) }
  return quantity > 0 ? addItemToInventory(cleared, itemId, quantity) : cleared
}

function activeGettingStarted(db: GameDatabase): PlayerSave {
  const save = createNewSave(db)
  return {
    ...save,
    quests: [
      ...save.quests.filter((row) => row.questId !== QUEST),
      { questId: QUEST, status: 'active', progress: 0, counters: {} },
    ],
  }
}

const index = (db: GameDatabase, save: PlayerSave) =>
  getCurrentStepIndex(db, save, getQuest(db, QUEST)!)

/** Fennel's Show choices: the raw potatoes (QSTP-0014) and the baked ones (QSTP-0016). */
function showFennel(db: GameDatabase, save: PlayerSave, which: 'raw' | 'cooked'): PlayerSave {
  const [dialogueId, nodeId, choiceId] =
    which === 'raw' ? ['DLG-0003', 'DNODE-0004', 'DCH-0005'] : ['DLG-0005', 'DNODE-0007', 'DCH-0009']
  const shown = chooseDialogue(db, save, dialogueId, nodeId, choiceId)
  expect(shown.ok, shown.reason).toBe(true)
  return shown.save
}

function throughCooking(db: GameDatabase): PlayerSave {
  let save = applyQuestStepUnlocks(db, setCount(activeGettingStarted(db), RAW, 5))
  expect(index(db, save)).toBe(1)
  save = applyQuestTalkProgress(db, save, FENNEL)
  expect(index(db, save)).toBe(1)
  save = showFennel(db, save, 'raw')
  expect(index(db, save)).toBe(2)
  save = applyQuestVisitProgress(db, save, KITCHEN)
  for (let cooked = 1; cooked <= 5; cooked += 1) {
    save = setCount(save, RAW, 5 - cooked)
    save = setCount(save, COOKED, cooked)
    save = applyQuestProcessProgress(db, save, RECIPE)
    expect(index(db, save)).toBe(cooked < 5 ? 2 : 3)
  }
  return save
}

describe('quest step latching (BUG-01)', () => {
  const { launch } = prepareDatabase(rawDatabase)

  it('hold, talk, cook 5 reaches step 3 then 4 without regressing', () => {
    let save = throughCooking(launch)
    const counters = getQuestProgress(save, QUEST).counters ?? {}
    expect(counters['step:QSTP-0013']).toBe(1)
    expect(counters['step:QSTP-0014']).toBe(1)
    expect(counters['step:QSTP-0015']).toBe(1)
    expect(inventoryCount(save, RAW)).toBe(0)
    save = showFennel(launch, save, 'cooked')
    expect(index(launch, save)).toBe(4)
    expect(inventoryCount(save, COOKED)).toBe(5)
  })

  it('selling the cooked potatoes at step 5 does not regress', () => {
    let save = showFennel(launch, throughCooking(launch), 'cooked')
    expect(index(launch, save)).toBe(4)
    save = applyQuestStepUnlocks(launch, setCount(save, COOKED, 0))
    expect(index(launch, save)).toBe(4)
  })

  it('steps only latch in order', () => {
    const save = applyQuestStepUnlocks(launch, setCount(activeGettingStarted(launch), COOKED, 5))
    expect(getQuestProgress(save, QUEST).counters?.['step:QSTP-0016']).toBeUndefined()
    expect(index(launch, save)).toBe(0)
  })

  it('unlocks from a latched step stay applied', () => {
    const patchedRaw = {
      ...rawDatabase,
      QuestSteps: rawDatabase.QuestSteps.map((step: Record<string, unknown>) =>
        step['Step ID'] === 'QSTP-0013'
          ? { ...step, Notes: `Hold: ${RAW} x5; UnlockLocation: LOC-9999` }
          : step,
      ),
    }
    const db = prepareDatabase(patchedRaw).launch
    let save = applyQuestStepUnlocks(db, setCount(activeGettingStarted(db), RAW, 5))
    expect(save.unlockedLocationIds).toContain('LOC-9999')
    save = {
      ...setCount(save, RAW, 0),
      unlockedLocationIds: (save.unlockedLocationIds ?? []).filter((id) => id !== 'LOC-9999'),
    }
    save = applyQuestStepUnlocks(db, save)
    expect(save.unlockedLocationIds).toContain('LOC-9999')
    expect(index(db, save)).toBe(1)
  })
})
