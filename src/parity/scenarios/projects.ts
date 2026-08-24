import {
  hasNpcKnowledge,
  hasProjectKnowledge,
  knowledgeNpcForSkill,
  npcsAtLocation,
  shopIdForMerchant,
  unlockNpcKnowledge,
} from '../../game/npcs/knowledge'
import { completeSpecialProject, validateProjectCompletion } from '../../game/projects/engine'
import {
  defaultProjectId,
  describeProjectCompletion,
  projectDetail,
  projectMenuList,
} from '../../game/projects/menu'
import {
  isCompleteProject,
  maxProjectQuantity,
  maxProjectsFromGold,
  maxProjectsFromMaterials,
  meetsProjectKnowledge,
  meetsProjectSkills,
  projectInputs,
  projectSkillRequirements,
  projectsForFacility,
  specialProductionStationLabel,
  specialProductionStationsAt,
  unmetProjectSkillRequirements,
} from '../../game/projects/projects'
import type { PlayerSave } from '../../game/save/types'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import { contentDatabase } from './contentDatabase'
import { arcanaSave, asJson, baseSave, forgeSave } from './saveFixtures'

type SaveKind = 'base' | 'forge' | 'arcana'

function saveFor(kind: SaveKind): PlayerSave {
  const db = contentDatabase()
  if (kind === 'base') return baseSave(db)
  if (kind === 'forge') return forgeSave(db)
  return arcanaSave(db)
}

function withSave(kind: SaveKind, extra: Record<string, JsonValue> = {}): JsonValue {
  return { source: 'content', save: asJson(saveFor(kind)), ...extra }
}

const NOW_MS = Date.parse('2026-01-01T00:00:00.000Z')

const STATION_LOCATIONS = ['LOC-0025', 'LOC-0007', 'LOC-0030', 'LOC-0023', 'LOC-9999']
const KNOWLEDGE_SKILLS = ['SKL-0011', 'SKL-0012', 'SKL-0013', 'SKL-0007']
const NPC_LOCATIONS = [
  'LOC-0006',
  'LOC-0007',
  'LOC-0011',
  'LOC-0022',
  'LOC-0024',
  'LOC-0029',
  'LOC-9999',
]
const UNLOCK_NPCS = ['NPC-0003', 'NPC-0004', 'NPC-0001']

/** The three stations, one search that matches and one that cannot. */
const MENU_STATIONS = [
  { facilityId: 'FAC-0005', skillId: 'SKL-0011', query: 'axe' },
  { facilityId: 'FAC-0008', skillId: 'SKL-0013', query: 'enchant' },
  { facilityId: 'FAC-0003', skillId: 'SKL-0012', query: 'zzz' },
]

/** A tool, a level-gated tool, an enchantment, a spell, and a missing row. */
const MENU_PROJECTS = ['PRJ-0007', 'PRJ-0118', 'PRJ-0135', 'PRJ-0139', 'PRJ-9999']

const VALIDATE_CASES: Array<{
  name: string
  save: SaveKind
  projectId: string
  quantity: number
  target?: string | null
}> = [
  { name: 'ok-tool', save: 'forge', projectId: 'PRJ-0007', quantity: 1 },
  { name: 'ok-multi', save: 'forge', projectId: 'PRJ-0007', quantity: 3 },
  { name: 'unknown-project', save: 'forge', projectId: 'PRJ-9999', quantity: 1 },
  { name: 'wrong-location', save: 'arcana', projectId: 'PRJ-0007', quantity: 1 },
  { name: 'no-mentor', save: 'base', projectId: 'PRJ-0007', quantity: 1 },
  { name: 'skill-gate', save: 'forge', projectId: 'PRJ-0118', quantity: 1 },
  { name: 'zero-quantity', save: 'forge', projectId: 'PRJ-0007', quantity: 0 },
  { name: 'too-many', save: 'forge', projectId: 'PRJ-0007', quantity: 99 },
  { name: 'enchant-no-target', save: 'arcana', projectId: 'PRJ-0135', quantity: 1 },
  {
    name: 'enchant-inventory-target',
    save: 'arcana',
    projectId: 'PRJ-0135',
    quantity: 1,
    target: 'inv:3',
  },
  {
    name: 'enchant-equipped-target',
    save: 'arcana',
    projectId: 'PRJ-0135',
    quantity: 1,
    target: 'eq:SLOT-0001',
  },
  {
    name: 'enchant-many',
    save: 'arcana',
    projectId: 'PRJ-0135',
    quantity: 2,
    target: 'inv:3',
  },
]

export const projectScenarios: ParityScenario[] = [
  scenario('projects/rows', 'all', { source: 'content' }, () => {
    const db = contentDatabase()
    return {
      rows: db.Projects.map((project) => ({
        projectId: project['Project ID'],
        complete: isCompleteProject(project),
        inputs: projectInputs(project),
        skills: projectSkillRequirements(project),
      })),
    } as unknown as JsonValue
  }),

  ...(['base', 'forge', 'arcana'] as const).map((kind) =>
    scenario('projects/gates', kind, withSave(kind), () => {
      const db = contentDatabase()
      const save = saveFor(kind)
      return {
        rows: db.Projects.filter(isCompleteProject).map((project) => ({
          projectId: project['Project ID'],
          skills: meetsProjectSkills(save, project),
          knowledge: meetsProjectKnowledge(db, save, project),
          unmet: unmetProjectSkillRequirements(db, save, project),
          materialMax: maxProjectsFromMaterials(save, project),
          goldMax: maxProjectsFromGold(save, project),
          quantityMax: maxProjectQuantity(save, project),
        })),
      } as unknown as JsonValue
    }),
  ),

  scenario('projects/facility', 'listings', { source: 'content', locations: STATION_LOCATIONS }, () => {
    const db = contentDatabase()
    return {
      byFacility: ['FAC-0003', 'FAC-0005', 'FAC-0008', 'FAC-0013', 'FAC-0016'].map((facilityId) => ({
        facilityId,
        all: projectsForFacility(db, facilityId).map((project) => project['Project ID']),
        smithingOnly: projectsForFacility(db, facilityId, 'SKL-0011').map(
          (project) => project['Project ID'],
        ),
      })),
      stations: STATION_LOCATIONS.map((locationId) => ({
        locationId,
        stations: specialProductionStationsAt(db, locationId).map((station) => ({
          facilityId: station.facility['Facility ID'],
          skillId: station.skillId,
          skillName: station.skillName,
          label: station.label,
        })),
      })),
      labels: KNOWLEDGE_SKILLS.map((skillId) => specialProductionStationLabel(skillId, 'Fallback')),
    } as unknown as JsonValue
  }),

  ...VALIDATE_CASES.map((entry) =>
    scenario(
      'projects/validate',
      entry.name,
      withSave(entry.save, {
        projectId: entry.projectId,
        quantity: entry.quantity,
        target: entry.target ?? null,
      }),
      () =>
        validateProjectCompletion(
          contentDatabase(),
          saveFor(entry.save),
          entry.projectId,
          entry.quantity,
          entry.target,
        ) as unknown as JsonValue,
    ),
  ),

  ...VALIDATE_CASES.map((entry) =>
    scenario(
      'projects/complete',
      entry.name,
      withSave(entry.save, {
        projectId: entry.projectId,
        quantity: entry.quantity,
        target: entry.target ?? null,
        nowMs: NOW_MS,
      }),
      () => {
        const result = completeSpecialProject(
          contentDatabase(),
          saveFor(entry.save),
          entry.projectId,
          entry.quantity,
          entry.target,
          NOW_MS,
        )
        return (result.ok
          ? {
              ok: true,
              save: asJson(result.save),
              outputLabel: result.outputLabel,
              outputQty: result.outputQty,
              xpGained: result.xpGained,
              goldSpent: result.goldSpent,
            }
          : result) as unknown as JsonValue
      },
    ),
  ),

  ...(['base', 'forge', 'arcana'] as const).map((kind) =>
    scenario('projects/menu', kind, withSave(kind, { stations: MENU_STATIONS as JsonValue }), () => {
      const db = contentDatabase()
      const save = saveFor(kind)
      return {
        stations: MENU_STATIONS.map((station) => ({
          facilityId: station.facilityId,
          skillId: station.skillId,
          list: projectMenuList(db, save, station.facilityId, station.skillId),
          searched: projectMenuList(db, save, station.facilityId, station.skillId, station.query),
          defaultProjectId: defaultProjectId(db, save, station.facilityId, station.skillId),
        })),
        details: MENU_PROJECTS.map((projectId) => projectDetail(db, save, projectId)),
      } as unknown as JsonValue
    }),
  ),

  ...VALIDATE_CASES.map((entry) =>
    scenario(
      'projects/receipt',
      entry.name,
      withSave(entry.save, {
        projectId: entry.projectId,
        quantity: entry.quantity,
        target: entry.target ?? null,
        nowMs: NOW_MS,
      }),
      () => {
        const result = completeSpecialProject(
          contentDatabase(),
          saveFor(entry.save),
          entry.projectId,
          entry.quantity,
          entry.target,
          NOW_MS,
        )
        if (!result.ok) return { ok: false, reason: result.reason } as unknown as JsonValue
        return {
          ok: true,
          receipt: describeProjectCompletion(
            contentDatabase(),
            entry.projectId,
            entry.quantity,
            result,
          ),
        } as unknown as JsonValue
      },
    ),
  ),

  scenario(
    'npcs/knowledge',
    'lookups',
    withSave('forge', { locations: NPC_LOCATIONS, npcIds: UNLOCK_NPCS }),
    () => {
      const db = contentDatabase()
      const save = saveFor('forge')
      return {
        byLocation: NPC_LOCATIONS.map((locationId) => ({
          locationId,
          npcIds: npcsAtLocation(db, locationId, NOW_MS).map((npc) => npc['NPC ID']),
          shopIds: npcsAtLocation(db, locationId, NOW_MS).map((npc) => shopIdForMerchant(db, npc)),
        })),
        mentorForSkill: KNOWLEDGE_SKILLS.map((skillId) => knowledgeNpcForSkill(skillId)),
        knows: UNLOCK_NPCS.map((npcId) => hasNpcKnowledge(save, npcId)),
        projectKnowledge: KNOWLEDGE_SKILLS.map((skillId) =>
          hasProjectKnowledge(db, save, skillId),
        ),
      } as unknown as JsonValue
    },
  ),

  scenario('npcs/knowledge', 'unlock', withSave('base', { npcIds: UNLOCK_NPCS }), () => {
    const base = saveFor('base')
    return {
      results: UNLOCK_NPCS.map((npcId) => {
        const first = unlockNpcKnowledge(base, npcId)
        if (!first.ok) return { npcId, ok: false, reason: first.reason }
        const again = unlockNpcKnowledge(first.save, npcId)
        return {
          npcId,
          ok: true,
          alreadyHad: first.alreadyHad,
          save: asJson(first.save),
          repeatAlreadyHad: again.ok ? again.alreadyHad : null,
        }
      }),
    } as unknown as JsonValue
  }),
]
