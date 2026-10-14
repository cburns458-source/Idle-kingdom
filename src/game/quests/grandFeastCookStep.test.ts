import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { addItemToInventory } from '../activity/rewards'
import { getSkillProgress } from '../activity/xp'
import { prepareDatabase } from '../data/loadDatabase'
import { chooseDialogue, dialoguesForNpc, startDialogue, type DialogueResult } from '../dialogue/engine'
import { bagCount } from '../dialogue/stepProgress'
import { createNewSave, parseSave } from '../save/saveStore'
import type { PlayerSave, QuestProgress } from '../save/types'
import { courtyardBotanyUnlocked } from '../timers/locationTimers'
import { parseNotesObjectives } from './objectives'
import { applyQuestProcessProgress, applyQuestVisitProgress } from './progress'
import { completeQuest, getQuest, getQuestProgress } from './quests'
import {
  dialogueStepType,
  getCurrentStepId,
  getQuestSteps,
  handInCounterKey,
  isStepLatched,
  questStepJournal,
} from './steps'

// The Grand Feast (QST-0001) on the launch content players load: briefing,
// optional Cook step, hand-in at the King.

const rawDatabase = JSON.parse(readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'))
const { launch: db } = prepareDatabase(rawDatabase)
const NOW = Date.parse('2026-10-14T00:00:00.000Z')

const THRONE_ROOM = 'LOC-0016'
const FEAST = 'QST-0001'
const BRIEFING = 'QSTP-0001'
const COOK = 'QSTP-0036'
const HAND_IN = 'QSTP-0002'
const BAKED_POTATO = 'ITEM-0058'
const COOKED_PERCH = 'ITEM-0059'
const GOLDEN_SPUD = 'ITEM-0026'
const COOKING = 'SKL-0007'
const BAKE_POTATO = 'RCP-0001'

function fresh(): PlayerSave {
  return { ...createNewSave(db, NOW), currentLocationId: THRONE_ROOM }
}

function withQuest(save: PlayerSave, status: QuestProgress['status'], counters: Record<string, number>): PlayerSave {
  const row: QuestProgress = { questId: FEAST, status, progress: 0, counters }
  return { ...save, quests: [...save.quests.filter((quest) => quest.questId !== FEAST), row] }
}

function setCount(save: PlayerSave, itemId: string, quantity: number): PlayerSave {
  const cleared = { ...save, inventory: save.inventory.filter((stack) => stack.itemId !== itemId) }
  return quantity > 0 ? addItemToInventory(cleared, itemId, quantity) : cleared
}

function reload(save: PlayerSave): PlayerSave {
  return parseSave(JSON.parse(JSON.stringify(save)), NOW)
}

function picked(save: PlayerSave, dialogueId: string, nodeId: string, choiceId: string): DialogueResult {
  const result = chooseDialogue(db, save, dialogueId, nodeId, choiceId)
  expect(result.ok, `${choiceId}: ${result.reason}`).toBe(true)
  return result
}

function accept(): PlayerSave {
  return picked(fresh(), 'DLG-0011', 'DNODE-0018', 'DCH-0023').save
}

function stepOf(save: PlayerSave): string | null {
  return getCurrentStepId(db, save, getQuest(db, FEAST)!)
}

function kingChoices(save: PlayerSave): string[] {
  return startDialogue(db, save, 'DLG-0012').view?.choices.map((choice) => choice.choiceId) ?? []
}

/** Hands in everything the King still needs, then takes "The feast is ready." */
function finishAtTheKing(save: PlayerSave): PlayerSave {
  const handedIn = picked(save, 'DLG-0012', 'DNODE-0020', 'DCH-0026')
  expect(handedIn.questCompletions).toEqual([])
  const paid = picked(handedIn.save, 'DLG-0012', 'DNODE-0022', 'DCH-0031')
  expect(paid.questCompletions.map((completion) => completion.questId)).toEqual([FEAST])
  return paid.save
}

function expectPaid(save: PlayerSave): void {
  expect(getQuestProgress(save, FEAST).status).toBe('completed')
  expect(getSkillProgress(save, COOKING).xp).toBe(10_000)
  expect(bagCount(save, GOLDEN_SPUD)).toBe(1)
  expect(courtyardBotanyUnlocked(save)).toBe(true)
}

describe('The Grand Feast cook step', () => {
  it('authors the Cook step as an optional Hold between the briefing and the hand-in', () => {
    const steps = getQuestSteps(db, FEAST)
    expect(steps.map((step) => step['Step ID'])).toEqual([BRIEFING, COOK, HAND_IN])
    expect(steps.map((step) => step['Step Order'])).toEqual([1, 2, 3])

    const cook = steps[1]!
    expect(cook['Journal Label']).toBe('Cook food for the feast')
    expect(cook.Notes).toBe('Hold: ITEM-0058 x10, ITEM-0059 x10; Optional')
    // `Optional` is its own semicolon-separated field, which is what the engine parses.
    expect((cook.Notes ?? '').split(';').map((field) => field.trim())).toContain('Optional')
    expect(dialogueStepType(cook)).toBeNull()
    expect(cook['Step Items']).toBe('ITEM-0058:10;ITEM-0059:10')
    expect(cook['Step NPC']).toBeNull()
    expect(cook.Status).toBe('Planned')
    expect(cook['Release Phase']).toBe('Launch')
    expect(parseNotesObjectives(cook.Notes ?? '').holds).toEqual([
      { targetId: BAKED_POTATO, quantity: 10 },
      { targetId: COOKED_PERCH, quantity: 10 },
    ])

    const handIn = steps[2]!
    expect(handIn['Journal Label']).toBe('Bring the food to the King')
    expect(handIn['Step Type']).toBe('HandIn')
    expect(handIn['Step Items']).toBe('ITEM-0058:10;ITEM-0059:10')
    expect(handIn['Step NPC']).toBe('NPC-0001')
  })

  it('keeps the rewards, the King dialogue and the quest lines as they were', () => {
    const quest = getQuest(db, FEAST)!
    expect(quest['Reward XP Skill ID']).toBe(COOKING)
    expect(quest['Reward XP Amount']).toBe(10_000)
    expect(quest['Reward Item ID']).toBe(GOLDEN_SPUD)
    expect(quest['Reward Item Quantity']).toBe(1)

    const choice = (choiceId: string) => db.DialogueChoices.find((row) => row['Choice ID'] === choiceId)!
    expect(db.Dialogues.find((row) => row['Dialogue ID'] === 'DLG-0012')?.Condition).toBe(
      'quest_active:QST-0001;!quest_step:QST-0001:QSTP-0001',
    )
    expect(choice('DCH-0026').Condition).toBe('quest_step:QST-0001:QSTP-0002')
    expect(choice('DCH-0026').Action).toBe('hand_in:QST-0001:QSTP-0002')
    expect(choice('DCH-0030').Condition).toBe('quest_active:QST-0001;!quest_step:QST-0001:QSTP-0002')
    expect(choice('DCH-0031').Condition).toBe('quest_active:QST-0001;!quest_step:QST-0001:QSTP-0002')
    expect(choice('DCH-0032').Condition).toBe('quest_step:QST-0001:QSTP-0002')

    expect(db.QuestDialogue.filter((row) => row['Quest ID'] === FEAST).map((row) => row['Dialogue ID'])).toEqual([
      'QDL-0007',
      'QDL-0024',
    ])
  })

  it('finishes at the King after cooking the food', () => {
    let save = accept()
    expect(stepOf(save)).toBe(HAND_IN)
    expect(isStepLatched(save, FEAST, COOK)).toBe(false)

    // Bake ten potatoes and ten perch; the cooking tick latches the finished step.
    save = setCount(setCount(save, BAKED_POTATO, 10), COOKED_PERCH, 10)
    save = applyQuestProcessProgress(db, save, BAKE_POTATO)
    expect(isStepLatched(save, FEAST, COOK)).toBe(true)
    expect(stepOf(save)).toBe(HAND_IN)
    expect(questStepJournal(db, save, getQuest(db, FEAST)!)).toEqual([
      { key: BRIEFING, label: 'Hear what the King needs', state: 'done' },
      { key: COOK, label: 'Cook food for the feast', state: 'done' },
      { key: HAND_IN, label: 'Bring the food to the King', state: 'current' },
    ])

    expect(dialoguesForNpc(db, save, 'NPC-0001')[0]).toBe('DLG-0012')
    expect(kingChoices(save)).toContain('DCH-0026')
    expect(kingChoices(save)).not.toContain('DCH-0030')
    expect(completeQuest(db, save, FEAST).ok).toBe(false)

    save = finishAtTheKing(save)
    expect(bagCount(save, BAKED_POTATO)).toBe(0)
    expect(bagCount(save, COOKED_PERCH)).toBe(0)
    expectPaid(save)
  })

  it('opens the hand-in right away when the food is obtained another way', () => {
    let save = accept()
    // Bought or gifted elsewhere: nothing was cooked, so no cooking tick ran.
    save = setCount(setCount(save, BAKED_POTATO, 10), COOKED_PERCH, 10)
    expect(isStepLatched(save, FEAST, COOK)).toBe(false)
    expect(stepOf(save)).toBe(HAND_IN)
    expect(dialoguesForNpc(db, save, 'NPC-0001')[0]).toBe('DLG-0012')
    expect(kingChoices(save)).toContain('DCH-0026')
    expect(kingChoices(save)).not.toContain('DCH-0030')

    // Walking into the throne room is the tick that latches the held food.
    save = applyQuestVisitProgress(db, save, THRONE_ROOM)
    expect(stepOf(save)).toBe(HAND_IN)
    expectPaid(finishAtTheKing(save))
  })

  it('skips cooking and still completes at QSTP-0002 with 10,000 Cooking XP and the Golden Spud', () => {
    let save = accept()
    // After the briefing the hand-in is already current; the Cook step is skipped.
    expect(stepOf(save)).toBe(HAND_IN)
    expect(isStepLatched(save, FEAST, COOK)).toBe(false)

    // Food obtained elsewhere — no cooking tick, no step:QSTP-0036 latch.
    save = setCount(setCount(save, BAKED_POTATO, 10), COOKED_PERCH, 10)
    expect(isStepLatched(save, FEAST, COOK)).toBe(false)
    expect(stepOf(save)).toBe(HAND_IN)
    expect(kingChoices(save)).toContain('DCH-0026')

    save = finishAtTheKing(save)
    expect(isStepLatched(save, FEAST, COOK)).toBe(false)
    expectPaid(save)
  })

  it('hands the food in a few at a time without ever holding the full order', () => {
    let save = accept()
    expect(stepOf(save)).toBe(HAND_IN)
    expect(chooseDialogue(db, save, 'DLG-0012', 'DNODE-0020', 'DCH-0026').code).toBe('nothing_to_hand_in')

    const first = picked(setCount(save, BAKED_POTATO, 6), 'DLG-0012', 'DNODE-0020', 'DCH-0026')
    expect(first.itemDeltas).toEqual([{ itemId: BAKED_POTATO, qty: -6 }])
    save = reload(picked(first.save, 'DLG-0012', 'DNODE-0022', 'DCH-0032').save)
    expect(stepOf(save)).toBe(HAND_IN)
    expect(isStepLatched(save, FEAST, COOK)).toBe(false)

    save = setCount(setCount(save, BAKED_POTATO, 4), COOKED_PERCH, 10)
    save = finishAtTheKing(save)
    expect(isStepLatched(save, FEAST, COOK)).toBe(false)
    expectPaid(save)
  })

  it('loads a save made before the Cook step at the hand-in with its counts kept', () => {
    // Saved on the old two-step quest: briefed, six potatoes already with the
    // King, four more and the perch in the bag. The Cook step was never a step
    // for this player, so it has no latch and the bag is short of ten potatoes.
    const before = withQuest(fresh(), 'active', {
      'talk:NPC-0001': 1,
      'talk:NPC-0001:QSTP-0001': 1,
      'step:QSTP-0001': 1,
      [handInCounterKey(HAND_IN, BAKED_POTATO)]: 6,
    })
    let save = reload(setCount(setCount(before, BAKED_POTATO, 4), COOKED_PERCH, 10))

    expect(stepOf(save)).toBe(HAND_IN)
    expect(isStepLatched(save, FEAST, COOK)).toBe(false)
    expect(getQuestProgress(save, FEAST).counters?.[handInCounterKey(HAND_IN, BAKED_POTATO)]).toBe(6)
    expect(kingChoices(save)).toEqual(expect.arrayContaining(['DCH-0026']))
    expect(kingChoices(save)).not.toContain('DCH-0030')

    const handedIn = picked(save, 'DLG-0012', 'DNODE-0020', 'DCH-0026')
    expect(handedIn.itemDeltas).toEqual([
      { itemId: BAKED_POTATO, qty: -4 },
      { itemId: COOKED_PERCH, qty: -10 },
    ])
    save = picked(handedIn.save, 'DLG-0012', 'DNODE-0022', 'DCH-0031').save
    expectPaid(save)
  })
})
