import type { ProjectRow } from '../data/projectTypes'
import type { GameDatabase } from '../data/types'
import { hasProjectKnowledge } from '../npcs/knowledge'
import { inventoryCount } from '../production/recipes'
import { listRecipeBookEntries, type RecipeBookEntry } from '../recipes/knowledge'
import type { PlayerSave } from '../save/types'
import { isSpellItem, spellTooltipLines } from '../spells/spells'
import { eligibleEnchantmentTargets, type EnchantTargetOption } from './enchantments'
import type { ProjectCompleteResult } from './engine'
import {
  getEnchantment,
  getProject,
  isEnchantmentOutput,
  maxProjectQuantity,
  meetsProjectKnowledge,
  meetsProjectSkills,
  projectInputsForSave,
  projectSkillRequirements,
  projectsForFacility,
  unmetProjectSkillRequirements,
} from './projects'

function skillName(db: GameDatabase, skillId: string): string {
  return db.Skills.find((skill) => skill['Skill ID'] === skillId)?.['Display Name'] ?? skillId
}

function itemName(db: GameDatabase, itemId: string): string | null {
  return db.Items.find((item) => item['Item ID'] === itemId)?.['Display Name'] ?? null
}

/** One row of a station's project list. */
export interface ProjectListItem {
  projectId: string
  /** What the project makes, at what level: `Bronze bar → Bronze Bar (Lv 1)`. */
  label: string
  locked: boolean
}

function listLabel(db: GameDatabase, project: ProjectRow): string {
  const outputId = project['Output Item / Target ID']
  const level = project['Required Skill 1 Level'] ?? 1
  if (isEnchantmentOutput(outputId)) return `${project['Display Name']} (Lv ${level})`
  return `${project['Display Name']} → ${itemName(db, outputId) ?? project['Display Name']} (Lv ${level})`
}

/** Whether [project] answers to [query], by its own name or by what it makes. */
export function projectMatchesQuery(db: GameDatabase, project: ProjectRow, query: string): boolean {
  const needle = query.trim().toLowerCase()
  if (!needle) return true
  const outputId = project['Output Item / Target ID']
  const candidates = [
    project['Display Name'],
    project['Internal Key'],
    itemName(db, outputId),
    getEnchantment(db, outputId)?.['Display Name'] ?? null,
  ]
  return candidates.some((value) => value?.toLowerCase().includes(needle) ?? false)
}

/**
 * Whether this project can be completed right now: level, mentor, materials,
 * gold, and (for an enchantment) a valid target.
 */
export function canMakeProject(db: GameDatabase, save: PlayerSave, project: ProjectRow): boolean {
  if (!meetsProjectSkills(save, project) || !meetsProjectKnowledge(db, save, project)) {
    return false
  }
  if (maxProjectQuantity(save, project) < 1) return false
  const outputId = project['Output Item / Target ID']
  if (!isEnchantmentOutput(outputId)) return true
  const enchantment = getEnchantment(db, outputId)
  return enchantment != null && eligibleEnchantmentTargets(db, save, enchantment).length > 0
}

/**
 * The projects a station offers, in menu order, narrowed by [query].
 *
 * Locked rows stay in the list: seeing what the next mentor or level unlocks is
 * the point of the book. The start dropdown uses [readyProjectMenuList].
 */
export function projectMenuList(
  db: GameDatabase,
  save: PlayerSave,
  facilityId: string,
  skillId: string,
  query = '',
): ProjectListItem[] {
  return projectsForFacility(db, facilityId, skillId)
    .filter((project) => projectMatchesQuery(db, project, query))
    .map((project) => ({
      projectId: project['Project ID'],
      label: listLabel(db, project),
      locked: !canMakeProject(db, save, project),
    }))
}

/** Projects this station can complete right now. */
export function readyProjectMenuList(
  db: GameDatabase,
  save: PlayerSave,
  facilityId: string,
  skillId: string,
  query = '',
): ProjectListItem[] {
  return projectMenuList(db, save, facilityId, skillId, query).filter((row) => !row.locked)
}

/** Every project at this station, including locked ones, as recipe-book rows. */
export function recipeBookForProjectStation(
  save: PlayerSave,
  db: GameDatabase,
  facilityId: string,
  skillId: string,
): RecipeBookEntry[] {
  const ids = new Set(
    projectsForFacility(db, facilityId, skillId).map((project) => project['Project ID']),
  )
  return listRecipeBookEntries(save, db).filter(
    (entry) => entry.kind === 'project' && ids.has(entry.id),
  )
}

/** The project a station opens on: the first one that can actually be made. */
export function defaultProjectId(
  db: GameDatabase,
  save: PlayerSave,
  facilityId: string,
  skillId: string,
): string | null {
  const projects = projectsForFacility(db, facilityId, skillId)
  const ready = projects.find((project) => canMakeProject(db, save, project))
  const unlocked = projects.find(
    (project) => meetsProjectSkills(save, project) && meetsProjectKnowledge(db, save, project),
  )
  return ready?.['Project ID'] ?? unlocked?.['Project ID'] ?? projects[0]?.['Project ID'] ?? null
}

export interface ProjectIngredientLine {
  itemId: string
  name: string
  need: number
  owned: number
}

/** Everything shown about the selected project, with no numbers left to derive. */
export interface ProjectDetail {
  projectId: string
  name: string
  /** Null for an enchantment, which is applied rather than handed over. */
  outputItemId: string | null
  outputName: string
  outputQuantity: number
  /** `Instant · 1,000 XP · 50 gold`. */
  summaryLine: string
  /** What an enchantment or a spell does, when the output has an effect. */
  effectLine: string | null
  /** `Smithing 10 · Artisanry 5`, or null when the project asks for no skills. */
  skillLine: string | null
  ingredients: ProjectIngredientLine[]
  goldCost: number
  goldOwned: number
  isEnchantment: boolean
  /** Null when the project can be made; otherwise why it cannot. */
  lockedReason: string | null
  maxQuantity: number
  /** Empty for anything but an enchantment. */
  enchantTargets: EnchantTargetOption[]
}

function summaryLine(project: ProjectRow): string {
  const parts = ['Instant', `${project['XP Reward'].toLocaleString()} XP`]
  if (project['Gold Cost'] > 0) parts.push(`${project['Gold Cost'].toLocaleString()} gold`)
  return parts.join(' · ')
}

function lockedReason(
  db: GameDatabase,
  save: PlayerSave,
  project: ProjectRow,
  skillId: string,
): string | null {
  const knowledge = hasProjectKnowledge(db, save, skillId)
  if (!knowledge.ok) {
    return `Locked — speak with the ${knowledge.npcName} to unlock ${skillName(db, skillId)} projects.`
  }
  if (meetsProjectSkills(save, project)) return null
  const unmet = unmetProjectSkillRequirements(db, save, project).map(
    (requirement) => `${requirement.skillName} ${requirement.level}`,
  )
  return unmet.length > 0 ? `Locked — needs ${unmet.join(', ')}.` : 'Locked.'
}

function effectLine(db: GameDatabase, project: ProjectRow): string | null {
  const outputId = project['Output Item / Target ID']
  if (isEnchantmentOutput(outputId)) return getEnchantment(db, outputId)?.Effect ?? null
  if (!isSpellItem(db, outputId)) return null
  const item = db.Items.find((row) => row['Item ID'] === outputId)
  // The last tooltip line says whether copies stack, which is what a buyer asks.
  return spellTooltipLines(db, item, outputId).slice(-1)[0] ?? null
}

export function projectDetail(
  db: GameDatabase,
  save: PlayerSave,
  projectId: string,
): ProjectDetail | null {
  const project = getProject(db, projectId)
  if (!project) return null
  const outputId = project['Output Item / Target ID']
  const enchantment = isEnchantmentOutput(outputId) ? getEnchantment(db, outputId) : undefined
  const skillId = project['Skill ID']
  const reason = lockedReason(db, save, project, skillId)
  const skills = projectSkillRequirements(project)

  return {
    projectId,
    name: project['Display Name'],
    outputItemId: enchantment ? null : outputId,
    outputName:
      (enchantment ? enchantment['Display Name'] : itemName(db, outputId)) ??
      project['Display Name'],
    outputQuantity: project['Output Quantity'],
    summaryLine: summaryLine(project),
    effectLine: effectLine(db, project),
    skillLine:
      skills.length === 0
        ? null
        : skills
            .map((requirement) => `${skillName(db, requirement.skillId)} ${requirement.level}`)
            .join(' · '),
    ingredients: projectInputsForSave(save, project).map((input) => ({
      itemId: input.itemId,
      name: itemName(db, input.itemId) ?? input.itemId,
      need: input.quantity,
      owned: inventoryCount(save, input.itemId),
    })),
    goldCost: project['Gold Cost'],
    goldOwned: save.gold,
    isEnchantment: enchantment !== undefined,
    lockedReason: reason,
    maxQuantity: reason === null ? maxProjectQuantity(save, project) : 0,
    enchantTargets: enchantment ? eligibleEnchantmentTargets(db, save, enchantment) : [],
  }
}

/** What a finished project is worth, as the popup and the message say it. */
export interface ProjectReceipt {
  projectName: string
  lines: string[]
  message: string
}

/**
 * Describes a completed project.
 *
 * [requestedQuantity] is what the player asked for, which can be more than one
 * craft's worth of output and is worth repeating back to them.
 */
export function describeProjectCompletion(
  db: GameDatabase,
  projectId: string,
  requestedQuantity: number,
  result: Extract<ProjectCompleteResult, { ok: true }>,
): ProjectReceipt {
  const lines = [
    result.outputQty > 1 ? `${result.outputLabel} ×${result.outputQty}` : result.outputLabel,
    result.xpGained > 0 ? `+${result.xpGained.toLocaleString()} XP` : null,
    result.goldSpent > 0 ? `Spent ${result.goldSpent.toLocaleString()} gold` : null,
    requestedQuantity > 1 ? `Crafted ${requestedQuantity} times` : null,
  ].filter((line): line is string => line !== null)

  return {
    projectName: getProject(db, projectId)?.['Display Name'] ?? result.outputLabel,
    lines,
    message: [
      `Completed ${result.outputLabel}`,
      result.outputQty > 1 ? `×${result.outputQty}` : null,
      result.xpGained > 0 ? `+${result.xpGained.toLocaleString()} XP` : null,
      result.goldSpent > 0 ? `-${result.goldSpent} gold` : null,
    ]
      .filter((part) => part !== null)
      .join(' · '),
  }
}
