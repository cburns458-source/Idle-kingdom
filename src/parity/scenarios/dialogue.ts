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
import { cheatAbandonQuest, completeQuest } from '../../game/quests/quests'
import { migrateSave } from '../../game/save/migrations'
import { parseSave } from '../../game/save/saveStore'
import type { PlayerSave } from '../../game/save/types'
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

function digest(save: PlayerSave): JsonValue {
  return {
    gold: save.gold,
    inventory: json(save.inventory),
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
        const result = chooseDialogue(db, save, str(op, 'dialogueId'), str(op, 'nodeId'), str(op, 'choiceId'))
        out = resultSummary(save, result)
        if (result.ok) save = result.save
        break
      }
      case 'setItem':
        save = setItemCount(save, str(op, 'itemId'), Number(op.quantity))
        break
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
        const result = completeQuest(db, save, str(op, 'questId'))
        out = result.ok ? { ok: true, rewards: result.rewards.map((line) => line.label) } : result
        if (result.ok) save = result.save
        break
      }
      case 'reload':
        save = parseSave(JSON.parse(JSON.stringify(save)), FIXED_TIMESTAMP_MS)
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
