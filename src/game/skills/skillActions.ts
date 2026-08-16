import type { ProjectRow } from '../data/projectTypes'
import type { ActionRow, GameDatabase } from '../data/types'
import { SMITHING_SKILL_ID } from '../npcs/knowledge'
import {
  getEnchantment,
  isCompleteProject,
  isEnchantmentOutput,
  projectSkillRequirements,
} from '../projects/projects'

export interface SkillMenuListItem {
  id: string
  displayName: string
  level: number | null
}

/** Actions for a skill menu: display names only, unique by name, proficiency when set. */
export function actionsForSkill(db: GameDatabase, skillId: string): SkillMenuListItem[] {
  const rows = db.Actions.filter(
    (action) =>
      action['Relevant Skill ID'] === skillId &&
      action.Status !== 'Needs Data' &&
      Boolean(action['Display Name']?.trim()),
  )

  rows.sort(compareSkillActions)

  const seen = new Set<string>()
  const items: SkillMenuListItem[] = []
  for (const action of rows) {
    const displayName = action['Display Name']!.trim()
    if (seen.has(displayName)) continue
    seen.add(displayName)
    const proficiency = action['Proficiency Level']
    items.push({
      id: action['Action ID'],
      displayName,
      level: typeof proficiency === 'number' ? proficiency : null,
    })
  }
  return items
}

/** Projects for smithing / artisanry / arcana: resulting item name + required level. */
export function projectsForSkill(db: GameDatabase, skillId: string): SkillMenuListItem[] {
  const rows = db.Projects.filter(
    (project) => project['Skill ID'] === skillId && isCompleteProject(project),
  )

  rows.sort((a, b) => {
    const aLevel = projectLevelForSkill(a, skillId) ?? Number.POSITIVE_INFINITY
    const bLevel = projectLevelForSkill(b, skillId) ?? Number.POSITIVE_INFINITY
    if (aLevel !== bLevel) return aLevel - bLevel
    return projectOutputName(db, a).localeCompare(projectOutputName(db, b))
  })

  const seen = new Set<string>()
  const items: SkillMenuListItem[] = []
  for (const project of rows) {
    const displayName = projectOutputName(db, project)
    if (!displayName || seen.has(displayName)) continue
    seen.add(displayName)
    items.push({
      id: project['Project ID'],
      displayName,
      level: projectLevelForSkill(project, skillId),
    })
  }
  return items
}

/** Combined skill menu rows: actions first, then projects. */
export function skillMenuEntries(db: GameDatabase, skillId: string): SkillMenuListItem[] {
  return [...actionsForSkill(db, skillId), ...projectsForSkill(db, skillId)]
}

/** `{level}. {name}` for a skill-menu row. */
export function skillMenuLine(item: SkillMenuListItem): string {
  if (item.level == null) return item.displayName
  const number = Number.isInteger(item.level) ? item.level : item.level
  return `${number}. ${item.displayName}`
}

/** Rows shown on a skill tile: smithing is grouped by material, others are listed. */
export function skillMenuDisplayEntries(db: GameDatabase, skillId: string): SkillMenuListItem[] {
  if (skillId !== SMITHING_SKILL_ID) return skillMenuEntries(db, skillId)
  const items: SkillMenuListItem[] = [...actionsForSkill(db, skillId)]
  const seen = new Set<string>()
  for (const project of projectsForSkill(db, skillId)) {
    const material = smithingMaterial(project.displayName)
    if (!material) {
      items.push(project)
      continue
    }
    const key = `${project.level ?? ''}|${material}`
    if (seen.has(key)) continue
    seen.add(key)
    items.push({
      id: key,
      displayName: `${material} items`,
      level: project.level,
    })
  }
  return items
}

function smithingMaterial(name: string): string | null {
  const parts = name.trim().split(/\s+/)
  if (parts.length < 2) return null
  return parts[0] ?? null
}

export function projectOutputName(db: GameDatabase, project: ProjectRow): string {
  const outputId = project['Output Item / Target ID']
  if (!outputId) return project['Display Name']
  if (isEnchantmentOutput(outputId)) {
    return getEnchantment(db, outputId)?.['Display Name'] ?? project['Display Name']
  }
  return (
    db.Items.find((item) => item['Item ID'] === outputId)?.['Display Name'] ??
    project['Display Name']
  )
}

function projectLevelForSkill(project: ProjectRow, skillId: string): number | null {
  const match = projectSkillRequirements(project).find((requirement) => requirement.skillId === skillId)
  return match?.level ?? null
}

function compareSkillActions(a: ActionRow, b: ActionRow): number {
  const aProf =
    typeof a['Proficiency Level'] === 'number' ? a['Proficiency Level'] : Number.POSITIVE_INFINITY
  const bProf =
    typeof b['Proficiency Level'] === 'number' ? b['Proficiency Level'] : Number.POSITIVE_INFINITY
  if (aProf !== bProf) return aProf - bProf
  return a['Display Name'].localeCompare(b['Display Name'])
}

/** @deprecated Use SkillMenuListItem */
export type SkillActionListItem = SkillMenuListItem
