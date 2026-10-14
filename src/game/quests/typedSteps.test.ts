import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { chooseDialogue } from '../dialogue/engine'
import { stepProgressGroup } from '../dialogue/stepProgress'
import { talkWithQuestNpc } from '../npcs/conversation'
import { createNewSave } from '../save/saveStore'
import type { PlayerSave } from '../save/types'
import {
  canPlantBotanySeed,
  discoverTimerSpotsForLocation,
  FARM_LOCATION_ID,
  farmBotanyUnlocked,
} from '../timers/locationTimers'
import { getQuest, getQuestProgress } from './quests'
import { applyQuestStepUnlocks, getCurrentStepId, isStepComplete, isStepPassed } from './steps'

type Row = Record<string, unknown>

const content = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
) as Record<string, Row[]>

/** Step typing as SYS-01 PR B (#323) ships it, applied to the live step rows. */
const TYPED: Record<string, Row> = {
  'QSTP-0014': { 'Step Type': 'Show', 'Step Items': 'ITEM-0025:5', 'Step NPC': 'NPC-0014' },
  'QSTP-0016': { 'Step Type': 'Show', 'Step Items': 'ITEM-0058:5', 'Step NPC': 'NPC-0014' },
  'QSTP-0022': { 'Step Type': 'Talk', 'Step NPC': 'NPC-0014' },
  'QSTP-0023': { 'Step Type': 'Talk', 'Step NPC': 'NPC-0014' },
  'QSTP-0024': { 'Step Type': 'Talk', 'Step NPC': 'NPC-0014' },
  'QSTP-0035': { 'Step Type': 'Talk', 'Step NPC': 'NPC-0014' },
}

function launchRow(row: Row): Row {
  return { Status: 'Confirmed', 'Release Phase': 'Launch', Notes: null, ...row }
}

const rawDatabase = {
  ...content,
  QuestSteps: [
    ...content.QuestSteps!.map((row) => ({ ...row, ...(TYPED[row['Step ID'] as string] ?? {}) })),
    launchRow({
      'Step ID': 'QSTP-9202',
      'Quest ID': 'QST-0001',
      'Step Order': 4,
      'Journal Label': 'Later talk',
      'Step Type': 'Talk',
      'Step NPC': 'NPC-0001',
    }),
  ],
  Dialogues: [
    ...content.Dialogues!,
    launchRow({
      'Dialogue ID': 'DLG-9201',
      'Internal Key': 'dlg-9201',
      'Display Name': 'Fennel',
      'NPC ID': 'NPC-0014',
      'Start Node ID': 'DNODE-9201',
      Repeatable: true,
    }),
  ],
  DialogueNodes: [...content.DialogueNodes!, launchRow({ 'Node ID': 'DNODE-9201', 'Dialogue ID': 'DLG-9201', Line: 'Hello.' })],
  DialogueChoices: [
    ...content.DialogueChoices!,
    launchRow({
      'Choice ID': 'DCH-9201',
      'Node ID': 'DNODE-9201',
      Label: 'About the farm',
      'Next Node ID': null,
      Condition: 'quest_step:QST-0011:QSTP-0023',
      Action: 'talk_flag:QST-0011:QSTP-0023',
      'Sort Order': 1,
    }),
  ],
}
const { launch: db } = prepareDatabase(rawDatabase)
const { launch: untypedDb } = prepareDatabase({
  ...content,
  QuestSteps: content.QuestSteps!.map((row) => {
    if (!TYPED[row['Step ID'] as string]) return row
    const { 'Step Type': _type, 'Step Items': _items, 'Step NPC': _npc, ...untyped } = row
    return untyped
  }),
})
const START_MS = Date.parse('2026-01-01T00:00:00.000Z')

function withQuest(questId: string, counters: Record<string, number>, save?: PlayerSave): PlayerSave {
  const base = save ?? { ...createNewSave(db, START_MS), currentLocationId: FARM_LOCATION_ID }
  const progress = Object.values(counters).reduce((sum, value) => sum + value, 0)
  return {
    ...base,
    quests: [...base.quests.filter((row) => row.questId !== questId), { questId, status: 'active', progress, counters }],
  }
}

const gettingStarted = getQuest(db, 'QST-0006')!
const EARLY = { 'step:QSTP-0013': 1, 'step:QSTP-0014': 1, 'step:QSTP-0015': 1 }

describe('typed steps on saves already past them', () => {
  it('makes an old save show the cooked potatoes again when nothing shows it is past the step', () => {
    const save = withQuest('QST-0006', EARLY)
    expect(isStepPassed(db, save, 'QST-0006', 'QSTP-0016')).toBe(false)
    expect(getCurrentStepId(db, save, gettingStarted)).toBe('QSTP-0016')
  })

  it('counts an unmarked Show step as done once a later step is done', () => {
    const save = withQuest('QST-0006', { ...EARLY, 'step:QSTP-0022': 1 })
    expect(isStepPassed(db, save, 'QST-0006', 'QSTP-0016')).toBe(true)
    expect(getCurrentStepId(db, save, gettingStarted)).toBeNull()
    expect(stepProgressGroup(db, save, 'QST-0006', 'QSTP-0016')?.done).toBe(true)
  })

  it('counts an unmarked Show step as done once a later step is active', () => {
    const save = withQuest('QST-0006', { ...EARLY, 'talk:NPC-0014:QSTP-0022': 1 })
    expect(getCurrentStepId(db, save, gettingStarted)).toBe('QSTP-0022')
  })

  it('counts a later Notes-driven step met from saved counters', () => {
    const atShow = withQuest('QST-0006', { 'step:QSTP-0013': 1 })
    expect(getCurrentStepId(db, atShow, gettingStarted)).toBe('QSTP-0014')

    const cooked = withQuest('QST-0006', { 'step:QSTP-0013': 1, 'visit:LOC-0023': 1, 'process:RCP-0001': 5 })
    expect(isStepPassed(db, cooked, 'QST-0006', 'QSTP-0014')).toBe(true)
    expect(getCurrentStepId(db, cooked, gettingStarted)).toBe('QSTP-0016')
  })

  it('never writes a done mark for a passed step', () => {
    const save = withQuest('QST-0006', { ...EARLY, 'talk:NPC-0014:QSTP-0022': 1 })
    const after = applyQuestStepUnlocks(db, save)
    expect(getQuestProgress(after, 'QST-0006').counters).toEqual(getQuestProgress(save, 'QST-0006').counters)
  })

  it('refuses the dialogue action for a step the quest is past', () => {
    const save = withQuest('QST-0011', { 'step:QSTP-0024': 1 })
    expect(chooseDialogue(db, save, 'DLG-9201', 'DNODE-9201', 'DCH-9201')).toMatchObject({
      ok: false,
      code: 'not_available',
    })
  })
})

describe('farm patch for dialogue-only players (Green Thumb)', () => {
  it('stays locked while Green Thumb has no Fennel progress', () => {
    const save = withQuest('QST-0011', {})
    expect(farmBotanyUnlocked(db, save)).toBe(false)
    expect(canPlantBotanySeed(db, { ...save, inventory: [{ itemId: 'ITEM-0324', quantity: 1 }] }, 'ITEM-0324').ok).toBe(false)
  })

  it('unlocks when the dialogue Talk step with Fennel is done', () => {
    const save = withQuest('QST-0011', { 'step:QSTP-0023': 1 })
    expect(farmBotanyUnlocked(db, save)).toBe(true)
    expect(canPlantBotanySeed(db, { ...save, inventory: [{ itemId: 'ITEM-0324', quantity: 1 }] }, 'ITEM-0324').ok).toBe(true)
    expect(discoverTimerSpotsForLocation(db, save, FARM_LOCATION_ID).discoveredTimerSpotIds).toContain(
      `botany:${FARM_LOCATION_ID}`,
    )
  })

  it('unlocks when the quest is past that step even if it was never marked', () => {
    expect(farmBotanyUnlocked(db, withQuest('QST-0011', { 'step:QSTP-0024': 1 }))).toBe(true)
  })

  it('unlocks after talking to Fennel through dialogue only', () => {
    const save = withQuest('QST-0011', {})
    const talked = chooseDialogue(db, save, 'DLG-9201', 'DNODE-9201', 'DCH-9201')
    expect(talked.ok).toBe(true)
    expect(getQuestProgress(talked.save, 'QST-0011').counters).toEqual({ 'step:QSTP-0023': 1 })
    expect(farmBotanyUnlocked(db, talked.save)).toBe(true)
    expect(talked.save.discoveredTimerSpotIds).toContain(`botany:${FARM_LOCATION_ID}`)
  })

  it('still unlocks through the panel talk counter and on completion', () => {
    expect(farmBotanyUnlocked(db, withQuest('QST-0011', { 'talk:NPC-0014': 1 }))).toBe(true)
    const done = withQuest('QST-0011', {})
    expect(
      farmBotanyUnlocked(db, { ...done, quests: [{ questId: 'QST-0011', status: 'completed', progress: 0, counters: {} }] }),
    ).toBe(true)
  })

  it('ignores step marks on untyped steps, as before #323', () => {
    expect(farmBotanyUnlocked(untypedDb, withQuest('QST-0011', { 'step:QSTP-0023': 1 }))).toBe(false)
  })

  it('adds the farm timer spot after panel talk', () => {
    const talked = talkWithQuestNpc(db, withQuest('QST-0011', {}), 'NPC-0014')
    expect(talked.ok).toBe(true)
    if (!talked.ok) return
    expect(talked.save.discoveredTimerSpotIds).toContain(`botany:${FARM_LOCATION_ID}`)
  })
})

describe('HandIn steps only count with their step latch (option b)', () => {
  const feast = () => getQuest(db, 'QST-0001')!
  // Every save here is past the optional Cook step (QSTP-0036): it latched when the food was cooked.

  it('stays current when a later step is latched', () => {
    const save = withQuest('QST-0001', { 'step:QSTP-0001': 1, 'step:QSTP-0036': 1, 'step:QSTP-9202': 1 })
    expect(isStepPassed(db, save, 'QST-0001', 'QSTP-0002')).toBe(true)
    expect(isStepComplete(db, save, 'QST-0001', '', 'QSTP-0002')).toBe(false)
    expect(getCurrentStepId(db, save, feast())).toBe('QSTP-0002')
    expect(stepProgressGroup(db, save, 'QST-0001', 'QSTP-0002')?.done).toBe(false)
  })

  it('counts as done once the step latch is written', () => {
    const save = withQuest('QST-0001', { 'step:QSTP-0001': 1, 'step:QSTP-0036': 1, 'step:QSTP-0002': 1 })
    expect(isStepComplete(db, save, 'QST-0001', '', 'QSTP-0002')).toBe(true)
    expect(getCurrentStepId(db, save, feast())).toBe('QSTP-9202')
    expect(stepProgressGroup(db, save, 'QST-0001', 'QSTP-0002')?.done).toBe(true)
  })

  it('stays unfinished when only a partial hand-in counter is present', () => {
    const save = withQuest('QST-0001', {
      'step:QSTP-0001': 1,
      'step:QSTP-0036': 1,
      'handIn:QSTP-0002:ITEM-0058': 4,
      'step:QSTP-9202': 1,
    })
    expect(isStepComplete(db, save, 'QST-0001', '', 'QSTP-0002')).toBe(false)
    expect(getCurrentStepId(db, save, feast())).toBe('QSTP-0002')
    expect(stepProgressGroup(db, save, 'QST-0001', 'QSTP-0002')?.done).toBe(false)
  })
})
