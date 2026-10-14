import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { addItemToInventory } from '../activity/rewards'
import { getSkillProgress } from '../activity/xp'
import { prepareDatabase } from '../data/loadDatabase'
import type { DialogueChoiceRow } from '../data/types'
import { INVENTORY_SLOT_LIMIT } from '../inventory/capacity'
import { talkWithQuestNpc } from '../npcs/conversation'
import { applyQuestActionProgress, applyQuestAutoStartOnSeed, applyQuestPlantProgress } from '../quests/progress'
import { cheatAbandonQuest, completeQuest, getQuest, getQuestProgress } from '../quests/quests'
import { getCurrentStepId } from '../quests/steps'
import { createNewSave, parseSave } from '../save/saveStore'
import { courtyardBotanyUnlocked } from '../timers/locationTimers'
import type { PlayerSave, QuestProgress } from '../save/types'
import { chooseDialogue, dialoguesForNpc, parseDialogueTokens, startDialogue, type DialogueResult } from './engine'
import { bagCount } from './stepProgress'
import { validateDialogueContent } from './validate'

// Fennel (NPC-0014) and the King (NPC-0001) on the launch content players load.

const rawDatabase = JSON.parse(readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'))
const { launch: db } = prepareDatabase(rawDatabase)
const NOW = Date.parse('2026-01-01T00:00:00.000Z')

const FARM = 'LOC-0001'
const THRONE_ROOM = 'LOC-0016'
const CITADEL_PLAZA = 'LOC-0028'
const POTATO_SEED = 'ITEM-0324'
const CARROT_SEED = 'ITEM-0339'
const COMPOST = 'ITEM-0377'
const BAKED_POTATO = 'ITEM-0058'
const COOKED_PERCH = 'ITEM-0059'
const GOLDEN_SPUD = 'ITEM-0026'
const COOKING = 'SKL-0007'

function fresh(locationId: string): PlayerSave {
  return { ...createNewSave(db, NOW), currentLocationId: locationId }
}

function withQuest(save: PlayerSave, questId: string, status: QuestProgress['status'], counters?: Record<string, number>): PlayerSave {
  const row: QuestProgress = { questId, status, progress: 0, ...(counters ? { counters } : {}) }
  return { ...save, quests: [...save.quests.filter((quest) => quest.questId !== questId), row] }
}

function setCount(save: PlayerSave, itemId: string, quantity: number): PlayerSave {
  const cleared = { ...save, inventory: save.inventory.filter((stack) => stack.itemId !== itemId) }
  return quantity > 0 ? addItemToInventory(cleared, itemId, quantity) : cleared
}

function fillBag(save: PlayerSave): PlayerSave {
  const inventory = [...save.inventory]
  for (let index = 0; inventory.length < INVENTORY_SLOT_LIMIT; index += 1) {
    inventory.push({ itemId: `ITEM-FILL-${index}`, quantity: 1 })
  }
  return { ...save, inventory }
}

function reload(save: PlayerSave): PlayerSave {
  return parseSave(JSON.parse(JSON.stringify(save)), NOW)
}

function pick(save: PlayerSave, dialogueId: string, nodeId: string, choiceId: string): DialogueResult {
  return chooseDialogue(db, save, dialogueId, nodeId, choiceId)
}

function picked(save: PlayerSave, dialogueId: string, nodeId: string, choiceId: string): DialogueResult {
  const result = pick(save, dialogueId, nodeId, choiceId)
  expect(result.ok, `${choiceId}: ${result.reason}`).toBe(true)
  return result
}

const seedGift = (save: PlayerSave) => pick(save, 'DLG-0007', 'DNODE-0011', 'DCH-0014')
const guidePotato = (save: PlayerSave) => pick(save, 'DLG-0001', 'DNODE-0001', 'DCH-0001')

function greenThumbActive(foundSeed = POTATO_SEED): PlayerSave {
  const save = setCount(withQuest(fresh(FARM), 'QST-0006', 'completed'), foundSeed, 1)
  const started = applyQuestAutoStartOnSeed(db, save)
  expect(getQuestProgress(started, 'QST-0011').status).toBe('active')
  return started
}

function stepOf(save: PlayerSave, questId: string): string | null {
  return getCurrentStepId(db, save, getQuest(db, questId)!)
}

describe('Fennel and King dialogue content', () => {
  it('validates on the launch view with no errors and ships every Fennel and King row', () => {
    expect(validateDialogueContent(db).filter((issue) => issue.severity === 'error')).toEqual([])
    const shipped = db.Dialogues.filter((row) => row['NPC ID'] === 'NPC-0014' || row['NPC ID'] === 'NPC-0001')
    expect(shipped.map((row) => row['Dialogue ID'])).toEqual([
      'DLG-0002',
      'DLG-0003',
      'DLG-0004',
      'DLG-0005',
      'DLG-0006',
      'DLG-0007',
      'DLG-0008',
      'DLG-0009',
      'DLG-0010',
      'DLG-0011',
      'DLG-0012',
    ])
    const ids = new Set(shipped.map((row) => row['Dialogue ID']))
    const nodes = rawDatabase.DialogueNodes.filter((row: { 'Dialogue ID': string }) => ids.has(row['Dialogue ID']))
    const nodeIds = new Set(nodes.map((row: { 'Node ID': string }) => row['Node ID']))
    const choices = rawDatabase.DialogueChoices.filter((row: { 'Node ID': string }) => nodeIds.has(row['Node ID']))
    expect(db.DialogueNodes.filter((row) => ids.has(row['Dialogue ID']))).toHaveLength(nodes.length)
    expect(db.DialogueChoices.filter((row) => nodeIds.has(row['Node ID']))).toHaveLength(choices.length)
  })

  it('guards every dialogue grant with a gift flag, and quest gifts with !quest_done', () => {
    const grants = db.DialogueChoices.filter((row: DialogueChoiceRow) =>
      parseDialogueTokens(row.Action).some((token) => token.name === 'grant_item'),
    )
    expect(grants.map((row) => row['Choice ID'])).toEqual(['DCH-0001', 'DCH-0014'])
    for (const row of grants) {
      const flag = parseDialogueTokens(row.Action).find((token) => token.name === 'set_flag')?.args[0] ?? ''
      expect(flag).toMatch(/^gift:(QST|DLG)-\d+:\w+$/)
      const conditions = parseDialogueTokens(row.Condition).map((token) => token.raw)
      expect(conditions).toContain(`!flag:${flag}`)
      const owner = flag.split(':')[1]!
      if (owner.startsWith('QST-')) expect(conditions).toContain(`!quest_done:${owner}`)
    }
  })

  it('never mentions the bank or says items must be in the bag', () => {
    const lines = db.DialogueNodes.map((row) => row.Line)
    expect(lines.filter((line) => /\bbank\b|\bbag\b|\bpack\b|inventory/i.test(line))).toEqual([])
  })

  it('keeps a Fennel planting reminder on QSTP-0034', () => {
    const dialogue = db.Dialogues.find((row) => row['Dialogue ID'] === 'DLG-0009')
    expect(dialogue?.Condition).toBe('quest_step:QST-0011:QSTP-0034')
    const node = db.DialogueNodes.find((row) => row['Node ID'] === 'DNODE-0015')
    expect(node?.Line).toMatch(/patch/i)
    expect(node?.Line).toMatch(/compost/i)
    expect(node?.Line).not.toMatch(/\bbank\b/i)
    expect(startDialogue(db, greenThumbActive(), 'DLG-0009').ok).toBe(false)
    const planted = withQuest(greenThumbActive(), 'QST-0011', 'active', { 'step:QSTP-0023': 1, 'step:QSTP-0024': 1 })
    expect(stepOf(planted, 'QST-0011')).toBe('QSTP-0034')
    expect(dialoguesForNpc(db, planted, 'NPC-0014')).toEqual(['DLG-0009'])
    const view = startDialogue(db, planted, 'DLG-0009').view
    expect(view?.line).toBe(node?.Line)
    expect(view?.choices.map((choice) => choice.choiceId)).toEqual(['DCH-0020'])
  })

  it('guides Visiting the Citadel on the Guide and Market Master without quest actions', () => {
    expect(db.Dialogues.filter((row) => row['Dialogue ID'] === 'DLG-0013' || row['Dialogue ID'] === 'DLG-0014')).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          'Dialogue ID': 'DLG-0013',
          'NPC ID': 'NPC-0013',
          Condition: 'quest_active:QST-0004',
          Priority: 10,
        }),
        expect.objectContaining({
          'Dialogue ID': 'DLG-0014',
          'NPC ID': 'NPC-0006',
          Condition: 'quest_active:QST-0004',
          Priority: 10,
        }),
      ]),
    )
    const guideLine = db.DialogueNodes.find((row) => row['Node ID'] === 'DNODE-0023')?.Line ?? ''
    const marketLine = db.DialogueNodes.find((row) => row['Node ID'] === 'DNODE-0024')?.Line ?? ''
    expect(guideLine).toMatch(/bazaar/i)
    expect(guideLine).toMatch(/training grounds/i)
    expect(marketLine).toMatch(/browse/i)
    expect([guideLine, marketLine].join(' ')).not.toMatch(/\bbank\b|\bgold\b|\bpoints?\b/i)

    const idle = fresh(CITADEL_PLAZA)
    expect(dialoguesForNpc(db, idle, 'NPC-0013')).toEqual(['DLG-0001'])
    expect(dialoguesForNpc(db, idle, 'NPC-0006')).toEqual([])

    const touring = withQuest(idle, 'QST-0004', 'active')
    expect(dialoguesForNpc(db, touring, 'NPC-0013')[0]).toBe('DLG-0013')
    expect(dialoguesForNpc(db, touring, 'NPC-0013')).toContain('DLG-0001')
    expect(dialoguesForNpc(db, touring, 'NPC-0006')).toEqual(['DLG-0014'])
    expect(startDialogue(db, touring, 'DLG-0013').view?.line).toBe(guideLine)
    expect(startDialogue(db, touring, 'DLG-0014').view?.line).toBe(marketLine)

    for (const [dialogueId, nodeId, choiceId] of [
      ['DLG-0013', 'DNODE-0023', 'DCH-0033'],
      ['DLG-0014', 'DNODE-0024', 'DCH-0034'],
    ] as const) {
      const choice = rawDatabase.DialogueChoices.find((row: { 'Choice ID': string }) => row['Choice ID'] === choiceId)
      expect(choice?.Action).toBeNull()
      const after = picked(touring, dialogueId, nodeId, choiceId)
      expect(getQuestProgress(after.save, 'QST-0004').status).toBe('active')
      expect(after.itemDeltas).toEqual([])
    }

    const done = withQuest(idle, 'QST-0004', 'completed')
    expect(dialoguesForNpc(db, done, 'NPC-0013')).toEqual(['DLG-0001'])
    expect(dialoguesForNpc(db, done, 'NPC-0006')).toEqual([])
  })

  it('stores a numberless make-room line on every SYS-01 hand-out choice', () => {
    const handOuts = rawDatabase.DialogueChoices.filter((row: DialogueChoiceRow) =>
      parseDialogueTokens(row.Action).some((token) => token.name === 'grant_item' || token.name === 'complete_quest'),
    )
    expect(handOuts.map((row: { 'Choice ID': string }) => row['Choice ID'])).toEqual([
      'DCH-0001',
      'DCH-0012',
      'DCH-0014',
      'DCH-0021',
      'DCH-0030',
      'DCH-0031',
    ])
    for (const row of handOuts) {
      const line = row['No Room Line'] ?? ''
      expect(line.length).toBeGreaterThan(10)
      expect(line).not.toMatch(/\d/)
      expect(line).not.toMatch(/\bbank\b/i)
    }
  })

  it('gives each gift once, even after closing mid-conversation and reloading', () => {
    let save = fresh(CITADEL_PLAZA)
    expect(startDialogue(db, save, 'DLG-0001').ok).toBe(true)
    save = picked(save, 'DLG-0001', 'DNODE-0001', 'DCH-0001').save
    expect(bagCount(save, BAKED_POTATO)).toBe(1)
    save = reload(save)
    expect(startDialogue(db, save, 'DLG-0001').ok).toBe(true)
    const again = guidePotato(save)
    expect(again.ok).toBe(false)
    expect(again.code).toBe('not_available')

    let farm = greenThumbActive()
    farm = (() => {
      const gift = seedGift(farm)
      expect(gift.ok, gift.reason).toBe(true)
      expect(gift.itemDeltas).toEqual([{ itemId: POTATO_SEED, qty: 1 }])
      return reload(gift.save)
    })()
    expect(farm.dialogueFlags).toContain('gift:QST-0011:seed')
    expect(dialoguesForNpc(db, farm, 'NPC-0014')).not.toContain('DLG-0007')
    expect(seedGift(farm).ok).toBe(false)
    expect(bagCount(farm, POTATO_SEED)).toBe(2)
  })

  it('gives players who already finished either quest nothing new', () => {
    let save = withQuest(withQuest(fresh(FARM), 'QST-0006', 'completed'), 'QST-0011', 'completed')
    save = applyQuestAutoStartOnSeed(db, setCount(save, POTATO_SEED, 3))
    expect(dialoguesForNpc(db, save, 'NPC-0014')).toEqual([])
    expect(seedGift(save).ok).toBe(false)
    expect(pick(save, 'DLG-0010', 'DNODE-0016', 'DCH-0021').ok).toBe(false)

    let king = withQuest(fresh(THRONE_ROOM), 'QST-0001', 'completed')
    king = setCount(setCount(king, BAKED_POTATO, 10), COOKED_PERCH, 10)
    expect(dialoguesForNpc(db, king, 'NPC-0001')).toEqual([])
    for (const choiceId of ['DCH-0026', 'DCH-0030']) {
      expect(pick(king, 'DLG-0012', 'DNODE-0020', choiceId).ok).toBe(false)
    }
    expect(pick(king, 'DLG-0012', 'DNODE-0022', 'DCH-0031').ok).toBe(false)
    expect(bagCount(king, GOLDEN_SPUD)).toBe(0)
  })

  it('finishing Green Thumb gives exactly 4 Potato Seed, 3 Carrot Seed and the Guide, once', () => {
    let save = greenThumbActive()
    const before = { potato: bagCount(save, POTATO_SEED), carrot: bagCount(save, CARROT_SEED) }
    const results: DialogueResult[] = []
    const take = (dialogueId: string, nodeId: string, choiceId: string) => {
      const result = picked(save, dialogueId, nodeId, choiceId)
      results.push(result)
      save = result.save
    }
    take('DLG-0007', 'DNODE-0011', 'DCH-0014')
    expect(stepOf(save, 'QST-0011')).toBe('QSTP-0024')
    expect(pick(save, 'DLG-0008', 'DNODE-0013', 'DCH-0017').reason).toBe('Needs Compost')
    save = applyQuestActionProgress(db, setCount(save, COMPOST, 1), 'ACN-0199', 1)
    take('DLG-0008', 'DNODE-0013', 'DCH-0017')
    save = applyQuestPlantProgress(db, save, [POTATO_SEED], true)
    expect(stepOf(save, 'QST-0011')).toBe('QSTP-0035')
    take('DLG-0010', 'DNODE-0016', 'DCH-0021')
    expect(getQuestProgress(save, 'QST-0011').status).toBe('completed')

    expect(seedGift(save).ok).toBe(false)
    expect(pick(save, 'DLG-0010', 'DNODE-0016', 'DCH-0021').ok).toBe(false)
    expect(dialoguesForNpc(db, save, 'NPC-0014')).toEqual([])

    const granted = (itemId: string) =>
      results.flatMap((result) => result.itemDeltas).filter((delta) => delta.itemId === itemId).reduce((sum, delta) => sum + delta.qty, 0)
    expect(granted(POTATO_SEED)).toBe(4)
    expect(granted(CARROT_SEED)).toBe(3)
    expect(results.flatMap((result) => result.bookDeltas)).toEqual(['BOOK-0002'])
    expect(bagCount(save, POTATO_SEED) - before.potato).toBe(4)
    expect(bagCount(save, CARROT_SEED) - before.carrot).toBe(3)
    expect(save.unlockedBookIds).toContain('BOOK-0002')
  })

  it('hands in the feast over several visits and pays the quest once', () => {
    let save = fresh(THRONE_ROOM)
    expect(dialoguesForNpc(db, save, 'NPC-0001')[0]).toBe('DLG-0011')
    save = picked(save, 'DLG-0011', 'DNODE-0018', 'DCH-0023').save
    expect(stepOf(save, 'QST-0001')).toBe('QSTP-0002')
    expect(dialoguesForNpc(db, save, 'NPC-0001')[0]).toBe('DLG-0012')
    expect(pick(save, 'DLG-0012', 'DNODE-0020', 'DCH-0026').code).toBe('nothing_to_hand_in')

    expect(courtyardBotanyUnlocked(save)).toBe(false)
    const first = picked(setCount(save, BAKED_POTATO, 6), 'DLG-0012', 'DNODE-0020', 'DCH-0026')
    expect(first.itemDeltas).toEqual([{ itemId: BAKED_POTATO, qty: -6 }])
    expect(first.view?.choices.map((choice) => choice.choiceId)).toEqual(['DCH-0032'])
    save = reload(picked(first.save, 'DLG-0012', 'DNODE-0022', 'DCH-0032').save)
    expect(stepOf(save, 'QST-0001')).toBe('QSTP-0002')

    save = setCount(setCount(save, BAKED_POTATO, 9), COOKED_PERCH, 12)
    const second = picked(save, 'DLG-0012', 'DNODE-0020', 'DCH-0026')
    expect(second.itemDeltas).toEqual([
      { itemId: BAKED_POTATO, qty: -4 },
      { itemId: COOKED_PERCH, qty: -10 },
    ])
    expect(bagCount(second.save, BAKED_POTATO)).toBe(5)
    expect(bagCount(second.save, COOKED_PERCH)).toBe(2)
    expect(second.view?.choices.map((choice) => choice.choiceId)).toEqual(['DCH-0031'])
    expect(getSkillProgress(second.save, COOKING).xp).toBe(0)

    // Closing before "The feast is ready" leaves the reward on the opening node.
    save = reload(second.save)
    expect(startDialogue(db, save, 'DLG-0012').view?.choices.map((choice) => choice.choiceId)).toEqual([
      'DCH-0030',
      'DCH-0027',
    ])
    const paid = picked(save, 'DLG-0012', 'DNODE-0020', 'DCH-0030')
    expect(paid.itemDeltas).toEqual([{ itemId: GOLDEN_SPUD, qty: 1 }])
    save = paid.save
    expect(getQuestProgress(save, 'QST-0001').status).toBe('completed')
    expect(getSkillProgress(save, COOKING).xp).toBe(10_000)
    expect(bagCount(save, GOLDEN_SPUD)).toBe(1)
    expect(db.Items.find((row) => row['Item ID'] === GOLDEN_SPUD)?.Tradeable).toBe(true)
    expect(courtyardBotanyUnlocked(save)).toBe(true)

    for (const [nodeId, choiceId] of [
      ['DNODE-0020', 'DCH-0030'],
      ['DNODE-0022', 'DCH-0031'],
      ['DNODE-0020', 'DCH-0026'],
    ] as const) {
      expect(pick(save, 'DLG-0012', nodeId, choiceId).ok).toBe(false)
    }
    expect(getSkillProgress(save, COOKING).xp).toBe(10_000)
    expect(bagCount(save, GOLDEN_SPUD)).toBe(1)
  })

  it('reports the quest a dialogue choice completed for the reward popup', () => {
    let save = picked(fresh(THRONE_ROOM), 'DLG-0011', 'DNODE-0018', 'DCH-0023').save
    save = setCount(setCount(save, BAKED_POTATO, 10), COOKED_PERCH, 10)
    const handedIn = picked(save, 'DLG-0012', 'DNODE-0020', 'DCH-0026')
    expect(handedIn.questCompletions).toEqual([])

    const paid = picked(handedIn.save, 'DLG-0012', 'DNODE-0022', 'DCH-0031')
    expect(paid.questCompletions).toHaveLength(1)
    const completion = paid.questCompletions[0]!
    const direct = completeQuest(db, handedIn.save, 'QST-0001')
    expect(direct.ok).toBe(true)
    if (!direct.ok) return
    expect(completion.questId).toBe('QST-0001')
    expect(completion.questName).toBe(direct.questName)
    expect(completion.rewards).toEqual(direct.rewards.map((reward) => reward.label))
    expect(completion.rewards.length).toBeGreaterThan(0)
    expect(completion.pendingSkillXp).toBe(direct.pendingSkillXp)
    expect(completion.pendingSkillXp).toBe(0)
    expect(JSON.parse(JSON.stringify(paid)).questCompletions).toEqual([
      {
        questId: completion.questId,
        questName: completion.questName,
        rewards: completion.rewards,
        pendingSkillXp: completion.pendingSkillXp,
        rewardBundle: completion.rewardBundle,
        message: completion.message,
        booksGranted: completion.booksGranted,
      },
    ])

    expect(pick(paid.save, 'DLG-0012', 'DNODE-0022', 'DCH-0031').questCompletions).toEqual([])
  })

  it('keeps gifts claimable while the bag is full', () => {
    const full = fillBag(fresh(CITADEL_PLAZA))
    const refused = guidePotato(full)
    expect(refused.code).toBe('no_room')
    expect(refused.save).toBe(full)
    expect(guidePotato({ ...full, inventory: full.inventory.slice(1) }).ok).toBe(true)

    const farm = fillBag(greenThumbActive(CARROT_SEED))
    const noRoom = seedGift(farm)
    expect(noRoom.code).toBe('no_room')
    expect(noRoom.save.dialogueFlags).not.toContain('gift:QST-0011:seed')
    expect(stepOf(noRoom.save, 'QST-0011')).toBe('QSTP-0023')
    const freed = { ...farm, inventory: farm.inventory.filter((stack) => !stack.itemId.startsWith('ITEM-FILL-')) }
    expect(seedGift(freed).ok).toBe(true)
  })

  it('puts the choice No Room Line on a grant_item no_room and grants nothing', () => {
    const full = fillBag(fresh(CITADEL_PLAZA))
    const line = db.DialogueChoices.find((row) => row['Choice ID'] === 'DCH-0001')?.['No Room Line']
    expect(line).toMatch(/Clear some space/)
    const refused = guidePotato(full)
    expect(refused).toMatchObject({
      ok: false,
      code: 'no_room',
      itemDeltas: [],
      noRoom: { slotsNeeded: 1, slotsFree: 0, npcLine: line },
    })
    expect(bagCount(refused.save, BAKED_POTATO)).toBe(0)
    expect(refused.save.dialogueFlags ?? []).not.toContain('gift:DLG-0001:potato')
  })

  it('leaves npcLine unset when a full-bag choice grants nothing', () => {
    const full = fillBag(fresh(CITADEL_PLAZA))
    const declined = pick(full, 'DLG-0001', 'DNODE-0001', 'DCH-0002')
    expect(declined.ok).toBe(true)
    expect(declined.code).toBeNull()
    expect(declined.noRoom).toBeNull()
    expect(declined.itemDeltas).toEqual([])
    expect(bagCount(declined.save, BAKED_POTATO)).toBe(0)
  })

  it('leaves npcLine unset on a refusal other than no_room', () => {
    const save = picked(fresh(CITADEL_PLAZA), 'DLG-0001', 'DNODE-0001', 'DCH-0001').save
    const again = guidePotato(save)
    expect(again.ok).toBe(false)
    expect(again.code).toBe('not_available')
    expect(again.noRoom).toBeNull()
  })

  it('omits a whitespace-only No Room Line from no_room.npcLine', () => {
    const patchedRaw = JSON.parse(JSON.stringify(rawDatabase)) as typeof rawDatabase
    const choice = patchedRaw.DialogueChoices.find((row: { 'Choice ID': string }) => row['Choice ID'] === 'DCH-0001')
    expect(choice).toBeDefined()
    choice!['No Room Line'] = ' \t\n '
    const patched = prepareDatabase(patchedRaw).launch
    const full = fillBag({ ...createNewSave(patched, NOW), currentLocationId: CITADEL_PLAZA })
    const refused = chooseDialogue(patched, full, 'DLG-0001', 'DNODE-0001', 'DCH-0001')
    expect(refused.ok).toBe(false)
    expect(refused.code).toBe('no_room')
    expect(refused.noRoom).toEqual({ slotsNeeded: 1, slotsFree: 0 })
    expect(refused.noRoom).not.toHaveProperty('npcLine')
    expect(bagCount(refused.save, BAKED_POTATO)).toBe(0)
  })

  it('/abandonquest clears Green Thumb gift flags so the seed can be claimed again', () => {
    let save = greenThumbActive()
    const gift = seedGift(save)
    expect(gift.ok).toBe(true)
    save = { ...gift.save, dialogueFlags: [...(gift.save.dialogueFlags ?? []), 'gift:DLG-0001:potato'] }
    const abandoned = cheatAbandonQuest(save, 'QST-0011')
    expect(abandoned.ok).toBe(true)
    if (!abandoned.ok) return
    expect(abandoned.save.dialogueFlags).toEqual(['gift:DLG-0001:potato'])
    save = applyQuestAutoStartOnSeed(db, abandoned.save)
    const again = seedGift(save)
    expect(again.ok, again.reason).toBe(true)
    expect(seedGift(again.save).ok).toBe(false)
  })

  it('keeps a Fennel step finished under the old flow done', () => {
    const latched = withQuest(fresh(FARM), 'QST-0006', 'active', {
      'talk:NPC-0014': 1,
      'talk:NPC-0014:QSTP-0014': 1,
      'step:QSTP-0013': 1,
      'step:QSTP-0014': 1,
    })
    expect(bagCount(latched, 'ITEM-0025')).toBe(0)
    expect(stepOf(reload(latched), 'QST-0006')).toBe('QSTP-0015')
    expect(dialoguesForNpc(db, latched, 'NPC-0014')).toEqual(['DLG-0004'])

    const shown = withQuest(fresh(FARM), 'QST-0006', 'active', {
      'step:QSTP-0013': 1,
      'step:QSTP-0014': 1,
      'step:QSTP-0015': 1,
      'step:QSTP-0016': 1,
    })
    expect(stepOf(reload(shown), 'QST-0006')).toBe('QSTP-0022')
    const done = picked(shown, 'DLG-0006', 'DNODE-0009', 'DCH-0012')
    expect(done.bookDeltas).toEqual(['BOOK-0001'])
    expect(getQuestProgress(done.save, 'QST-0006').status).toBe('completed')

    const oldSeed = withQuest(withQuest(fresh(FARM), 'QST-0006', 'completed'), 'QST-0011', 'active', {
      'give:ITEM-0324': 1,
      'talk:NPC-0014': 1,
      'talk:NPC-0014:QSTP-0023': 1,
      'step:QSTP-0023': 1,
    })
    expect(stepOf(oldSeed, 'QST-0011')).toBe('QSTP-0024')
    expect(dialoguesForNpc(db, oldSeed, 'NPC-0014')).toEqual(['DLG-0008'])
    expect(seedGift(setCount(oldSeed, POTATO_SEED, 2)).ok).toBe(false)
  })

  it('lets a player midway through the old feast finish with the new hand-in', () => {
    let save = withQuest(fresh(THRONE_ROOM), 'QST-0001', 'active', {
      'talk:NPC-0001': 1,
      'talk:NPC-0001:QSTP-0001': 1,
      'step:QSTP-0001': 1,
    })
    save = setCount(setCount(reload(save), BAKED_POTATO, 10), COOKED_PERCH, 10)
    expect(dialoguesForNpc(db, save, 'NPC-0001')[0]).toBe('DLG-0012')
    save = picked(save, 'DLG-0012', 'DNODE-0020', 'DCH-0026').save
    save = picked(save, 'DLG-0012', 'DNODE-0022', 'DCH-0031').save
    expect(getQuestProgress(save, 'QST-0001').status).toBe('completed')
    expect(bagCount(save, GOLDEN_SPUD)).toBe(1)
    expect(getSkillProgress(save, COOKING).xp).toBe(10_000)

    // Accepted on the old panel but never talked: the King still briefs them.
    const accepted = withQuest(fresh(THRONE_ROOM), 'QST-0001', 'active', {})
    const view = startDialogue(db, accepted, 'DLG-0011').view
    expect(view?.choices.map((choice) => choice.choiceId)).toEqual(['DCH-0029', 'DCH-0024'])
    const briefed = picked(accepted, 'DLG-0011', 'DNODE-0018', 'DCH-0029')
    expect(stepOf(briefed.save, 'QST-0001')).toBe('QSTP-0002')
  })

  it('the old panel Continue cannot finish a Talk step that a dialogue talk_flag owns', () => {
    // Green Thumb G1: the seed gift is the only way through QSTP-0023.
    const seeded = greenThumbActive()
    const talked = talkWithQuestNpc(db, seeded, 'NPC-0014')
    expect(talked.ok).toBe(true)
    if (!talked.ok) return
    expect(stepOf(talked.save, 'QST-0011')).toBe('QSTP-0023')
    expect(dialoguesForNpc(db, talked.save, 'NPC-0014')).toEqual(['DLG-0007'])
    expect(getQuestProgress(talked.save, 'QST-0011').status).toBe('active')
    const gift = seedGift(talked.save)
    expect(gift.ok, gift.reason).toBe(true)
    expect(gift.itemDeltas).toEqual([{ itemId: POTATO_SEED, qty: 1 }])
    expect(stepOf(gift.save, 'QST-0011')).toBe('QSTP-0024')

    // The same for the King's brief (QSTP-0001) and Fennel's farewell (QSTP-0022).
    const accepted = withQuest(fresh(THRONE_ROOM), 'QST-0001', 'active', {})
    const kingTalked = talkWithQuestNpc(db, accepted, 'NPC-0001')
    expect(kingTalked.ok).toBe(true)
    if (!kingTalked.ok) return
    expect(stepOf(kingTalked.save, 'QST-0001')).toBe('QSTP-0001')
    expect(dialoguesForNpc(db, kingTalked.save, 'NPC-0001')).toEqual(['DLG-0011'])

    const farewell = withQuest(fresh(FARM), 'QST-0006', 'active', {
      'step:QSTP-0013': 1,
      'step:QSTP-0014': 1,
      'step:QSTP-0015': 1,
      'step:QSTP-0016': 1,
    })
    const fennelTalked = talkWithQuestNpc(db, farewell, 'NPC-0014')
    expect(fennelTalked.ok).toBe(true)
    if (!fennelTalked.ok) return
    expect(stepOf(fennelTalked.save, 'QST-0006')).toBe('QSTP-0022')
    expect(getQuestProgress(fennelTalked.save, 'QST-0006').status).toBe('active')
    expect(dialoguesForNpc(db, fennelTalked.save, 'NPC-0014')).toEqual(['DLG-0006'])
    expect(picked(fennelTalked.save, 'DLG-0006', 'DNODE-0009', 'DCH-0012').bookDeltas).toEqual(['BOOK-0001'])
  })
})
