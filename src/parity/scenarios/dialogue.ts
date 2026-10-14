/**
 * SYS-01 dialogue engine parity.
 *
 * Each fixture is the real content database plus a small synthetic patch (test
 * quests, steps, NPCs and dialogues appended, so no live quest changes) and a
 * script of operations. `runDialogueScript` is mirrored op for op by
 * `packages/ik_rules/test/dialogue_parity_test.dart`.
 */

import type { GameDatabase } from '../../game/data/types'
import {
  checkDialogueCondition,
  chooseDialogue,
  dialoguesForNpc,
  parseDialogueTokens,
  startDialogue,
  viewDialogueNode,
  type DialogueResult,
} from '../../game/dialogue/engine'
import { stepProgressView } from '../../game/dialogue/stepProgress'
import { validateDialogueContent } from '../../game/dialogue/validate'
import { addItemToInventory } from '../../game/activity/rewards'
import { INVENTORY_SLOT_LIMIT } from '../../game/inventory/capacity'
import { getSkillProgress } from '../../game/activity/xp'
import { filterLaunchContent } from '../../game/data/validate'
import { talkWithQuestNpc } from '../../game/npcs/conversation'
import {
  applyQuestActionProgress,
  applyQuestAutoStartOnSeed,
  applyQuestPlantProgress,
  applyQuestTalkProgress,
} from '../../game/quests/progress'
import { cheatAbandonQuest, completeQuest } from '../../game/quests/quests'
import { migrateSave } from '../../game/save/migrations'
import { parseSave } from '../../game/save/saveStore'
import type { PlayerSave, QuestProgress } from '../../game/save/types'
import { canonicalJson } from '../canonicalJson'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import { contentDatabase } from './contentDatabase'
import { asJson, baseSave, FIXED_TIMESTAMP_MS } from './saveFixtures'

/** Plain JSON copy (undefined fields dropped), which is what the Dart side compares. */
function json(value: unknown): JsonValue {
  return value === undefined ? null : (JSON.parse(JSON.stringify(value)) as JsonValue)
}

type Row = Record<string, JsonValue>
type Patch = Record<string, Row[]>
type Op = Record<string, JsonValue>

const LOCATION = 'LOC-0002'
const POTATO = 'ITEM-0025'
const GOLDEN_SPUD = 'ITEM-0026'
const BAKED_POTATO = 'ITEM-0058'
const COOKED_PERCH = 'ITEM-0059'

function quest(id: string, name: string, npcId: string, extra: Row = {}): Row {
  return {
    'Quest ID': id,
    'Internal Key': id.toLowerCase(),
    'Display Name': name,
    'NPC ID': npcId,
    Summary: null,
    Pitch: null,
    Status: 'Confirmed',
    'Release Phase': 'Launch',
    Notes: null,
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

function step(id: string, questId: string, order: number, type: string | null, items: string | null, npcId: string): Row {
  return {
    'Step ID': id,
    'Quest ID': questId,
    'Step Order': order,
    'Journal Label': id,
    Notes: null,
    'Step Type': type,
    'Step Items': items,
    'Step NPC': npcId,
    Status: 'Confirmed',
    'Release Phase': 'Launch',
  }
}

function npc(id: string, name: string): Row {
  return {
    'NPC ID': id,
    'Internal Key': id.toLowerCase(),
    'Display Name': name,
    'Location ID': LOCATION,
    Role: null,
    Status: 'Confirmed',
    'Release Phase': 'Launch',
    Description: null,
    Notes: null,
  }
}

function dialogue(id: string, npcId: string, startNodeId: string, extra: Row = {}): Row {
  return {
    'Dialogue ID': id,
    'Internal Key': id.toLowerCase(),
    'Display Name': id,
    'NPC ID': npcId,
    'Start Node ID': startNodeId,
    Repeatable: true,
    Status: 'Confirmed',
    'Release Phase': 'Launch',
    Notes: null,
    ...extra,
  }
}

function node(id: string, dialogueId: string): Row {
  return {
    'Node ID': id,
    'Dialogue ID': dialogueId,
    Line: `${id} line`,
    Status: 'Confirmed',
    'Release Phase': 'Launch',
    Notes: null,
  }
}

function choice(
  id: string,
  nodeId: string,
  order: number,
  condition: string | null,
  action: string | null,
  extra: Row = {},
): Row {
  return {
    'Choice ID': id,
    'Node ID': nodeId,
    Label: `${id} label`,
    'Next Node ID': null,
    Condition: condition,
    Action: action,
    'Sort Order': order,
    Status: 'Confirmed',
    'Release Phase': 'Launch',
    Notes: null,
    ...extra,
  }
}

/**
 * Test-only content. QST-9001 mirrors the Grand Feast plan (King starts it,
 * hand in 10 Baked Potato + 10 Cooked Perch, complete), QST-9002 the Getting
 * Started ending (show 5 Baked Potato), QST-9003/9004 a legacy and a dialogue
 * quest with the same leftover reward cells.
 */
export const DIALOGUE_PATCH: Patch = {
  NPCs: [npc('NPC-9001', 'Test King'), npc('NPC-9002', 'Test Fennel')],
  Quests: [
    quest('QST-9001', 'Test Feast', 'NPC-9001', { 'Reward Mode': 'dialogue' }),
    quest('QST-9002', 'Test Showing', 'NPC-9002', { 'Reward Mode': 'dialogue' }),
    quest('QST-9003', 'Test Legacy Pay', 'NPC-9001', {
      Notes: 'RewardGold: 500',
      'Reward Item ID': GOLDEN_SPUD,
      'Reward Item Quantity': 1,
    }),
    quest('QST-9004', 'Test Dialogue Pay', 'NPC-9001', {
      'Reward Mode': 'dialogue',
      Notes: 'RewardGold: 500',
      'Reward Item ID': GOLDEN_SPUD,
      'Reward Item Quantity': 1,
    }),
  ],
  QuestSteps: [
    step('QSTP-9001', 'QST-9001', 1, 'Talk', null, 'NPC-9001'),
    step('QSTP-9002', 'QST-9001', 2, 'HandIn', `${BAKED_POTATO}:10;${COOKED_PERCH}:10`, 'NPC-9001'),
    step('QSTP-9011', 'QST-9002', 1, 'Show', `${BAKED_POTATO}:5`, 'NPC-9002'),
    step('QSTP-9021', 'QST-9003', 1, 'Talk', null, 'NPC-9001'),
    step('QSTP-9031', 'QST-9004', 1, 'Talk', null, 'NPC-9001'),
  ],
  Dialogues: [
    dialogue('DLG-9001', 'NPC-9001', 'DNODE-9001', { Priority: 5 }),
    dialogue('DLG-9002', 'NPC-9002', 'DNODE-9011'),
    dialogue('DLG-9003', 'NPC-9002', 'DNODE-9021'),
    dialogue('DLG-9004', 'NPC-9001', 'DNODE-9031'),
    dialogue('DLG-9005', 'NPC-9001', 'DNODE-9041', { Priority: 9, Condition: 'flag:never-set' }),
  ],
  DialogueNodes: [
    node('DNODE-9001', 'DLG-9001'),
    node('DNODE-9011', 'DLG-9002'),
    node('DNODE-9021', 'DLG-9003'),
    node('DNODE-9031', 'DLG-9004'),
    node('DNODE-9041', 'DLG-9005'),
  ],
  DialogueChoices: [
    choice(
      'DCH-9001',
      'DNODE-9001',
      1,
      '!quest_active:QST-9001;!quest_done:QST-9001',
      'start_quest:QST-9001;talk_flag:QST-9001:QSTP-9001',
    ),
    choice('DCH-9002', 'DNODE-9001', 2, 'step_ready:QST-9001:QSTP-9002', 'hand_in:QST-9001:QSTP-9002'),
    choice(
      'DCH-9003',
      'DNODE-9001',
      3,
      'quest_active:QST-9001',
      `complete_quest:QST-9001;grant_item:${GOLDEN_SPUD}:1;set_flag:gift:QST-9001:feast`,
    ),
    choice('DCH-9004', 'DNODE-9001', 4, 'flag:secret', null, { Hidden: true }),
    choice('DCH-9005', 'DNODE-9001', 5, 'flag:secret', null, { QuestMarker: true }),
    choice('DCH-9006', 'DNODE-9001', 6, 'quest_active:QST-9001', 'hand_in:QST-9001:QSTP-9002'),
    choice('DCH-9011', 'DNODE-9011', 1, '!quest_active:QST-9002;!quest_done:QST-9002', 'start_quest:QST-9002'),
    choice('DCH-9012', 'DNODE-9011', 2, 'quest_step:QST-9002:QSTP-9011', 'show_items:QST-9002:QSTP-9011'),
    choice('DCH-9013', 'DNODE-9011', 3, 'quest_active:QST-9002', 'complete_quest:QST-9002'),
    choice(
      'DCH-9021',
      'DNODE-9021',
      1,
      'quest_active:QST-9002;!flag:gift:QST-9002:spud',
      `grant_item:${GOLDEN_SPUD}:1;set_flag:gift:QST-9002:spud`,
    ),
    choice(
      'DCH-9022',
      'DNODE-9021',
      2,
      '!flag:gift:QST-9001:seed',
      `grant_item:${POTATO}:3;set_flag:gift:QST-9001:seed`,
    ),
    choice('DCH-9023', 'DNODE-9021', 3, null, 'grant_book:BOOK-0001', { Repeatable: true }),
    choice('DCH-9024', 'DNODE-9021', 4, null, 'set_flag:met-fennel'),
    choice(
      'DCH-9025',
      'DNODE-9021',
      5,
      null,
      `grant_item:${GOLDEN_SPUD}:1;grant_item:${POTATO}:2;grant_item:${BAKED_POTATO}:3`,
      { Repeatable: true },
    ),
    choice(
      'DCH-9026',
      'DNODE-9021',
      6,
      null,
      `set_flag:rollback;grant_book:BOOK-0002;grant_item:${POTATO}:1;take_item:${COOKED_PERCH}:99`,
      { Repeatable: true },
    ),
    choice('DCH-9027', 'DNODE-9021', 7, null, 'mystery_action:QST-9001'),
    choice(
      'DCH-9028',
      'DNODE-9021',
      8,
      'quest_active:QST-9001',
      `hand_in:QST-9001:QSTP-9002;grant_item:${GOLDEN_SPUD}:1`,
      { Repeatable: true },
    ),
    choice('DCH-9029', 'DNODE-9021', 9, null, `take_item:${COOKED_PERCH}:3`),
    choice(
      'DCH-9030',
      'DNODE-9021',
      10,
      'quest_active:QST-9001;!flag:gift:QST-9001:thanks',
      `hand_in:QST-9001:QSTP-9002;grant_item:${GOLDEN_SPUD}:1;set_flag:gift:QST-9001:thanks`,
    ),
    choice(
      'DCH-9031',
      'DNODE-9031',
      1,
      '!quest_active:QST-9003;!quest_done:QST-9003',
      'start_quest:QST-9003;talk_flag:QST-9003:QSTP-9021;complete_quest:QST-9003',
    ),
    choice(
      'DCH-9032',
      'DNODE-9031',
      2,
      '!quest_active:QST-9004;!quest_done:QST-9004',
      'start_quest:QST-9004;talk_flag:QST-9004:QSTP-9031;complete_quest:QST-9004',
    ),
    choice('DCH-9041', 'DNODE-9041', 1, null, null),
  ],
}

/** Content plus [patch] rows appended to their tables. */
export function patchedDatabase(patch: Patch): GameDatabase {
  const base = contentDatabase() as unknown as Record<string, JsonValue[]>
  const db: Record<string, JsonValue[]> = { ...base }
  for (const [table, rows] of Object.entries(patch)) {
    db[table] = [...(base[table] ?? []), ...rows]
  }
  return db as unknown as GameDatabase
}

/** Replaces every stack of an item with one stack of `quantity` (0 clears it). */
function setItemCount(save: PlayerSave, itemId: string, quantity: number): PlayerSave {
  const cleared = { ...save, inventory: save.inventory.filter((stack) => stack.itemId !== itemId) }
  return quantity > 0 ? addItemToInventory(cleared, itemId, quantity) : cleared
}

/** Pads the bag with single filler stacks until exactly [free] slots remain. */
function fillBag(save: PlayerSave, free: number): PlayerSave {
  const inventory = [...save.inventory]
  for (let index = 0; inventory.length < INVENTORY_SLOT_LIMIT - free; index += 1) {
    inventory.push({ itemId: `ITEM-FILL-${index}`, quantity: 1 })
  }
  return { ...save, inventory }
}

function startingSave(): PlayerSave {
  return { ...baseSave(contentDatabase()), currentLocationId: LOCATION }
}

/** What players load: rows without Release Phase Launch dropped. */
function launchDatabase(): GameDatabase {
  return filterLaunchContent(contentDatabase())
}

function launchStartingSave(): PlayerSave {
  return baseSave(launchDatabase())
}

function digest(save: PlayerSave): JsonValue {
  return {
    gold: save.gold,
    inventory: json(save.inventory),
    bank: json(save.bank ?? []),
    quests: json([...save.quests].sort((a, b) => (a.questId < b.questId ? -1 : a.questId > b.questId ? 1 : 0))),
    dialogueFlags: save.dialogueFlags,
    unlockedBookIds: save.unlockedBookIds ?? [],
    completedDialogueIds: save.completedDialogueIds,
  }
}

function resultSummary(before: PlayerSave, result: DialogueResult): JsonValue {
  return {
    ok: result.ok,
    code: result.code,
    reason: result.reason,
    message: result.message,
    completed: result.completed,
    view: json(result.view),
    itemDeltas: json(result.itemDeltas),
    bookDeltas: result.bookDeltas,
    stepProgress: json(result.stepProgress),
    noRoom: json(result.noRoom),
    missing: json(result.missing),
    favourites: json(result.favourites),
    questCompletions: json(result.questCompletions),
    unchanged: canonicalJson(asJson(before)) === canonicalJson(asJson(result.save)),
  }
}

function str(op: Op, key: string): string {
  return String(op[key])
}

/** Runs [ops] from [save]; each step records its output and the save digest after it. */
export function runDialogueScript(db: GameDatabase, initial: PlayerSave, ops: Op[]): JsonValue {
  let save = initial
  const steps: JsonValue[] = []
  for (const op of ops) {
    let out: JsonValue = null
    switch (op.op) {
      case 'npc':
        out = dialoguesForNpc(db, save, str(op, 'npcId'))
        break
      case 'start':
        out = resultSummary(save, startDialogue(db, save, str(op, 'dialogueId')))
        break
      case 'view':
        out = json(viewDialogueNode(db, save, str(op, 'dialogueId'), str(op, 'nodeId')))
        break
      case 'choose': {
        const result = chooseDialogue(db, save, str(op, 'dialogueId'), str(op, 'nodeId'), str(op, 'choiceId'), {
          useFavourites: op.useFavourites === true,
        })
        out = resultSummary(save, result)
        if (result.ok) save = result.save
        break
      }
      case 'setItem':
        save = setItemCount(save, str(op, 'itemId'), Number(op.quantity))
        break
      case 'setBank': {
        const itemId = str(op, 'itemId')
        const quantity = Number(op.quantity)
        const bank = (save.bank ?? []).filter((stack) => stack.itemId !== itemId)
        save = { ...save, bank: quantity > 0 ? [...bank, { itemId, quantity }] : bank }
        break
      }
      case 'setStacks': {
        const itemId = str(op, 'itemId')
        const stacks = (op.stacks as Array<{ quantity: number; favorite: boolean }>).map((stack) =>
          stack.favorite ? { itemId, quantity: stack.quantity, favorite: true } : { itemId, quantity: stack.quantity },
        )
        save = { ...save, inventory: [...save.inventory.filter((stack) => stack.itemId !== itemId), ...stacks] }
        break
      }
      case 'fillBag':
        save = fillBag(save, Number(op.free))
        break
      case 'clearFillers':
        save = { ...save, inventory: save.inventory.filter((stack) => !stack.itemId.startsWith('ITEM-FILL-')) }
        break
      case 'progress':
        out = json(stepProgressView(db, save, str(op, 'questId'), str(op, 'stepId')))
        break
      case 'conditions':
        out = (op.tokens as string[]).map((raw) => {
          const token = parseDialogueTokens(raw)[0]!
          const check = checkDialogueCondition(db, save, token)
          return { token: raw, holds: check.holds, reason: check.reason }
        })
        break
      case 'cheatAbandon': {
        const result = cheatAbandonQuest(save, str(op, 'questId'))
        out = result.ok
          ? { ok: true, deletedHandIns: json(result.deletedHandIns) }
          : { ok: false, reason: result.reason }
        if (result.ok) save = result.save
        break
      }
      case 'completeQuest': {
        const result = completeQuest(db, save, str(op, 'questId'), { useFavourites: op.useFavourites === true })
        out = result.ok ? { ok: true, rewards: result.rewards.map((line) => line.label) } : json(result)
        if (result.ok) save = result.save
        break
      }
      case 'reload':
        save = parseSave(JSON.parse(JSON.stringify(save)), FIXED_TIMESTAMP_MS)
        break
      case 'setLocation':
        save = { ...save, currentLocationId: str(op, 'locationId') }
        break
      case 'setQuest': {
        const questId = str(op, 'questId')
        const row: QuestProgress = {
          questId,
          status: str(op, 'status') as QuestProgress['status'],
          progress: Number(op.progress ?? 0),
          ...(op.counters ? { counters: op.counters as Record<string, number> } : {}),
        }
        save = { ...save, quests: [...save.quests.filter((quest) => quest.questId !== questId), row] }
        break
      }
      case 'autoStartOnSeed':
        save = applyQuestAutoStartOnSeed(db, save)
        break
      case 'panelTalk':
        save = applyQuestTalkProgress(db, save, str(op, 'npcId'))
        break
      case 'oldTalk': {
        // The old panel's Continue (`quest_talk`).
        const result = talkWithQuestNpc(db, save, str(op, 'npcId'))
        out = result.ok ? { ok: true, message: result.message } : { ok: false, reason: result.reason }
        if (result.ok) save = result.save
        break
      }
      case 'gather':
        save = applyQuestActionProgress(db, save, str(op, 'actionId'), Number(op.amount ?? 1))
        break
      case 'plant':
        save = applyQuestPlantProgress(db, save, [str(op, 'itemId')], op.compost === true)
        break
      case 'skill':
        out = json(getSkillProgress(save, str(op, 'skillId')))
        break
      default:
        throw new Error(`Unknown dialogue script op: ${String(op.op)}`)
    }
    steps.push({ op: op.op as string, out, state: digest(save) })
  }
  return { steps, save: asJson(save) }
}

function choose(dialogueId: string, nodeId: string, choiceId: string): Op {
  return { op: 'choose', dialogueId, nodeId, choiceId }
}

const KING = (choiceId: string) => choose('DLG-9001', 'DNODE-9001', choiceId)
const FENNEL = (choiceId: string) => choose('DLG-9002', 'DNODE-9011', choiceId)
const GIFTS = (choiceId: string) => choose('DLG-9003', 'DNODE-9021', choiceId)
const setItem = (itemId: string, quantity: number): Op => ({ op: 'setItem', itemId, quantity })
const feastProgress: Op = { op: 'progress', questId: 'QST-9001', stepId: 'QSTP-9002' }
const confirmed = (op: Op): Op => ({ ...op, useFavourites: true })
/** Exact stacks of one item: `[quantity, favourite]` each. */
const stacks = (itemId: string, ...entries: Array<[number, boolean]>): Op => ({
  op: 'setStacks',
  itemId,
  stacks: entries.map(([quantity, favorite]) => ({ quantity, favorite })),
})

const SCRIPTS: Record<string, Op[]> = {
  // 1. Condition matrix incl. negation, step_ready, has_book, unknown tokens.
  'conditions-matrix': [
    {
      op: 'conditions',
      tokens: [
        'quest_active:QST-9001',
        '!quest_active:QST-9001',
        'quest_done:QST-9001',
        '!quest_done:QST-9001',
        'quest_step:QST-9001:QSTP-9001',
        'dialogue_done:DLG-9001',
        '!dialogue_done:DLG-9001',
        `has_item:${BAKED_POTATO}`,
        `has_item:${BAKED_POTATO}:3`,
        `!has_item:${BAKED_POTATO}`,
        'total_level:1',
        'total_level:999999',
        'skill:SKL-0001:1',
        'skill:SKL-0001:99',
        'flag:met-fennel',
        '!flag:met-fennel',
        'step_ready:QST-9001:QSTP-9002',
        'has_book:BOOK-0001',
        '!has_book:BOOK-0001',
        'mystery_token:QST-9001',
        '!mystery_token:QST-9001',
        'has_item:',
        'total_level:abc',
      ],
    },
    KING('DCH-9001'),
    setItem(BAKED_POTATO, 2),
    GIFTS('DCH-9024'),
    GIFTS('DCH-9023'),
    {
      op: 'conditions',
      tokens: [
        'quest_active:QST-9001',
        '!quest_active:QST-9001',
        'quest_step:QST-9001:QSTP-9001',
        'quest_step:QST-9001:QSTP-9002',
        `has_item:${BAKED_POTATO}:3`,
        `has_item:${BAKED_POTATO}:2`,
        'flag:met-fennel',
        '!flag:met-fennel',
        'step_ready:QST-9001:QSTP-9002',
        '!step_ready:QST-9001:QSTP-9002',
        'has_book:BOOK-0001',
        '!has_book:BOOK-0001',
      ],
    },
    setItem(BAKED_POTATO, 0),
    { op: 'conditions', tokens: ['step_ready:QST-9001:QSTP-9002'] },
    { op: 'npc', npcId: 'NPC-9001' },
    { op: 'start', dialogueId: 'DLG-9005' },
    { op: 'view', dialogueId: 'DLG-9001', nodeId: 'DNODE-9001' },
    GIFTS('DCH-9027'),
  ],

  // 2. Show: 4/5 fails with counts; 5/5 latches without taking; selling after stays done.
  show: [
    FENNEL('DCH-9011'),
    setItem(BAKED_POTATO, 4),
    { op: 'progress', questId: 'QST-9002', stepId: 'QSTP-9011' },
    FENNEL('DCH-9012'),
    setItem(BAKED_POTATO, 5),
    FENNEL('DCH-9012'),
    { op: 'progress', questId: 'QST-9002', stepId: 'QSTP-9011' },
    setItem(BAKED_POTATO, 0),
    { op: 'conditions', tokens: ['quest_step:QST-9002:QSTP-9011'] },
    { op: 'view', dialogueId: 'DLG-9002', nodeId: 'DNODE-9011' },
    FENNEL('DCH-9013'),
  ],

  // 3. HandIn: 6 then 4; 15 when 4 are needed takes 4; items tracked apart; 6/10 progress.
  'hand-in': [
    KING('DCH-9001'),
    setItem(BAKED_POTATO, 6),
    KING('DCH-9002'),
    feastProgress,
    setItem(BAKED_POTATO, 15),
    setItem(COOKED_PERCH, 6),
    KING('DCH-9002'),
    feastProgress,
    KING('DCH-9002'),
    KING('DCH-9006'),
    setItem(COOKED_PERCH, 4),
    KING('DCH-9002'),
    feastProgress,
    { op: 'conditions', tokens: ['step_ready:QST-9001:QSTP-9002'] },
  ],

  // 5. QA: once-only gift with a full bag, then a free slot, then a third try.
  'gift-full-bag': [
    FENNEL('DCH-9011'),
    { op: 'fillBag', free: 0 },
    GIFTS('DCH-9021'),
    { op: 'view', dialogueId: 'DLG-9003', nodeId: 'DNODE-9021' },
    { op: 'clearFillers' },
    { op: 'fillBag', free: 1 },
    GIFTS('DCH-9021'),
    GIFTS('DCH-9021'),
    { op: 'view', dialogueId: 'DLG-9003', nodeId: 'DNODE-9021' },
  ],

  // 6. A failing action anywhere leaves the save byte-identical.
  rollback: [
    setItem(COOKED_PERCH, 3),
    GIFTS('DCH-9026'),
    FENNEL('DCH-9012'),
    KING('DCH-9002'),
    KING('DCH-9003'),
  ],

  // 7. grant_book unlocks in the Library, never the bag, and is idempotent.
  'grant-book': [GIFTS('DCH-9023'), GIFTS('DCH-9023'), { op: 'conditions', tokens: ['has_book:BOOK-0001'] }],

  // 8. Reward Mode dialogue pays nothing; legacy pays; Grand Feast end to end.
  'reward-mode': [
    choose('DLG-9004', 'DNODE-9031', 'DCH-9031'),
    choose('DLG-9004', 'DNODE-9031', 'DCH-9032'),
    { op: 'npc', npcId: 'NPC-9001' },
    { op: 'start', dialogueId: 'DLG-9001' },
    KING('DCH-9001'),
    setItem(BAKED_POTATO, 10),
    setItem(COOKED_PERCH, 10),
    KING('DCH-9002'),
    feastProgress,
    KING('DCH-9003'),
    { op: 'view', dialogueId: 'DLG-9001', nodeId: 'DNODE-9001' },
  ],

  // 9. Cheat abandon mid hand-in: counters, held items and this quest's gift flags go.
  'cheat-abandon': [
    FENNEL('DCH-9011'),
    GIFTS('DCH-9021'),
    GIFTS('DCH-9022'),
    GIFTS('DCH-9024'),
    KING('DCH-9001'),
    setItem(BAKED_POTATO, 6),
    setItem(COOKED_PERCH, 2),
    KING('DCH-9002'),
    feastProgress,
    { op: 'reload' },
    { op: 'cheatAbandon', questId: 'QST-9001' },
    feastProgress,
    { op: 'cheatAbandon', questId: 'QST-9001' },
    { op: 'reload' },
    GIFTS('DCH-9022'),
    GIFTS('DCH-9022'),
    GIFTS('DCH-9021'),
    KING('DCH-9001'),
    feastProgress,
  ],

  // QA follow-up: items only in the bank count as 0; Show and HandIn refuse them.
  'bank-only': [
    FENNEL('DCH-9011'),
    KING('DCH-9001'),
    setItem(BAKED_POTATO, 0),
    setItem(COOKED_PERCH, 0),
    { op: 'setBank', itemId: BAKED_POTATO, quantity: 20 },
    { op: 'setBank', itemId: COOKED_PERCH, quantity: 20 },
    { op: 'progress', questId: 'QST-9002', stepId: 'QSTP-9011' },
    feastProgress,
    {
      op: 'conditions',
      tokens: [`has_item:${BAKED_POTATO}`, 'step_ready:QST-9002:QSTP-9011', 'step_ready:QST-9001:QSTP-9002'],
    },
    FENNEL('DCH-9012'),
    KING('DCH-9002'),
    KING('DCH-9006'),
    { op: 'view', dialogueId: 'DLG-9001', nodeId: 'DNODE-9001' },
  ],

  // QA follow-up: hand_in succeeds, then grant_item hits no_room; nothing sticks.
  'mid-chain-rollback': [
    KING('DCH-9001'),
    setItem(BAKED_POTATO, 15),
    { op: 'fillBag', free: 0 },
    GIFTS('DCH-9028'),
    feastProgress,
    { op: 'clearFillers' },
    GIFTS('DCH-9028'),
    feastProgress,
  ],

  // Conor: hearted stacks count everywhere; taking one needs useFavourites,
  // per request. Covers Show, hand_in and take_item, and the bank never counts.
  favourites: [
    FENNEL('DCH-9011'),
    stacks(BAKED_POTATO, [5, true]),
    { op: 'progress', questId: 'QST-9002', stepId: 'QSTP-9011' },
    FENNEL('DCH-9012'),
    KING('DCH-9001'),
    stacks(BAKED_POTATO, [10, true]),
    { op: 'setBank', itemId: BAKED_POTATO, quantity: 50 },
    { op: 'setBank', itemId: COOKED_PERCH, quantity: 50 },
    feastProgress,
    { op: 'conditions', tokens: ['step_ready:QST-9001:QSTP-9002'] },
    { op: 'view', dialogueId: 'DLG-9001', nodeId: 'DNODE-9001' },
    // Unconfirmed with only hearted stacks: prompt, nothing taken, no progress or gift flag.
    KING('DCH-9002'),
    GIFTS('DCH-9030'),
    // Mixed: the prompt names only what hearted stacks would supply; yes takes unhearted first.
    stacks(BAKED_POTATO, [10, true], [4, false]),
    KING('DCH-9002'),
    confirmed(KING('DCH-9002')),
    feastProgress,
    // Hand-in plus gift: prompt leaves the gift flag unset; yes commits both.
    stacks(COOKED_PERCH, [6, true]),
    GIFTS('DCH-9030'),
    confirmed(GIFTS('DCH-9030')),
    feastProgress,
    // A yes does not carry over: the next hand-in that needs hearted stacks asks again.
    stacks(COOKED_PERCH, [6, true]),
    KING('DCH-9002'),
    // Enough unhearted: no prompt, hearted stack untouched.
    stacks(COOKED_PERCH, [5, true], [4, false]),
    KING('DCH-9002'),
    feastProgress,
    // take_item: the same rules.
    stacks(COOKED_PERCH, [6, true]),
    GIFTS('DCH-9029'),
    confirmed(GIFTS('DCH-9029')),
    GIFTS('DCH-9029'),
    stacks(COOKED_PERCH, [5, true], [3, false]),
    GIFTS('DCH-9029'),
    stacks(COOKED_PERCH, [5, true], [1, false]),
    confirmed(GIFTS('DCH-9029')),
  ],

  // 11. Partial hand-in survives logout / login.
  'hand-in-reload': [
    KING('DCH-9001'),
    setItem(BAKED_POTATO, 6),
    KING('DCH-9002'),
    { op: 'reload' },
    feastProgress,
    setItem(BAKED_POTATO, 4),
    KING('DCH-9002'),
    { op: 'reload' },
    feastProgress,
  ],

  // 12. Exactly enough free slots succeeds; stacks already held cost no slot.
  'room-exact': [
    setItem(BAKED_POTATO, 1),
    { op: 'fillBag', free: 1 },
    GIFTS('DCH-9025'),
    { op: 'clearFillers' },
    { op: 'fillBag', free: 2 },
    GIFTS('DCH-9025'),
    { op: 'fillBag', free: 0 },
    GIFTS('DCH-9025'),
  ],

  // 13. A quest reward claimed with a full bag gives nothing and stays claimable.
  'quest-reward-full-bag': [
    KING('DCH-9001'),
    setItem(BAKED_POTATO, 10),
    setItem(COOKED_PERCH, 10),
    KING('DCH-9002'),
    { op: 'fillBag', free: 0 },
    KING('DCH-9003'),
    { op: 'view', dialogueId: 'DLG-9001', nodeId: 'DNODE-9001' },
    { op: 'clearFillers' },
    KING('DCH-9003'),
  ],

  // 14. A favourited hand-in with a full bag reports no_room, not the favourites prompt, yes or no.
  'favourite-hand-in-full-bag': [
    KING('DCH-9001'),
    stacks(BAKED_POTATO, [12, true]),
    stacks(COOKED_PERCH, [12, true]),
    { op: 'fillBag', free: 0 },
    GIFTS('DCH-9030'),
    confirmed(GIFTS('DCH-9030')),
    feastProgress,
    { op: 'clearFillers' },
    GIFTS('DCH-9030'),
    confirmed(GIFTS('DCH-9030')),
    feastProgress,
  ],

  // 15. A legacy quest completed by dialogue with a full bag reports no_room and stays active.
  'legacy-dialogue-complete-full-bag': [
    { op: 'fillBag', free: 0 },
    choose('DLG-9004', 'DNODE-9031', 'DCH-9031'),
    { op: 'clearFillers' },
    choose('DLG-9004', 'DNODE-9031', 'DCH-9031'),
  ],
}

const completeOp = (questId: string, useFavourites = false): Op =>
  useFavourites ? { op: 'completeQuest', questId, useFavourites } : { op: 'completeQuest', questId }
const LEGACY = (choiceId: string) => choose('DLG-9004', 'DNODE-9031', choiceId)

/**
 * Legacy quest turn-ins: QST-9005 delivers 5 Baked Potato for a Golden Spud and
 * 100 gold; QST-9006 pays two item stacks after one Talk step.
 */
const LEGACY_PATCH: Patch = {
  ...DIALOGUE_PATCH,
  Quests: [
    ...DIALOGUE_PATCH.Quests!,
    quest('QST-9005', 'Test Legacy Deliver', 'NPC-9001', {
      Notes: `Deliver: ${BAKED_POTATO} x5; RewardGold: 100`,
      'Reward Item ID': GOLDEN_SPUD,
      'Reward Item Quantity': 1,
    }),
    quest('QST-9006', 'Test Legacy Seeds', 'NPC-9001', { Notes: `RewardItem: ${POTATO} x3, ${COOKED_PERCH} x2` }),
  ],
  QuestSteps: [...DIALOGUE_PATCH.QuestSteps!, step('QSTP-9061', 'QST-9006', 1, 'Talk', null, 'NPC-9001')],
  DialogueChoices: [
    ...DIALOGUE_PATCH.DialogueChoices!,
    choice('DCH-9051', 'DNODE-9031', 3, '!quest_active:QST-9005;!quest_done:QST-9005', 'start_quest:QST-9005'),
    choice('DCH-9052', 'DNODE-9031', 4, 'quest_active:QST-9005', 'complete_quest:QST-9005'),
    choice(
      'DCH-9061',
      'DNODE-9031',
      5,
      '!quest_active:QST-9006;!quest_done:QST-9006',
      'start_quest:QST-9006;talk_flag:QST-9006:QSTP-9061',
    ),
  ],
}

const LEGACY_SCRIPTS: Record<string, Op[]> = {
  // A full bag refuses the turn-in untouched, ahead of the favourites prompt; a delivery that empties a stack frees its slot.
  'legacy-turn-in-full-bag': [
    LEGACY('DCH-9051'),
    stacks(BAKED_POTATO, [7, false]),
    { op: 'fillBag', free: 0 },
    completeOp('QST-9005'),
    completeOp('QST-9005', true),
    stacks(BAKED_POTATO, [7, true]),
    completeOp('QST-9005'),
    completeOp('QST-9005', true),
    { op: 'clearFillers' },
    stacks(BAKED_POTATO, [5, false]),
    { op: 'fillBag', free: 0 },
    completeOp('QST-9005'),
  ],

  // Bag stacks only (the bank never counts), unhearted first; hearted stacks need a per-request yes.
  'legacy-turn-in-favourites': [
    LEGACY('DCH-9051'),
    { op: 'setBank', itemId: BAKED_POTATO, quantity: 50 },
    completeOp('QST-9005'),
    stacks(BAKED_POTATO, [3, true], [4, false]),
    completeOp('QST-9005'),
    completeOp('QST-9005', true),
  ],

  // complete_quest in a dialogue folds the quest's hearted delivery into the choice's prompt.
  'legacy-dialogue-complete-favourites': [
    LEGACY('DCH-9051'),
    stacks(BAKED_POTATO, [6, true]),
    LEGACY('DCH-9052'),
    confirmed(LEGACY('DCH-9052')),
  ],

  // Two reward stacks with one free slot: nothing is granted, then both arrive once there is room.
  'legacy-multi-item-full-bag': [
    LEGACY('DCH-9061'),
    { op: 'fillBag', free: 1 },
    completeOp('QST-9006'),
    { op: 'clearFillers' },
    { op: 'fillBag', free: 2 },
    completeOp('QST-9006'),
  ],
}

const FENNEL_FARM = 'LOC-0001'
const THRONE_ROOM = 'LOC-0016'
const CITADEL_PLAZA = 'LOC-0028'
const POTATO_SEED = 'ITEM-0324'
const CARROT_SEED = 'ITEM-0339'
const COMPOST = 'ITEM-0377'
const COOKING = 'SKL-0007'

const at = (locationId: string): Op => ({ op: 'setLocation', locationId })
const npcList = (npcId: string): Op => ({ op: 'npc', npcId })
const questRow = (questId: string, status: string, counters?: Record<string, number>): Op => ({
  op: 'setQuest',
  questId,
  status,
  ...(counters ? { counters } : {}),
})
const guide = (nodeId: string, choiceId: string) => choose('DLG-0001', nodeId, choiceId)
const feastPitch = (choiceId: string) => choose('DLG-0011', 'DNODE-0018', choiceId)
const feastHandIn = (choiceId: string) => choose('DLG-0012', 'DNODE-0020', choiceId)
const feastAfter = (choiceId: string) => choose('DLG-0012', 'DNODE-0022', choiceId)
const realFeastProgress: Op = { op: 'progress', questId: 'QST-0001', stepId: 'QSTP-0002' }
const seedGift = choose('DLG-0007', 'DNODE-0011', 'DCH-0014')
const compostTalk = choose('DLG-0008', 'DNODE-0013', 'DCH-0017')
const greenThumbEnd = choose('DLG-0010', 'DNODE-0016', 'DCH-0021')
const plantSeed: Op = { op: 'plant', itemId: POTATO_SEED, compost: true }
const gatherCompost: Op[] = [setItem(COMPOST, 1), { op: 'gather', actionId: 'ACN-0199' }]
/** Getting Started done and a found seed in the bag, which auto-starts Green Thumb. */
const greenThumbStartWith = (foundSeed: string): Op[] => [
  at(FENNEL_FARM),
  questRow('QST-0006', 'completed'),
  setItem(foundSeed, 1),
  { op: 'autoStartOnSeed' },
]
const greenThumbStart = greenThumbStartWith(POTATO_SEED)

/** Fennel (NPC-0014) and the King (NPC-0001) on the real launch content. */
const CONTENT_SCRIPTS: Record<string, Op[]> = {
  // Citadel Guide potato: once, even after closing mid-conversation; a full bag keeps it claimable.
  'citadel-guide-potato': [
    at(CITADEL_PLAZA),
    { op: 'fillBag', free: 0 },
    { op: 'start', dialogueId: 'DLG-0001' },
    guide('DNODE-0001', 'DCH-0001'),
    { op: 'clearFillers' },
    guide('DNODE-0001', 'DCH-0001'),
    { op: 'reload' },
    { op: 'start', dialogueId: 'DLG-0001' },
    guide('DNODE-0001', 'DCH-0001'),
    guide('DNODE-0001', 'DCH-0002'),
    npcList('NPC-0013'),
  ],

  // Getting Started: both Show steps take nothing; the panel talk alone no longer advances them.
  'getting-started': [
    at(FENNEL_FARM),
    questRow('QST-0006', 'active', {}),
    npcList('NPC-0014'),
    setItem(POTATO, 4),
    npcList('NPC-0014'),
    { op: 'view', dialogueId: 'DLG-0003', nodeId: 'DNODE-0004' },
    choose('DLG-0003', 'DNODE-0004', 'DCH-0005'),
    setItem(POTATO, 5),
    { op: 'panelTalk', npcId: 'NPC-0014' },
    { op: 'conditions', tokens: ['quest_step:QST-0006:QSTP-0014'] },
    choose('DLG-0003', 'DNODE-0004', 'DCH-0005'),
    choose('DLG-0003', 'DNODE-0004', 'DCH-0005'),
    npcList('NPC-0014'),
    setItem(POTATO, 0),
    questRow('QST-0006', 'active', {
      'step:QSTP-0013': 1,
      'step:QSTP-0014': 1,
      'visit:LOC-0023': 1,
      'process:RCP-0001': 5,
    }),
    setItem(BAKED_POTATO, 5),
    npcList('NPC-0014'),
    choose('DLG-0005', 'DNODE-0007', 'DCH-0009'),
    setItem(BAKED_POTATO, 0),
    { op: 'reload' },
    npcList('NPC-0014'),
    choose('DLG-0006', 'DNODE-0009', 'DCH-0012'),
    choose('DLG-0006', 'DNODE-0009', 'DCH-0012'),
    npcList('NPC-0014'),
  ],

  // A Fennel step finished under the old talk flow (latched) stays done.
  'getting-started-latched': [
    at(FENNEL_FARM),
    questRow('QST-0006', 'active', {
      'talk:NPC-0014': 1,
      'talk:NPC-0014:QSTP-0014': 1,
      'step:QSTP-0013': 1,
      'step:QSTP-0014': 1,
    }),
    { op: 'conditions', tokens: ['quest_step:QST-0006:QSTP-0015', 'quest_step:QST-0006:QSTP-0014'] },
    npcList('NPC-0014'),
    questRow('QST-0006', 'active', {
      'talk:NPC-0014': 1,
      'talk:NPC-0014:QSTP-0014': 1,
      'talk:NPC-0014:QSTP-0016': 1,
      'step:QSTP-0013': 1,
      'step:QSTP-0014': 1,
      'step:QSTP-0015': 1,
      'step:QSTP-0016': 1,
    }),
    { op: 'reload' },
    npcList('NPC-0014'),
    choose('DLG-0006', 'DNODE-0009', 'DCH-0012'),
  ],

  // Green Thumb end to end: 1 gifted seed + quest completion (3 + 3 + Guide), each once.
  'green-thumb': [
    ...greenThumbStart,
    npcList('NPC-0014'),
    { op: 'start', dialogueId: 'DLG-0007' },
    seedGift,
    seedGift,
    npcList('NPC-0014'),
    { op: 'reload' },
    seedGift,
    compostTalk,
    ...gatherCompost,
    compostTalk,
    plantSeed,
    npcList('NPC-0014'),
    greenThumbEnd,
    greenThumbEnd,
    seedGift,
    npcList('NPC-0014'),
  ],

  // A full bag refuses the seed without setting the gift flag or advancing the step.
  // The found seed is a carrot, so the gifted potato seed needs a new slot.
  'green-thumb-full-bag': [
    ...greenThumbStartWith(CARROT_SEED),
    { op: 'fillBag', free: 0 },
    seedGift,
    { op: 'view', dialogueId: 'DLG-0007', nodeId: 'DNODE-0011' },
    { op: 'clearFillers' },
    seedGift,
  ],

  // Midway under the old flow: QSTP-0023 done with the GiveOnTalk seed, so no second seed.
  'green-thumb-old-seed': [
    at(FENNEL_FARM),
    questRow('QST-0006', 'completed'),
    questRow('QST-0011', 'active', {
      'give:ITEM-0324': 1,
      'talk:NPC-0014': 1,
      'talk:NPC-0014:QSTP-0023': 1,
      'step:QSTP-0023': 1,
    }),
    setItem(POTATO_SEED, 2),
    npcList('NPC-0014'),
    seedGift,
    ...gatherCompost,
    compostTalk,
    plantSeed,
    greenThumbEnd,
    seedGift,
  ],

  // Players who already finished get nothing new.
  'already-done': [
    at(FENNEL_FARM),
    questRow('QST-0006', 'completed'),
    questRow('QST-0011', 'completed'),
    setItem(POTATO_SEED, 3),
    { op: 'autoStartOnSeed' },
    npcList('NPC-0014'),
    seedGift,
    greenThumbEnd,
    at(THRONE_ROOM),
    questRow('QST-0001', 'completed'),
    setItem(BAKED_POTATO, 10),
    setItem(COOKED_PERCH, 10),
    npcList('NPC-0001'),
    feastPitch('DCH-0023'),
    feastHandIn('DCH-0026'),
    feastHandIn('DCH-0030'),
  ],

  // /abandonquest clears Green Thumb's gift flag, so the seed can be claimed once more.
  'green-thumb-abandon': [
    ...greenThumbStart,
    seedGift,
    { op: 'cheatAbandon', questId: 'QST-0011' },
    { op: 'autoStartOnSeed' },
    seedGift,
    seedGift,
  ],

  // Grand Feast: hand in over several visits, then the quest pays once.
  'grand-feast': [
    at(THRONE_ROOM),
    npcList('NPC-0001'),
    { op: 'start', dialogueId: 'DLG-0011' },
    feastPitch('DCH-0023'),
    npcList('NPC-0001'),
    { op: 'start', dialogueId: 'DLG-0012' },
    feastHandIn('DCH-0026'),
    setItem(BAKED_POTATO, 6),
    feastHandIn('DCH-0026'),
    feastAfter('DCH-0032'),
    { op: 'reload' },
    realFeastProgress,
    setItem(BAKED_POTATO, 9),
    setItem(COOKED_PERCH, 4),
    feastHandIn('DCH-0026'),
    realFeastProgress,
    setItem(COOKED_PERCH, 12),
    feastHandIn('DCH-0026'),
    { op: 'skill', skillId: COOKING },
    npcList('NPC-0001'),
    { op: 'start', dialogueId: 'DLG-0012' },
    feastHandIn('DCH-0030'),
    { op: 'skill', skillId: COOKING },
    feastHandIn('DCH-0030'),
    feastAfter('DCH-0031'),
    npcList('NPC-0001'),
  ],

  // Midway through the old feast: King heard (latched), food in the bag, never turned in.
  'grand-feast-old-save': [
    at(THRONE_ROOM),
    questRow('QST-0001', 'active', { 'talk:NPC-0001': 1, 'talk:NPC-0001:QSTP-0001': 1, 'step:QSTP-0001': 1 }),
    setItem(BAKED_POTATO, 10),
    setItem(COOKED_PERCH, 10),
    npcList('NPC-0001'),
    feastHandIn('DCH-0026'),
    feastAfter('DCH-0031'),
    { op: 'skill', skillId: COOKING },
    questRow('QST-0001', 'active', {}),
    npcList('NPC-0001'),
    { op: 'view', dialogueId: 'DLG-0011', nodeId: 'DNODE-0018' },
    feastPitch('DCH-0029'),
    npcList('NPC-0001'),
  ],

  // The seed auto-start the panel commits on open (`quest_autostart_seed` runs
  // only this): nothing before Getting Started is done, Green Thumb once it
  // is, never twice, and a seed kept in the bank counts.
  'green-thumb-autostart': [
    at(FENNEL_FARM),
    setItem(POTATO_SEED, 1),
    { op: 'autoStartOnSeed' },
    npcList('NPC-0014'),
    questRow('QST-0006', 'active', {}),
    { op: 'autoStartOnSeed' },
    npcList('NPC-0014'),
    questRow('QST-0006', 'completed'),
    { op: 'autoStartOnSeed' },
    npcList('NPC-0014'),
    { op: 'autoStartOnSeed' },
    questRow('QST-0011', 'inactive'),
    setItem(POTATO_SEED, 0),
    { op: 'setBank', itemId: POTATO_SEED, quantity: 1 },
    { op: 'autoStartOnSeed' },
    npcList('NPC-0014'),
  ],

  // The old panel's Continue at a Talk step a dialogue talk_flag owns leaves
  // the step current, so the gift, the brief and the farewell still open.
  'old-talk-keeps-dialogue-steps': [
    ...greenThumbStart,
    { op: 'oldTalk', npcId: 'NPC-0014' },
    { op: 'conditions', tokens: ['quest_step:QST-0011:QSTP-0023'] },
    npcList('NPC-0014'),
    seedGift,
    { op: 'conditions', tokens: ['quest_step:QST-0011:QSTP-0024'] },
    at(THRONE_ROOM),
    questRow('QST-0001', 'active', {}),
    { op: 'oldTalk', npcId: 'NPC-0001' },
    { op: 'conditions', tokens: ['quest_step:QST-0001:QSTP-0001'] },
    npcList('NPC-0001'),
    feastPitch('DCH-0029'),
    { op: 'conditions', tokens: ['quest_step:QST-0001:QSTP-0002'] },
    at(FENNEL_FARM),
    questRow('QST-0006', 'active', {
      'step:QSTP-0013': 1,
      'step:QSTP-0014': 1,
      'step:QSTP-0015': 1,
      'step:QSTP-0016': 1,
    }),
    { op: 'oldTalk', npcId: 'NPC-0014' },
    { op: 'conditions', tokens: ['quest_step:QST-0006:QSTP-0022'] },
    npcList('NPC-0014'),
    choose('DLG-0006', 'DNODE-0009', 'DCH-0012'),
  ],

  // Visiting the Citadel: Guide and Market Master remind; they do not advance the Visit step.
  'visiting-the-citadel': [
    at(CITADEL_PLAZA),
    npcList('NPC-0013'),
    npcList('NPC-0006'),
    questRow('QST-0004', 'active'),
    npcList('NPC-0013'),
    npcList('NPC-0006'),
    { op: 'start', dialogueId: 'DLG-0013' },
    choose('DLG-0013', 'DNODE-0023', 'DCH-0033'),
    { op: 'start', dialogueId: 'DLG-0014' },
    choose('DLG-0014', 'DNODE-0024', 'DCH-0034'),
    questRow('QST-0004', 'completed'),
    npcList('NPC-0013'),
    npcList('NPC-0006'),
  ],
}

/** 10. A v61 save as it was stored: no dialogueFlags, mid-quest and completed rows. */
function v61Save(): JsonValue {
  const save = asJson({
    ...startingSave(),
    completedDialogueIds: ['DLG-0001'],
    quests: [
      { questId: 'QST-9001', status: 'active', progress: 7, counters: { 'step:QSTP-9001': 1, [`handIn:QSTP-9002:${BAKED_POTATO}`]: 6 } },
      { questId: 'QST-9002', status: 'completed', progress: 5, counters: {} },
    ],
  }) as Record<string, JsonValue>
  delete save.dialogueFlags
  return { ...save, saveVersion: 61 }
}

function messyV61Save(): JsonValue {
  return { ...(v61Save() as Record<string, JsonValue>), dialogueFlags: ['b', 'a', 'b', '', 7, 'gift:QST-9001:feast'] }
}

const MIGRATION_OPS: Op[] = [
  { op: 'npc', npcId: 'NPC-9002' },
  feastProgress,
  GIFTS('DCH-9021'),
  FENNEL('DCH-9011'),
  setItem(BAKED_POTATO, 4),
  KING('DCH-9002'),
]

function migrationOutput(legacy: JsonValue): JsonValue {
  const db = patchedDatabase(DIALOGUE_PATCH)
  const migrated = migrateSave(legacy as unknown as PlayerSave, FIXED_TIMESTAMP_MS)
  return { migrated: asJson(migrated), script: runDialogueScript(db, migrated, MIGRATION_OPS) }
}

/** Synthetic rows that each break one validator rule. */
const BROKEN_PATCH: Patch = {
  ...DIALOGUE_PATCH,
  QuestSteps: [
    ...DIALOGUE_PATCH.QuestSteps!,
    step('QSTP-9901', 'QST-9001', 9, 'HandIn', null, 'NPC-9999'),
    step('QSTP-9902', 'QST-9001', 10, 'Show', `${BAKED_POTATO}:0;ITEM-NOPE:2;${BAKED_POTATO}:1`, 'NPC-9001'),
    step('QSTP-9903', 'QST-9001', 11, 'talk', null, 'NPC-9001'),
    step('QSTP-9904', 'QST-9001', 12, 'Talk', `${BAKED_POTATO}:1`, 'NPC-9001'),
  ],
  Quests: [...DIALOGUE_PATCH.Quests!, quest('QST-9901', 'Bad Mode', 'NPC-9001', { 'Reward Mode': 'later' })],
  Dialogues: [
    ...DIALOGUE_PATCH.Dialogues!,
    dialogue('DLG-9901', 'NPC-9999', 'DNODE-9001', { Condition: 'quest_done:QST-NOPE;moon_phase:full', Priority: 1.5 }),
  ],
  DialogueChoices: [
    ...DIALOGUE_PATCH.DialogueChoices!,
    choice('DCH-9901', 'DNODE-9021', 9, 'skill:SKL-0001:x;!flag', `grant_item:${POTATO}:1`),
    choice('DCH-9902', 'DNODE-9021', 10, '!flag:plain', `grant_item:${POTATO}:1;set_flag:plain`),
    choice('DCH-9903', 'DNODE-9021', 11, null, 'show_items:QST-9001:QSTP-9002;!set_flag:x;hand_in:QST-9001'),
    choice('DCH-9904', 'DNODE-NOPE', 12, null, null),
    choice('DCH-9905', 'DNODE-9021', 13, null, null, { 'Next Node ID': 'DNODE-9001' }),
  ],
}

export const dialogueScenarios: ParityScenario[] = [
  ...Object.entries(SCRIPTS).map(([name, ops]) =>
    scenario(
      'dialogue/engine',
      name,
      {
        source: 'content',
        nowMs: FIXED_TIMESTAMP_MS,
        patch: DIALOGUE_PATCH as unknown as JsonValue,
        save: asJson(startingSave()),
        ops: ops as JsonValue,
      },
      () => runDialogueScript(patchedDatabase(DIALOGUE_PATCH), startingSave(), ops),
    ),
  ),
  ...Object.entries(LEGACY_SCRIPTS).map(([name, ops]) =>
    scenario(
      'dialogue/engine',
      name,
      {
        source: 'content',
        nowMs: FIXED_TIMESTAMP_MS,
        patch: LEGACY_PATCH as unknown as JsonValue,
        save: asJson(startingSave()),
        ops: ops as JsonValue,
      },
      () => runDialogueScript(patchedDatabase(LEGACY_PATCH), startingSave(), ops),
    ),
  ),

  ...Object.entries(CONTENT_SCRIPTS).map(([name, ops]) =>
    scenario(
      'dialogue/content',
      name,
      { source: 'content', launch: true, nowMs: FIXED_TIMESTAMP_MS, save: asJson(launchStartingSave()), ops: ops as JsonValue },
      () => runDialogueScript(launchDatabase(), launchStartingSave(), ops),
    ),
  ),

  scenario('dialogue/migration', 'from-v61', { source: 'content', nowMs: FIXED_TIMESTAMP_MS, patch: DIALOGUE_PATCH as unknown as JsonValue, legacy: v61Save(), ops: MIGRATION_OPS as JsonValue }, () =>
    migrationOutput(v61Save()),
  ),
  scenario('dialogue/migration', 'from-v61-messy-flags', { source: 'content', nowMs: FIXED_TIMESTAMP_MS, patch: DIALOGUE_PATCH as unknown as JsonValue, legacy: messyV61Save(), ops: MIGRATION_OPS as JsonValue }, () =>
    migrationOutput(messyV61Save()),
  ),

  scenario('dialogue/validate', 'content', { source: 'content' }, () => ({
    issues: validateDialogueContent(contentDatabase()) as unknown as JsonValue,
  })),
  scenario('dialogue/validate', 'test-patch', { source: 'content', patch: DIALOGUE_PATCH as unknown as JsonValue }, () => ({
    issues: validateDialogueContent(patchedDatabase(DIALOGUE_PATCH)) as unknown as JsonValue,
  })),
  scenario('dialogue/validate', 'broken', { source: 'content', patch: BROKEN_PATCH as unknown as JsonValue }, () => ({
    issues: validateDialogueContent(patchedDatabase(BROKEN_PATCH)) as unknown as JsonValue,
  })),
]
