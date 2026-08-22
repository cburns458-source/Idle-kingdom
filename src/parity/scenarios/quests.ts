import {
  parseStructuredObjectives,
  normalizeObjectiveKind,
  questObjectiveProgress,
} from '../../game/quests/objectives'
import {
  applyQuestDefeatProgress,
  applyQuestLearnRecipeProgress,
  applyQuestProcessProgress,
} from '../../game/quests/progress'
import {
  acceptQuest,
  asQuestRows,
  completeQuest,
  getQuest,
  getQuestProgress,
  isQuestRepeatable,
  questStatusLabel,
  questsForNpc,
} from '../../game/quests/quests'
import type { PlayerSave } from '../../game/save/types'
import {
  isLocationUnlocked,
  isSubMap,
  isSubMapGateway,
  enterSubMapLabel,
  gatewayLocationIdForSubMap,
  landingLocationIdFor,
  locationRequiresUnlock,
  subMapDisplayName,
  subMapIdForGateway,
  unlockLocation,
} from '../../game/world/submaps'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import { contentDatabase } from './contentDatabase'
import { asJson, baseSave, questSave, richSave } from './saveFixtures'

type SaveKind = 'base' | 'rich' | 'quest'

function saveFor(kind: SaveKind): PlayerSave {
  const db = contentDatabase()
  if (kind === 'base') return baseSave(db)
  if (kind === 'rich') return richSave(db)
  return questSave(db)
}

function withSave(kind: SaveKind, extra: Record<string, JsonValue> = {}): JsonValue {
  return { source: 'content', save: asJson(saveFor(kind)), ...extra }
}

/** Objective Type strings, including ones no quest row uses yet. */
const OBJECTIVE_TYPES = [
  'Gather / Deliver',
  'Multi Deliver',
  'Defeat',
  'Kill Monsters',
  'Combat trial',
  'Process',
  'Craft items',
  'Cook a feast',
  'Learn Recipe',
  'Restore Facility',
  'Construct Portal',
  'Unlock Travel',
  'Mount route',
  'Guild collaboration',
  'Something else',
  '',
  null,
]

const QUEST_IDS = ['QST-0001', 'QST-0002', 'QST-9999']
const NPC_IDS = ['NPC-0001', 'NPC-0005', 'NPC-0007']
const MAP_IDS = ['MAP-0001', 'MAP-0002', 'MAP-0003', 'MAP-0004', 'MAP-0006', 'MAP-0007', 'MAP-9999']
const GATEWAY_IDS = ['LOC-0002', 'LOC-0010', 'LOC-0013', 'LOC-0027', 'LOC-0001']

export const questScenarios: ParityScenario[] = [
  scenario(
    'quests/objective-kinds',
    'normalize',
    { source: 'content', types: OBJECTIVE_TYPES as JsonValue },
    () => ({ kinds: OBJECTIVE_TYPES.map((value) => normalizeObjectiveKind(value)) }),
  ),

  scenario('quests/objectives', 'all-rows', { source: 'content' }, () => {
    const db = contentDatabase()
    return {
      rows: asQuestRows(db).map((quest) => ({
        questId: quest['Quest ID'],
        repeatable: isQuestRepeatable(quest),
        structured: parseStructuredObjectives(quest),
      })),
      lookups: QUEST_IDS.map((questId) => getQuest(db, questId)?.['Quest ID'] ?? null),
      byNpc: NPC_IDS.map((npcId) => ({
        npcId,
        questIds: questsForNpc(db, npcId).map((quest) => quest['Quest ID']),
      })),
      statusLabels: (['inactive', 'active', 'completed'] as const).map((status) =>
        questStatusLabel(status),
      ),
    } as unknown as JsonValue
  }),

  ...(['base', 'rich', 'quest'] as const).map((kind) =>
    scenario('quests/progress-view', kind, withSave(kind), () => {
      const db = contentDatabase()
      const save = saveFor(kind)
      return {
        byQuest: asQuestRows(db).map((quest) => ({
          questId: quest['Quest ID'],
          progress: getQuestProgress(save, quest['Quest ID']),
          status: questObjectiveProgress(db, save, quest),
        })),
      } as unknown as JsonValue
    }),
  ),

  ...(['base', 'quest'] as const).flatMap((kind) =>
    QUEST_IDS.map((questId) =>
      scenario(
        'quests/accept',
        `${kind}-${questId.toLowerCase()}`,
        withSave(kind, { questId }),
        () => {
          const result = acceptQuest(contentDatabase(), saveFor(kind), questId)
          return (result.ok ? { ok: true, save: asJson(result.save) } : result) as unknown as JsonValue
        },
      ),
    ),
  ),

  ...(['base', 'quest'] as const).flatMap((kind) =>
    QUEST_IDS.map((questId) =>
      scenario(
        'quests/complete',
        `${kind}-${questId.toLowerCase()}`,
        withSave(kind, { questId }),
        () => {
          const result = completeQuest(contentDatabase(), saveFor(kind), questId)
          return (result.ok
            ? {
                ok: true,
                save: asJson(result.save),
                message: result.message,
                questName: result.questName,
                rewards: result.rewards.map((reward) => reward.label),
                pendingSkillXp: result.pendingSkillXp,
              }
            : result) as unknown as JsonValue
        },
      ),
    ),
  ),

  scenario('quests/counters', 'bumps', withSave('quest'), () => {
    const db = contentDatabase()
    const save = saveFor('quest')
    const defeated = applyQuestDefeatProgress(db, save, 'ENM-0001', 2)
    const processed = applyQuestProcessProgress(db, defeated, 'RCP-0001', 3)
    const learned = applyQuestLearnRecipeProgress(db, processed, 'RCP-0003')
    return {
      defeated: asJson(defeated),
      processed: asJson(processed),
      learned: asJson(learned),
      // A quest that is not active must not gain counters.
      inactive: asJson(applyQuestProcessProgress(db, { ...save, quests: [] }, 'RCP-0001', 1)),
      zeroAmount: asJson(applyQuestDefeatProgress(db, save, 'ENM-0001', 0)),
    }
  }),

  scenario('world/submaps', 'topology', withSave('base', { mapIds: MAP_IDS }), () => {
    const db = contentDatabase()
    return {
      maps: MAP_IDS.map((mapId) => ({
        mapId,
        subMap: isSubMap(db, mapId),
        displayName: subMapDisplayName(db, mapId),
        gateway: gatewayLocationIdForSubMap(db, mapId),
      })),
      gateways: GATEWAY_IDS.map((locationId) => {
        const location = db.Locations.find((row) => row['Location ID'] === locationId)!
        return {
          locationId,
          isGateway: isSubMapGateway(location),
          childMapId: subMapIdForGateway(db, locationId),
          landing: landingLocationIdFor(location),
          label: enterSubMapLabel(db, location),
        }
      }),
      locked: db.Locations.map((location) => ({
        locationId: location['Location ID'],
        requiresUnlock: locationRequiresUnlock(location),
        unlockedForBase: isLocationUnlocked(saveFor('base'), location),
      })),
      unlockOnce: unlockLocation({ unlockedLocationIds: [] }, 'LOC-0026'),
      unlockTwice: unlockLocation({ unlockedLocationIds: ['LOC-0026'] }, 'LOC-0026'),
    } as unknown as JsonValue
  }),
]
