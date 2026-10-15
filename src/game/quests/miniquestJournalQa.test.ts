import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { addItemToInventory } from '../activity/rewards'
import { prepareDatabase } from '../data/loadDatabase'
import { chooseDialogue, dialoguesForNpc, startDialogue } from '../dialogue/engine'
import { logCompletion, miniQuestJournal, questJournalSteps, questLog } from '../log/log'
import { npcConversation, questSpokenLine, type NpcQuestBlock } from '../npcs/conversation'
import {
  applyQuestActionProgress,
  applyQuestAutoStartOnSeed,
} from './progress'
import { getQuest, getQuestProgress } from './quests'
import { getCurrentStepId, questStepJournal } from './steps'
import { createNewSave } from '../save/saveStore'
import type { PlayerSave } from '../save/types'
import { plantBotanySelection } from '../timers/locationTimers'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)
const { launch } = prepareDatabase(rawDatabase)

const FARMER_DESCRIPTION = 'A farmer who lives at the farm.'
const FENNEL = 'NPC-0014'
const GREEN_THUMB = 'QST-0011'
const FEAST = 'QST-0001'
const POTATO_SEED = 'ITEM-0324'
const COMPOST = 'ITEM-0377'
const COMPOST_ACTION = 'ACN-0199'

const STEP_TALK = 'QSTP-0023'
const STEP_COMPOST = 'QSTP-0024'
const STEP_PLANT = 'QSTP-0034'
const STEP_RETURN = 'QSTP-0035'

function fennel() {
  return launch.NPCs.find((row) => row['NPC ID'] === FENNEL)!
}

function spokenBlock(talkLine: string | null, idlePrompt = ''): NpcQuestBlock {
  return {
    questId: GREEN_THUMB,
    name: 'Green Thumb',
    summary: null,
    status: 'active',
    completedNote: '',
    acceptLabel: 'Accept',
    donateLabel: 'Donate',
    pitchLine: null,
    lines: [],
    progressLines: [],
    goldOwned: 0,
    goldRequired: 0,
    ready: false,
    canAccept: false,
    canDonate: false,
    donated: false,
    canTurnIn: false,
    canTalk: Boolean(talkLine),
    talkLabel: 'Talk',
    talkLine,
    canBribe: false,
    bribeLabel: 'Bribe',
    canChooseCombat: false,
    combatLabel: 'Fight',
    idlePrompt,
  }
}

function startGreenThumb(): PlayerSave {
  const save = applyQuestAutoStartOnSeed(launch, {
    ...createNewSave(launch),
    currentLocationId: 'LOC-0001',
    inventory: [{ itemId: POTATO_SEED, quantity: 1 }],
    quests: [{ questId: 'QST-0006', status: 'completed', progress: 1 }],
  })
  expect(getQuestProgress(save, GREEN_THUMB).status).toBe('active')
  return save
}

function journal(save: PlayerSave) {
  const quest = getQuest(launch, GREEN_THUMB)!
  const row = miniQuestJournal(launch, save).find((entry) => entry.questId === GREEN_THUMB)!
  return {
    quest,
    row,
    shared: questJournalSteps(launch, save, quest),
    steps: questStepJournal(launch, save, quest),
  }
}

function greenThumbBlock(save: PlayerSave) {
  return npcConversation(launch, save, fennel()).quests.find((row) => row.questId === GREEN_THUMB)!
}

function questsSection(save: PlayerSave) {
  return logCompletion(launch, save).sections.find((row) => row.section === 'quests')!
}

function nodeLine(nodeId: string): string {
  return launch.DialogueNodes.find((row) => row['Node ID'] === nodeId)!.Line
}

function assertNoFarmerLine(...parts: Array<string | null | undefined>) {
  for (const part of parts) {
    expect(part ?? '', JSON.stringify(part)).not.toContain(FARMER_DESCRIPTION)
  }
}

describe('QA: miniquest journal', () => {
  it('lists and ticks Green Thumb steps through the shared journal logic', () => {
    let save = startGreenThumb()
    const quest = getQuest(launch, GREEN_THUMB)!
    expect(questLog(launch, save).some((row) => row.questId === GREEN_THUMB)).toBe(false)

    let snap = journal(save)
    expect(snap.row.steps).toEqual(snap.shared)
    expect(snap.row.steps).toEqual(snap.steps)
    expect(getCurrentStepId(launch, save, quest)).toBe(STEP_TALK)
    expect(snap.row.steps.find((step) => step.key === STEP_TALK)).toEqual({
      key: STEP_TALK,
      label: 'Speak with Fennel at the farm',
      state: 'current',
    })

    save = chooseDialogue(launch, save, 'DLG-0007', 'DNODE-0011', 'DCH-0014').save
    snap = journal(save)
    expect(snap.row.steps).toEqual(snap.shared)
    expect(snap.row.steps).toEqual(snap.steps)
    expect(snap.row.steps.find((step) => step.key === STEP_TALK)?.state).toBe('done')
    expect(snap.row.steps.find((step) => step.key === STEP_COMPOST)).toEqual({
      key: STEP_COMPOST,
      label: 'Gather compost and speak with Fennel',
      state: 'current',
    })

    save = applyQuestActionProgress(launch, addItemToInventory(save, COMPOST, 1), COMPOST_ACTION, 1)
    save = chooseDialogue(launch, save, 'DLG-0008', 'DNODE-0013', 'DCH-0017').save
    snap = journal(save)
    expect(snap.row.steps).toEqual(snap.shared)
    expect(getCurrentStepId(launch, save, quest)).toBe(STEP_PLANT)
    expect(snap.row.steps.find((step) => step.key === STEP_COMPOST)?.state).toBe('done')
    expect(snap.row.steps.find((step) => step.key === STEP_PLANT)).toEqual({
      key: STEP_PLANT,
      label: 'Plant a potato seed with compost',
      state: 'current',
    })

    const planted = plantBotanySelection(launch, save, [POTATO_SEED], 0, true)
    expect(planted.ok).toBe(true)
    if (!planted.ok) return
    save = planted.save
    snap = journal(save)
    expect(snap.row.steps).toEqual(snap.shared)
    expect(getCurrentStepId(launch, save, quest)).toBe(STEP_RETURN)
    expect(snap.row.steps.find((step) => step.key === STEP_PLANT)?.state).toBe('done')
    expect(snap.row.steps.find((step) => step.key === STEP_RETURN)).toEqual({
      key: STEP_RETURN,
      label: 'Return to Fennel',
      state: 'current',
    })

    save = chooseDialogue(launch, save, 'DLG-0010', 'DNODE-0016', 'DCH-0021').save
    snap = journal(save)
    expect(snap.row.completed).toBe(true)
    expect(snap.row.steps).toEqual(snap.shared)
    expect(
      snap.row.steps.filter((step) => step.key.startsWith('QSTP-')).every((step) => step.state === 'done'),
    ).toBe(true)
  })

  it('keeps quest-log % still when a miniquest completes, and raises it for a normal quest', () => {
    const save = startGreenThumb()
    const before = questsSection(save)
    expect(before.total).toBeGreaterThan(0)

    const miniDone: PlayerSave = {
      ...save,
      quests: save.quests.map((row) =>
        row.questId === GREEN_THUMB ? { ...row, status: 'completed' as const } : row,
      ),
    }
    const afterMini = questsSection(miniDone)
    expect(afterMini.done).toBe(before.done)
    expect(afterMini.total).toBe(before.total)
    expect(afterMini.percent).toBe(before.percent)
    expect(afterMini.label).toBe(before.label)

    const feastDone: PlayerSave = {
      ...miniDone,
      quests: [
        ...miniDone.quests.filter((row) => row.questId !== FEAST),
        { questId: FEAST, status: 'completed', progress: 10 },
      ],
    }
    const afterFeast = questsSection(feastDone)
    expect(afterFeast.done).toBe(before.done + 1)
    expect(afterFeast.total).toBe(before.total)
    expect(afterFeast.percent).toBeGreaterThanOrEqual(before.percent)
    expect(afterFeast.label).not.toBe(before.label)
  })
})

describe('QA: Green Thumb spoken lines', () => {
  it('never shows Fennel description on a full run, and questSpokenLine has no description fallback', () => {
    expect(questSpokenLine(spokenBlock(null, ''))).toBe('')
    expect(questSpokenLine(spokenBlock('  ', '  '))).toBe('')
    expect(questSpokenLine(spokenBlock(null, 'Idle copy'))).toBe('Idle copy')
    expect(questSpokenLine(spokenBlock('Talk copy', 'Idle copy'))).toBe('Talk copy')
    expect(questSpokenLine(spokenBlock(null, ''))).not.toBe(FARMER_DESCRIPTION)

    const lines: Array<string | null | undefined> = []
    const record = (save: PlayerSave, extra: Array<string | null | undefined> = []) => {
      const conversation = npcConversation(launch, save, fennel())
      const block = conversation.quests.find((row) => row.questId === GREEN_THUMB)
      if (block) {
        lines.push(questSpokenLine(block), block.talkLine, block.idlePrompt, block.completedNote)
      }
      lines.push(conversation.description, ...extra)
    }

    let save = startGreenThumb()
    record(save, [greenThumbBlock(save).talkLine, startDialogue(launch, save, 'DLG-0007').view?.line])
    expect(questSpokenLine(greenThumbBlock(save))).toMatch(/found a seed/i)

    const firstTalk = chooseDialogue(launch, save, 'DLG-0007', 'DNODE-0011', 'DCH-0014')
    expect(firstTalk.ok).toBe(true)
    save = firstTalk.save
    record(save, [firstTalk.message])
    expect(questSpokenLine(greenThumbBlock(save))).toBe('')
    expect(greenThumbBlock(save).talkLine).toBeNull()
    expect(greenThumbBlock(save).idlePrompt).toBe('')

    save = applyQuestActionProgress(launch, addItemToInventory(save, COMPOST, 1), COMPOST_ACTION, 1)
    record(save, [startDialogue(launch, save, 'DLG-0008').view?.line])
    expect(questSpokenLine(greenThumbBlock(save))).toMatch(/compost/i)

    const compostTalk = chooseDialogue(launch, save, 'DLG-0008', 'DNODE-0013', 'DCH-0017')
    expect(compostTalk.ok).toBe(true)
    save = compostTalk.save
    record(save, [compostTalk.message, startDialogue(launch, save, 'DLG-0009').view?.line])
    expect(questSpokenLine(greenThumbBlock(save))).toBe('')

    const planted = plantBotanySelection(launch, save, [POTATO_SEED], 0, true)
    expect(planted.ok).toBe(true)
    if (!planted.ok) return
    save = planted.save
    record(save, [startDialogue(launch, save, 'DLG-0010').view?.line])
    expect(questSpokenLine(greenThumbBlock(save))).toMatch(/Well done/i)

    const finished = chooseDialogue(launch, save, 'DLG-0010', 'DNODE-0016', 'DCH-0021')
    expect(finished.ok).toBe(true)
    save = finished.save
    record(save, [finished.message])

    assertNoFarmerLine(...lines)
    expect(fennel().Description).toBe('')
  })

  it('speaks Green Thumb lines in step order: talk, compost, plant reminder, return and reward', () => {
    const dialogues = launch.Dialogues.filter((row) => row['NPC ID'] === FENNEL)
      .filter((row) => (row.Condition ?? '').includes(GREEN_THUMB))
      .sort((left, right) => left['Dialogue ID'].localeCompare(right['Dialogue ID']))
    expect(dialogues.map((row) => [row['Dialogue ID'], row.Condition])).toEqual([
      ['DLG-0007', `quest_step:${GREEN_THUMB}:${STEP_TALK}`],
      ['DLG-0008', `quest_step:${GREEN_THUMB}:${STEP_COMPOST}`],
      ['DLG-0009', `quest_step:${GREEN_THUMB}:${STEP_PLANT}`],
      ['DLG-0010', `quest_step:${GREEN_THUMB}:${STEP_RETURN}`],
    ])

    const questLines = launch.QuestDialogue.filter((row) => row['Quest ID'] === GREEN_THUMB)
    expect(questLines.map((row) => [row.Notes, row.Line])).toEqual([
      [`RequiresStep: ${STEP_TALK}`, nodeLine('DNODE-0011')],
      [`RequiresStep: ${STEP_COMPOST}`, nodeLine('DNODE-0013')],
      ['When: completed', nodeLine('DNODE-0017')],
      [`RequiresStep: ${STEP_RETURN}`, nodeLine('DNODE-0016')],
    ])

    let save = startGreenThumb()
    expect(getCurrentStepId(launch, save, getQuest(launch, GREEN_THUMB)!)).toBe(STEP_TALK)
    expect(dialoguesForNpc(launch, save, FENNEL)[0]).toBe('DLG-0007')
    expect(startDialogue(launch, save, 'DLG-0007').view?.line).toBe(nodeLine('DNODE-0011'))
    expect(greenThumbBlock(save).talkLine).toBe(nodeLine('DNODE-0011'))

    save = chooseDialogue(launch, save, 'DLG-0007', 'DNODE-0011', 'DCH-0014').save
    save = applyQuestActionProgress(launch, addItemToInventory(save, COMPOST, 1), COMPOST_ACTION, 1)
    expect(getCurrentStepId(launch, save, getQuest(launch, GREEN_THUMB)!)).toBe(STEP_COMPOST)
    expect(dialoguesForNpc(launch, save, FENNEL)[0]).toBe('DLG-0008')
    expect(startDialogue(launch, save, 'DLG-0008').view?.line).toBe(nodeLine('DNODE-0013'))
    expect(greenThumbBlock(save).talkLine).toBe(nodeLine('DNODE-0013'))

    save = chooseDialogue(launch, save, 'DLG-0008', 'DNODE-0013', 'DCH-0017').save
    expect(getCurrentStepId(launch, save, getQuest(launch, GREEN_THUMB)!)).toBe(STEP_PLANT)
    expect(dialoguesForNpc(launch, save, FENNEL)[0]).toBe('DLG-0009')
    expect(startDialogue(launch, save, 'DLG-0009').view?.line).toBe(nodeLine('DNODE-0015'))
    expect(startDialogue(launch, save, 'DLG-0009').view?.line).toMatch(/patch/i)

    const planted = plantBotanySelection(launch, save, [POTATO_SEED], 0, true)
    expect(planted.ok).toBe(true)
    if (!planted.ok) return
    save = planted.save
    expect(getCurrentStepId(launch, save, getQuest(launch, GREEN_THUMB)!)).toBe(STEP_RETURN)
    expect(dialoguesForNpc(launch, save, FENNEL)[0]).toBe('DLG-0010')
    expect(startDialogue(launch, save, 'DLG-0010').view?.line).toBe(nodeLine('DNODE-0016'))
    expect(greenThumbBlock(save).talkLine).toBe(nodeLine('DNODE-0016'))

    save = chooseDialogue(launch, save, 'DLG-0010', 'DNODE-0016', 'DCH-0021').save
    expect(getQuestProgress(save, GREEN_THUMB).status).toBe('completed')
    expect(greenThumbBlock(save).completedNote).toBe(nodeLine('DNODE-0017'))
  })
})

describe('QA: Fennel content', () => {
  it('clears Fennel description and drops the old farm line', () => {
    expect(fennel().Description).toBe('')
    expect(fennel().Description).not.toBe(FARMER_DESCRIPTION)
    expect(
      rawDatabase.NPCs.filter((row: { Description?: string }) => row.Description === FARMER_DESCRIPTION),
    ).toEqual([])
    expect(JSON.stringify(rawDatabase.NPCs)).not.toContain(FARMER_DESCRIPTION)
  })
})
