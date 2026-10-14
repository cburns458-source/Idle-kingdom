import {
  acceptQuestFromNpc,
  learnMentorProjects,
  npcConversation,
  questPitchLine,
  skillForKnowledgeNpc,
  takeMerchantTip,
} from '../../game/npcs/conversation'
import type { GameDatabase } from '../../game/data/types'
import type { PlayerSave } from '../../game/save/types'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import { contentDatabase, contentDatabaseWithRows, type ExtraRows } from './contentDatabase'
import { asJson, baseSave, FIXED_TIMESTAMP_MS, forgeSave, questSave } from './saveFixtures'

type SaveKind = 'base' | 'forge' | 'quest'

function saveFor(kind: SaveKind): PlayerSave {
  const db = contentDatabase()
  if (kind === 'base') return baseSave(db)
  if (kind === 'forge') return forgeSave(db)
  return questSave(db)
}

function withSave(kind: SaveKind, extra: Record<string, JsonValue> = {}): JsonValue {
  return { source: 'content', save: asJson(saveFor(kind)), ...extra }
}

function conversationsFor(db: GameDatabase, save: PlayerSave, npcIds: string[]): JsonValue {
  return npcIds.map((npcId) => {
    const npc = db.NPCs.find((row) => row['NPC ID'] === npcId)!
    return npcConversation(db, save, npc, FIXED_TIMESTAMP_MS)
  }) as unknown as JsonValue
}

/**
 * A closing line for the Barracks Guard, who only takes part in Lowly Beggar.
 * No shipped row gives a bystander one yet, so the fixture carries its own.
 */
const CLOSING_LINE_ROWS: ExtraRows = {
  QuestDialogue: [
    {
      'Dialogue ID': 'QDL-9001',
      'Quest ID': 'QST-0003',
      'NPC ID': 'NPC-0012',
      Line: 'Hmph.',
      Status: 'Confirmed',
      'Release Phase': 'Launch',
      Notes: 'When: completed',
    },
  ],
}

/** Giver, bystander with a closing line, bystander without one. */
const CLOSING_LINE_NPCS = ['NPC-0011', 'NPC-0012', 'NPC-0007']

/** At the barracks with Lowly Beggar in the given state. */
function lowlyBeggarSave(status: 'active' | 'completed'): PlayerSave {
  return {
    ...baseSave(contentDatabase()),
    currentLocationId: 'LOC-0017',
    quests: [
      status === 'completed'
        ? { questId: 'QST-0003', status, progress: 3, counters: {} }
        : { questId: 'QST-0003', status, progress: 1, counters: { 'talk:NPC-0011': 1 } },
    ],
  }
}

/** Merchants, mentors including Quill, and quest givers. */
const CONVERSATION_NPCS = [
  'NPC-0001',
  'NPC-0002',
  'NPC-0003',
  'NPC-0004',
  'NPC-0005',
  'NPC-0007',
  'NPC-0008',
  'NPC-0009',
]

const MENTOR_NPCS = ['NPC-0002', 'NPC-0003', 'NPC-0004', 'NPC-0007', 'NPC-9999']
const PITCH_QUESTS = ['QST-0001', 'QST-0002', 'QST-9999']

export const npcScenarios: ParityScenario[] = [
  ...(['base', 'forge', 'quest'] as const).map((kind) =>
    scenario('npcs/conversation', kind, withSave(kind, { npcIds: CONVERSATION_NPCS }), () => {
      const db = contentDatabase()
      const save = saveFor(kind)
      return {
        conversations: conversationsFor(db, save, CONVERSATION_NPCS),
        pitchLines: PITCH_QUESTS.map((questId) => questPitchLine(db, questId)),
        mentorSkills: MENTOR_NPCS.map((npcId) => skillForKnowledgeNpc(npcId)),
      } as unknown as JsonValue
    }),
  ),

  // A bystander's `When: completed` line keeps the quest on their panel once it
  // is done, and stays out of the way while it is still running.
  scenario(
    'npcs/conversation',
    'completed-line',
    {
      source: 'content',
      extraRows: CLOSING_LINE_ROWS,
      save: asJson(lowlyBeggarSave('completed')),
      activeSave: asJson(lowlyBeggarSave('active')),
      npcIds: CLOSING_LINE_NPCS,
    },
    () => {
      const db = contentDatabaseWithRows(CLOSING_LINE_ROWS)
      return {
        completed: conversationsFor(db, lowlyBeggarSave('completed'), CLOSING_LINE_NPCS),
        active: conversationsFor(db, lowlyBeggarSave('active'), CLOSING_LINE_NPCS),
      }
    },
  ),

  scenario('npcs/conversation', 'merchant-tip', withSave('base'), () => {
    const db = contentDatabase()
    const base = saveFor('base')
    const first = takeMerchantTip(db, base, 'NPC-0007')
    return {
      first: first ? { save: asJson(first.save), message: first.message } : null,
      // Listening twice must not pay twice.
      again: first ? takeMerchantTip(db, first.save, 'NPC-0007') : null,
      otherMerchant: takeMerchantTip(db, base, 'NPC-0008'),
    } as unknown as JsonValue
  }),

  scenario('npcs/conversation', 'mentor-unlock', withSave('base', { npcIds: MENTOR_NPCS }), () => {
    const db = contentDatabase()
    const base = saveFor('base')
    return {
      results: MENTOR_NPCS.map((npcId) => {
        const result = learnMentorProjects(db, base, npcId)
        return result.ok
          ? { npcId, ok: true, message: result.message, save: asJson(result.save) }
          : { npcId, ok: false, reason: result.reason }
      }),
    } as unknown as JsonValue
  }),

  ...(['base', 'quest'] as const).map((kind) =>
    scenario('npcs/conversation', `accept-${kind}`, withSave(kind, { questIds: PITCH_QUESTS }), () => {
      const db = contentDatabase()
      const save = saveFor(kind)
      return {
        results: PITCH_QUESTS.map((questId) => {
          const result = acceptQuestFromNpc(db, save, questId)
          return result.ok
            ? { questId, ok: true, message: result.message, save: asJson(result.save) }
            : { questId, ok: false, reason: result.reason }
        }),
      } as unknown as JsonValue
    }),
  ),
]
