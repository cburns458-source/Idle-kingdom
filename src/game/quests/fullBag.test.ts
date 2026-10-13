import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { DIALOGUE_PATCH, patchedDatabase } from '../../parity/scenarios/dialogue'
import { addItemToInventory } from '../activity/rewards'
import { getSkillProgress } from '../activity/xp'
import { prepareDatabase } from '../data/loadDatabase'
import { chooseDialogue } from '../dialogue/engine'
import { bagCount } from '../inventory/bag'
import { INVENTORY_SLOT_LIMIT } from '../inventory/capacity'
import { bribeForQuest, talkWithQuestNpc } from '../npcs/conversation'
import { createNewSave } from '../save/saveStore'
import { courtyardBotanyUnlocked } from '../timers/locationTimers'
import type { PlayerSave } from '../save/types'
import { applyGameCommand, type GameCommandResult } from '../server/authority'
import { latchStep } from './steps'
import {
  acceptQuest,
  applyQuestAutoCompleteOnVisit,
  bribeQuestNpc,
  completeQuest,
  getQuestProgress,
} from './quests'

const START_MS = Date.parse('2026-01-01T00:00:00.000Z')
const LOCATION = 'LOC-0002'
const NPC = 'NPC-9001'
const BAKED_POTATO = 'ITEM-0058'
const COOKED_PERCH = 'ITEM-0059'
const GOLDEN_SPUD = 'ITEM-0026'
const POTATO = 'ITEM-0025'
const NO_ROOM = 'No room in your bag. Free 1 slot and try again.'
const FAVOURITES_PROMPT = 'Some items are favourited. Do you still want to use them?'

type Row = Record<string, unknown>

function questRow(id: string, notes: string | null, extra: Row = {}): Row {
  return {
    'Quest ID': id,
    'Internal Key': id.toLowerCase(),
    'Display Name': id,
    'NPC ID': NPC,
    Summary: null,
    Pitch: null,
    Status: 'Confirmed',
    'Release Phase': 'Launch',
    Notes: notes,
    'Objective Type': null,
    'Objective Target ID': null,
    'Required Quantity': null,
    Repeatable: null,
    'Reward XP Skill ID': null,
    'Reward XP Amount': null,
    'Reward Item ID': null,
    'Reward Item Quantity': null,
    'Possible Rewards': null,
    ...extra,
  }
}

function talkStep(id: string, questId: string): Row {
  return {
    'Step ID': id,
    'Quest ID': questId,
    'Step Order': 1,
    'Journal Label': id,
    Notes: null,
    'Step Type': 'Talk',
    'Step Items': null,
    'Step NPC': NPC,
    Status: 'Confirmed',
    'Release Phase': 'Launch',
  }
}

const spud = { 'Reward Item ID': GOLDEN_SPUD, 'Reward Item Quantity': 1 }
const COOKING = 'SKL-0007'
const APOTHECARY = 'LOC-0026'

const rawDatabase = patchedDatabase({
  ...DIALOGUE_PATCH,
  Quests: [
    ...DIALOGUE_PATCH.Quests!,
    questRow('QST-9101', `Deliver: ${BAKED_POTATO} x5; RewardGold: 100`, spud),
    questRow('QST-9102', `Deliver: ${BAKED_POTATO} x5; RewardItem: ${POTATO} x3, ${COOKED_PERCH} x2`),
    questRow('QST-9103', `Deliver: ${BAKED_POTATO} x5; RewardGold: 250; RewardXp: SKL-0001 100; RewardBook: BOOK-0001`),
    questRow('QST-9104', 'AutoCompleteOnTalk', spud),
    questRow('QST-9105', 'AutoCompleteOnVisit', spud),
    questRow('QST-9106', `Deliver: ${BAKED_POTATO} x5`, { ...spud, 'Reward Mode': 'dialogue' }),
    questRow(
      'QST-9108',
      `Deliver: ${BAKED_POTATO} x5; RewardGold: 100; RewardXp: ${COOKING} 5000; UnlockLocation: ${APOTHECARY}; RewardBook: BOOK-0001`,
      spud,
    ),
  ] as never,
  QuestSteps: [
    ...DIALOGUE_PATCH.QuestSteps!,
    talkStep('QSTP-9104', 'QST-9104'),
    talkStep('QSTP-9105', 'QST-9105'),
  ] as never,
  DialogueChoices: [
    ...DIALOGUE_PATCH.DialogueChoices!,
    {
      'Choice ID': 'DCH-9108',
      'Node ID': 'DNODE-9031',
      Label: 'DCH-9108',
      'Next Node ID': null,
      Condition: 'quest_active:QST-9108',
      Action: 'complete_quest:QST-9108;set_flag:gift:QST-9108:done',
      'No Room Line': '',
      'Sort Order': 9,
      Status: 'Confirmed',
      'Release Phase': 'Launch',
      Notes: null,
    },
  ] as never,
})
const { launch: db } = prepareDatabase(rawDatabase)
const { launch: contentDb } = prepareDatabase(
  JSON.parse(readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8')),
)

function freshSave(): PlayerSave {
  return { ...createNewSave(db, START_MS), currentLocationId: LOCATION }
}

function started(questId: string, save: PlayerSave = freshSave()): PlayerSave {
  const accepted = acceptQuest(db, save, questId)
  if (!accepted.ok) throw new Error(accepted.reason)
  return accepted.save
}

function withStacks(save: PlayerSave, itemId: string, stacks: Array<[number, boolean]>): PlayerSave {
  return {
    ...save,
    inventory: [
      ...save.inventory.filter((stack) => stack.itemId !== itemId),
      ...stacks.map(([quantity, favorite]) => (favorite ? { itemId, quantity, favorite } : { itemId, quantity })),
    ],
  }
}

function fillBag(save: PlayerSave, free: number): PlayerSave {
  const inventory = save.inventory.filter((stack) => !stack.itemId.startsWith('ITEM-FILL-'))
  for (let index = 0; inventory.length < INVENTORY_SLOT_LIMIT - free; index += 1) {
    inventory.push({ itemId: `ITEM-FILL-${index}`, quantity: 1 })
  }
  return { ...save, inventory }
}

function snapshot(save: PlayerSave): string {
  return JSON.stringify(save)
}

function command(save: PlayerSave, name: string, args: Record<string, unknown> = {}): GameCommandResult {
  return applyGameCommand(rawDatabase, { command: name, args, save, nowMs: START_MS, random: () => 0 })
}

describe('legacy quest rewards with a full bag', () => {
  it('refuses the turn-in with no_room and leaves everything as it was', () => {
    const save = fillBag(withStacks(started('QST-9101'), BAKED_POTATO, [[7, false]]), 0)
    const before = snapshot(save)

    const result = completeQuest(db, save, 'QST-9101')

    expect(result).toEqual({ ok: false, reason: NO_ROOM, code: 'no_room', noRoom: { slotsNeeded: 1, slotsFree: 0 } })
    expect(snapshot(save)).toBe(before)
    expect(getQuestProgress(save, 'QST-9101').status).toBe('active')
  })

  it('succeeds once a slot is free, granting the item once', () => {
    const save = fillBag(withStacks(started('QST-9101'), BAKED_POTATO, [[7, false]]), 1)
    const result = completeQuest(db, save, 'QST-9101')
    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(bagCount(result.save, GOLDEN_SPUD)).toBe(1)
    expect(bagCount(result.save, BAKED_POTATO)).toBe(2)
    expect(result.save.gold).toBe(save.gold + 100)
    expect(getQuestProgress(result.save, 'QST-9101').status).toBe('completed')
    expect(completeQuest(db, result.save, 'QST-9101').ok).toBe(false)
  })

  it('counts the slot a delivery frees', () => {
    const save = fillBag(withStacks(started('QST-9101'), BAKED_POTATO, [[5, false]]), 0)
    const result = completeQuest(db, save, 'QST-9101')
    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(bagCount(result.save, GOLDEN_SPUD)).toBe(1)
    expect(bagCount(result.save, BAKED_POTATO)).toBe(0)
  })

  it('merges into a stack already in a full bag', () => {
    const save = fillBag(withStacks(withStacks(started('QST-9101'), BAKED_POTATO, [[7, false]]), GOLDEN_SPUD, [[2, false]]), 0)
    const result = completeQuest(db, save, 'QST-9101')
    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(bagCount(result.save, GOLDEN_SPUD)).toBe(3)
  })

  it('grants none of a multi-item reward when only part fits', () => {
    const save = fillBag(withStacks(started('QST-9102'), BAKED_POTATO, [[7, false]]), 1)
    const before = snapshot(save)
    expect(completeQuest(db, save, 'QST-9102')).toEqual({
      ok: false,
      reason: NO_ROOM,
      code: 'no_room',
      noRoom: { slotsNeeded: 2, slotsFree: 1 },
    })
    expect(snapshot(save)).toBe(before)

    const roomy = completeQuest(db, fillBag(save, 2), 'QST-9102')
    expect(roomy.ok).toBe(true)
    if (!roomy.ok) return
    expect(bagCount(roomy.save, POTATO)).toBe(3)
    expect(bagCount(roomy.save, COOKED_PERCH)).toBe(2)
  })

  it('pays gold, XP and books into a full bag', () => {
    const save = fillBag(withStacks(started('QST-9103'), BAKED_POTATO, [[7, false]]), 0)
    const result = completeQuest(db, save, 'QST-9103')
    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(result.save.gold).toBe(save.gold + 250)
    expect(result.save.unlockedBookIds).toContain('BOOK-0001')
  })

  it('leaves dialogue-mode quests alone: they pay nothing on completion', () => {
    const save = fillBag(withStacks(started('QST-9106'), BAKED_POTATO, [[7, false]]), 0)
    const result = completeQuest(db, save, 'QST-9106')
    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(bagCount(result.save, GOLDEN_SPUD)).toBe(0)
    expect(getQuestProgress(result.save, 'QST-9106').status).toBe('completed')
  })

  it('keeps an auto-complete-on-talk quest active and finishes it on the next talk', () => {
    const save = fillBag(latchStep(started('QST-9104'), 'QST-9104', 'QSTP-9104'), 0)
    const blocked = talkWithQuestNpc(db, save, NPC)
    expect(blocked.ok).toBe(true)
    if (!blocked.ok) return
    expect(getQuestProgress(blocked.save, 'QST-9104').status).toBe('active')
    expect(bagCount(blocked.save, GOLDEN_SPUD)).toBe(0)

    const retried = talkWithQuestNpc(db, fillBag(blocked.save, 1), NPC)
    expect(retried.ok).toBe(true)
    if (!retried.ok) return
    expect(getQuestProgress(retried.save, 'QST-9104').status).toBe('completed')
    expect(bagCount(retried.save, GOLDEN_SPUD)).toBe(1)
  })

  it('keeps an auto-complete-on-visit quest active and finishes it on the next visit', () => {
    const save = fillBag(latchStep(started('QST-9105'), 'QST-9105', 'QSTP-9105'), 0)
    const blocked = applyQuestAutoCompleteOnVisit(db, save)
    expect(blocked.completions).toEqual([])
    expect(snapshot(blocked.save)).toBe(snapshot(save))

    const retried = applyQuestAutoCompleteOnVisit(db, fillBag(blocked.save, 1))
    expect(retried.completions.map((line) => line.questId)).toEqual(['QST-9105'])
    expect(bagCount(retried.save, GOLDEN_SPUD)).toBe(1)
  })

  it('passes no_room through a dialogue complete_quest on a legacy quest', () => {
    const save = fillBag(freshSave(), 0)
    const result = chooseDialogue(db, save, 'DLG-9004', 'DNODE-9031', 'DCH-9031')
    expect(result).toMatchObject({ ok: false, code: 'no_room', reason: NO_ROOM, noRoom: { slotsNeeded: 1, slotsFree: 0 } })
    expect(result.noRoom).toEqual({ slotsNeeded: 1, slotsFree: 0 })
    expect(result.save).toBe(save)
  })
})

/** Everything a turn-in could pay or take, so a refusal can be checked field by field. */
function paidState(save: PlayerSave, questId: string) {
  return {
    cookingXp: getSkillProgress(save, COOKING).xp,
    gold: save.gold,
    inventory: save.inventory,
    unlockedLocationIds: save.unlockedLocationIds ?? [],
    unlockedBookIds: save.unlockedBookIds ?? [],
    dialogueFlags: save.dialogueFlags ?? [],
    completedDialogueIds: save.completedDialogueIds,
    quest: getQuestProgress(save, questId),
    courtyard: courtyardBotanyUnlocked(save),
  }
}

describe('no_room is all-or-nothing', () => {
  function rewardReady(free: number): PlayerSave {
    return fillBag(withStacks(started('QST-9108'), BAKED_POTATO, [[7, false]]), free)
  }

  it('pays no XP, gold, book, unlock or item and keeps the quest active on a legacy turn-in', () => {
    const save = rewardReady(0)
    const before = paidState(save, 'QST-9108')
    expect(before.unlockedLocationIds).not.toContain(APOTHECARY)

    const result = completeQuest(db, save, 'QST-9108')
    expect(result).toMatchObject({ ok: false, code: 'no_room' })
    expect(paidState(save, 'QST-9108')).toEqual(before)
    expect(before.quest.status).toBe('active')

    const paid = completeQuest(db, fillBag(save, 1), 'QST-9108')
    expect(paid.ok).toBe(true)
    if (!paid.ok) return
    const after = paidState(paid.save, 'QST-9108')
    expect(after.cookingXp).toBe(before.cookingXp + 5000)
    expect(after.unlockedLocationIds).toContain(APOTHECARY)
    expect(after.unlockedBookIds).toContain('BOOK-0001')
    expect(after.quest.status).toBe('completed')
  })

  it('writes nothing, flags included, when a dialogue complete_quest hits a full bag', () => {
    const save = rewardReady(0)
    const before = paidState(save, 'QST-9108')
    const result = chooseDialogue(db, save, 'DLG-9004', 'DNODE-9031', 'DCH-9108')
    expect(result).toMatchObject({ ok: false, code: 'no_room', itemDeltas: [], bookDeltas: [] })
    expect(result.noRoom).toEqual({ slotsNeeded: 1, slotsFree: 0 })
    expect(result.save).toBe(save)
    expect(paidState(result.save, 'QST-9108')).toEqual(before)

    const paid = chooseDialogue(db, fillBag(save, 1), 'DLG-9004', 'DNODE-9031', 'DCH-9108')
    expect(paid.ok).toBe(true)
    expect(paidState(paid.save, 'QST-9108')).toMatchObject({
      cookingXp: before.cookingXp + 5000,
      dialogueFlags: ['gift:QST-9108:done'],
      quest: { status: 'completed' },
    })
    expect(paid.save.unlockedLocationIds).toContain(APOTHECARY)
  })

  it('keeps The Grand Feast unpaid: no Cooking XP, no Courtyard plot, deliveries and quest state untouched', () => {
    let save: PlayerSave = { ...createNewSave(contentDb, START_MS), currentLocationId: 'LOC-0016' }
    const accepted = chooseDialogue(contentDb, save, 'DLG-0011', 'DNODE-0018', 'DCH-0023')
    if (!accepted.ok) throw new Error(accepted.reason)
    save = addItemToInventory(addItemToInventory(accepted.save, BAKED_POTATO, 11), COOKED_PERCH, 11)
    const handedIn = chooseDialogue(contentDb, save, 'DLG-0012', 'DNODE-0020', 'DCH-0026')
    if (!handedIn.ok) throw new Error(handedIn.reason)
    save = fillBag(handedIn.save, 0)
    const before = paidState(save, 'QST-0001')
    expect(before.courtyard).toBe(false)

    const result = chooseDialogue(contentDb, save, 'DLG-0012', 'DNODE-0022', 'DCH-0031')
    const kingLine = contentDb.DialogueChoices.find((row) => row['Choice ID'] === 'DCH-0031')?.['No Room Line']
    expect(kingLine).toMatch(/Clear some room/)
    expect(result).toMatchObject({
      ok: false,
      code: 'no_room',
      noRoom: { slotsNeeded: 1, slotsFree: 0, npcLine: kingLine },
    })
    expect(result.save).toBe(save)
    expect(paidState(save, 'QST-0001')).toEqual(before)

    const paid = chooseDialogue(contentDb, fillBag(save, 1), 'DLG-0012', 'DNODE-0022', 'DCH-0031')
    expect(paid.ok, paid.reason).toBe(true)
    expect(getSkillProgress(paid.save, COOKING).xp).toBe(before.cookingXp + 10000)
    expect(courtyardBotanyUnlocked(paid.save)).toBe(true)
    expect(bagCount(paid.save, BAKED_POTATO)).toBe(1)
    expect(bagCount(paid.save, GOLDEN_SPUD)).toBe(1)
  })
})

describe('legacy quest turn-ins share the hand-in item rules', () => {
  it('takes bag stacks only; the bank never counts', () => {
    const save = { ...started('QST-9101'), bank: [{ itemId: BAKED_POTATO, quantity: 50 }] }
    expect(completeQuest(db, save, 'QST-9101')).toEqual({ ok: false, reason: 'Need 5 Baked Potato.' })
  })

  it('asks before using favourited stacks, and takes unhearted ones first on a yes', () => {
    const save = withStacks(started('QST-9101'), BAKED_POTATO, [[3, true], [4, false]])
    const before = snapshot(save)
    expect(completeQuest(db, save, 'QST-9101')).toEqual({
      ok: false,
      reason: FAVOURITES_PROMPT,
      code: 'confirm_favourites',
      favourites: [{ itemId: BAKED_POTATO, qty: 1 }],
    })
    expect(snapshot(save)).toBe(before)

    const confirmed = completeQuest(db, save, 'QST-9101', { useFavourites: true })
    expect(confirmed.ok).toBe(true)
    if (!confirmed.ok) return
    expect(confirmed.save.inventory.filter((stack) => stack.itemId === BAKED_POTATO)).toEqual([
      { itemId: BAKED_POTATO, quantity: 2, favorite: true },
    ])
  })

  it('does not ask when unhearted stacks cover the delivery', () => {
    const save = withStacks(started('QST-9101'), BAKED_POTATO, [[3, true], [5, false]])
    const result = completeQuest(db, save, 'QST-9101')
    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(result.save.inventory.filter((stack) => stack.itemId === BAKED_POTATO)).toEqual([
      { itemId: BAKED_POTATO, quantity: 3, favorite: true },
    ])
  })

  it('reports a full bag before the favourites prompt, with or without useFavourites', () => {
    const save = fillBag(withStacks(started('QST-9101'), BAKED_POTATO, [[7, true]]), 0)
    const before = snapshot(save)
    const noRoom = { ok: false, reason: NO_ROOM, code: 'no_room', noRoom: { slotsNeeded: 1, slotsFree: 0 } }
    expect(completeQuest(db, save, 'QST-9101')).toEqual(noRoom)
    expect(completeQuest(db, save, 'QST-9101', { useFavourites: true })).toEqual(noRoom)
    expect(snapshot(save)).toBe(before)
  })
})

describe('dialogue hand-ins with a full bag (QA)', () => {
  const handInAndGift = (save: PlayerSave, useFavourites?: boolean) =>
    chooseDialogue(db, save, 'DLG-9003', 'DNODE-9021', 'DCH-9030', useFavourites === undefined ? {} : { useFavourites })

  function feastReady(): PlayerSave {
    const opened = chooseDialogue(db, freshSave(), 'DLG-9001', 'DNODE-9001', 'DCH-9001')
    if (!opened.ok) throw new Error(opened.reason)
    return withStacks(withStacks(opened.save, BAKED_POTATO, [[12, true]]), COOKED_PERCH, [[12, true]])
  }

  it('returns no_room, not confirm_favourites, for a favourited hand-in with a full bag', () => {
    const save = fillBag(feastReady(), 0)
    for (const useFavourites of [undefined, false, true]) {
      const result = handInAndGift(save, useFavourites)
      expect(result).toMatchObject({
        ok: false,
        code: 'no_room',
        reason: NO_ROOM,
        noRoom: { slotsNeeded: 1, slotsFree: 0 },
        favourites: [],
      })
      expect(result.save).toBe(save)
    }
  })

  it('asks about favourites once the bag has room', () => {
    const save = fillBag(feastReady(), 1)
    expect(handInAndGift(save)).toMatchObject({ ok: false, code: 'confirm_favourites' })
    expect(handInAndGift(save, true).ok).toBe(true)
  })
})

describe('bribe coin purse with a full bag', () => {
  function bribeReady(free: number): PlayerSave {
    const base = createNewSave(contentDb, START_MS)
    return fillBag(
      {
        ...base,
        gold: 300,
        currentLocationId: 'LOC-0017',
        quests: [...base.quests, { questId: 'QST-0003', status: 'active', progress: 0, counters: {} }],
      },
      free,
    )
  }

  it('refuses with no_room and takes no gold and sets no flag', () => {
    const save = bribeReady(0)
    const before = snapshot(save)
    const result = bribeQuestNpc(contentDb, save, 'QST-0003')
    expect(result).toEqual({ ok: false, reason: NO_ROOM, code: 'no_room', noRoom: { slotsNeeded: 1, slotsFree: 0 } })
    expect(snapshot(save)).toBe(before)
    expect(bribeForQuest(contentDb, save, 'QST-0003')).toEqual(result)
  })

  it('hands over the purse once there is room', () => {
    const result = bribeQuestNpc(contentDb, bribeReady(1), 'QST-0003')
    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(result.save.gold).toBe(100)
    expect(bagCount(result.save, 'ITEM-0299')).toBe(1)
  })
})

describe('server commands carry no_room and the favourites prompt', () => {
  it('quest_complete returns no_room with its counts', () => {
    const save = fillBag(withStacks(started('QST-9101'), BAKED_POTATO, [[7, true]]), 0)
    const noRoom = { ok: false, reason: NO_ROOM, code: 'no_room', noRoom: { slotsNeeded: 1, slotsFree: 0 } }
    expect(command(save, 'quest_complete', { questId: 'QST-9101' })).toEqual(noRoom)
    expect(command(save, 'quest_complete', { questId: 'QST-9101', useFavourites: true })).toEqual(noRoom)
  })

  it('quest_complete asks about favourites, validates useFavourites, and never stores it', () => {
    const save = withStacks(started('QST-9101'), BAKED_POTATO, [[6, true]])
    expect(command(save, 'quest_complete', { questId: 'QST-9101', useFavourites: 'yes' })).toEqual({
      ok: false,
      reason: 'useFavourites must be true or false.',
    })
    expect(command(save, 'quest_complete', { questId: 'QST-9101' })).toEqual({
      ok: false,
      reason: FAVOURITES_PROMPT,
      code: 'confirm_favourites',
      favourites: [{ itemId: BAKED_POTATO, qty: 5 }],
    })
    const confirmed = command(save, 'quest_complete', { questId: 'QST-9101', useFavourites: true })
    expect(confirmed.ok).toBe(true)
    if (!confirmed.ok) return
    expect(JSON.stringify(confirmed.save)).not.toContain('useFavourites')
    expect(getQuestProgress(confirmed.save, 'QST-9101').status).toBe('completed')
  })

  it('dialogue_choose forwards no_room ahead of the favourites prompt', () => {
    const opened = chooseDialogue(db, freshSave(), 'DLG-9001', 'DNODE-9001', 'DCH-9001')
    const save = fillBag(withStacks(withStacks(opened.save, BAKED_POTATO, [[12, true]]), COOKED_PERCH, [[12, true]]), 0)
    const args = { dialogueId: 'DLG-9003', nodeId: 'DNODE-9021', choiceId: 'DCH-9030' }
    const noRoom = { ok: false, reason: NO_ROOM, code: 'no_room', noRoom: { slotsNeeded: 1, slotsFree: 0 } }
    expect(command(save, 'dialogue_choose', args)).toEqual(noRoom)
    expect(command(save, 'dialogue_choose', { ...args, useFavourites: true })).toEqual(noRoom)
  })
})

describe('quest_bribe on the server', () => {
  it('returns no_room for a full bag', () => {
    const base = createNewSave(contentDb, START_MS)
    const save = fillBag(
      { ...base, gold: 300, quests: [...base.quests, { questId: 'QST-0003', status: 'active', progress: 0, counters: {} }] },
      0,
    )
    const result = applyGameCommand(
      JSON.parse(readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8')),
      { command: 'quest_bribe', args: { questId: 'QST-0003' }, save, nowMs: START_MS, random: () => 0 },
    )
    expect(result).toEqual({ ok: false, reason: NO_ROOM, code: 'no_room', noRoom: { slotsNeeded: 1, slotsFree: 0 } })
  })
})
