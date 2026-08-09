import { getSkillProgress } from '../activity/xp'
import type { EnchantmentRow, ProjectRow } from '../data/projectTypes'
import type { FacilityRow, GameDatabase } from '../data/types'
import { hasProjectKnowledge } from '../npcs/knowledge'
import { inventoryCount } from '../production/recipes'
import type { PlayerSave } from '../save/types'

export interface ProjectInput {
  itemId: string
  quantity: number
}

export interface SpecialProductionStation {
  facility: FacilityRow
  skillId: string
  skillName: string
  label: string
}

export function isCompleteProject(project: ProjectRow): boolean {
  if (project.Status === 'Needs Data') return false
  if (project.Instant !== 'Yes') return false
  if (typeof project['XP Reward'] !== 'number') return false
  if (typeof project['Output Quantity'] !== 'number') return false
  if (!project['Output Item / Target ID'] || !project['Facility ID'] || !project['Skill ID']) {
    return false
  }
  if (typeof project['Gold Cost'] !== 'number') return false
  return true
}

export function projectInputs(project: ProjectRow): ProjectInput[] {
  const out: ProjectInput[] = []
  const pairs: Array<[string | null, number | null]> = [
    [project['Input 1 Item ID'], project['Input 1 Quantity']],
    [project['Input 2 Item ID'], project['Input 2 Quantity']],
    [project['Input 3 Item ID'], project['Input 3 Quantity']],
    [project['Input 4 Item ID'], project['Input 4 Quantity']],
  ]
  for (const [itemId, quantity] of pairs) {
    if (itemId && typeof quantity === 'number' && quantity > 0) {
      out.push({ itemId, quantity })
    }
  }
  return out
}

export function projectSkillRequirements(
  project: ProjectRow,
): Array<{ skillId: string; level: number }> {
  const out: Array<{ skillId: string; level: number }> = []
  const pairs: Array<[string | null, number | null]> = [
    [project['Required Skill 1 ID'], project['Required Skill 1 Level']],
    [project['Required Skill 2 ID'], project['Required Skill 2 Level']],
    [project['Required Skill 3 ID'], project['Required Skill 3 Level']],
  ]
  for (const [skillId, level] of pairs) {
    if (skillId && typeof level === 'number') {
      out.push({ skillId, level })
    }
  }
  return out
}

export function getProject(db: GameDatabase, projectId: string): ProjectRow | undefined {
  return db.Projects.find((project) => project['Project ID'] === projectId)
}

export function getEnchantment(db: GameDatabase, enchantmentId: string): EnchantmentRow | undefined {
  return db.Enchantments.find((row) => row['Enchantment ID'] === enchantmentId)
}

export function isEnchantmentOutput(outputId: string): boolean {
  return outputId.startsWith('ENCH-')
}

export function meetsProjectSkills(save: PlayerSave, project: ProjectRow): boolean {
  return projectSkillRequirements(project).every(
    (requirement) => getSkillProgress(save, requirement.skillId).level >= requirement.level,
  )
}

export function meetsProjectKnowledge(
  db: GameDatabase,
  save: PlayerSave,
  project: ProjectRow,
): boolean {
  return hasProjectKnowledge(db, save, project['Skill ID']).ok
}

export function unmetProjectSkillRequirements(
  db: GameDatabase,
  save: PlayerSave,
  project: ProjectRow,
): Array<{ skillId: string; skillName: string; level: number; have: number }> {
  return projectSkillRequirements(project)
    .map((requirement) => {
      const have = getSkillProgress(save, requirement.skillId).level
      return {
        skillId: requirement.skillId,
        skillName:
          db.Skills.find((skill) => skill['Skill ID'] === requirement.skillId)?.['Display Name'] ??
          requirement.skillId,
        level: requirement.level,
        have,
      }
    })
    .filter((requirement) => requirement.have < requirement.level)
}

export function maxProjectsFromMaterials(save: PlayerSave, project: ProjectRow): number {
  const inputs = projectInputs(project)
  if (inputs.length === 0) return Number.POSITIVE_INFINITY
  let max = Number.POSITIVE_INFINITY
  for (const input of inputs) {
    max = Math.min(max, Math.floor(inventoryCount(save, input.itemId) / input.quantity))
  }
  return Number.isFinite(max) ? Math.max(0, max) : 0
}

export function maxProjectsFromGold(save: PlayerSave, project: ProjectRow): number {
  const cost = project['Gold Cost']
  if (cost <= 0) return Number.POSITIVE_INFINITY
  return Math.floor(save.gold / cost)
}

export function maxProjectQuantity(save: PlayerSave, project: ProjectRow): number {
  const materialMax = maxProjectsFromMaterials(save, project)
  const goldMax = maxProjectsFromGold(save, project)
  if (!Number.isFinite(materialMax) && !Number.isFinite(goldMax)) return 1
  return Math.max(0, Math.min(materialMax, goldMax))
}

/** Launch projects at a facility (skill gates affect completion, not listing). */
export function projectsForFacility(
  db: GameDatabase,
  facilityId: string,
  skillId?: string,
): ProjectRow[] {
  return db.Projects.filter(
    (project) =>
      isCompleteProject(project) &&
      project['Facility ID'] === facilityId &&
      (!skillId || project['Skill ID'] === skillId),
  ).sort((a, b) => {
    const aLevel = a['Required Skill 1 Level'] ?? 0
    const bLevel = b['Required Skill 1 Level'] ?? 0
    return aLevel - bLevel || a['Display Name'].localeCompare(b['Display Name'])
  })
}

/**
 * Special Production stations at a location, derived from Facilities + Projects.
 * Instant projects do not use the Primary Activity slot.
 */
export function specialProductionStationsAt(
  db: GameDatabase,
  locationId: string,
): SpecialProductionStation[] {
  const facilities = db.Facilities.filter(
    (facility) =>
      facility['Location ID'] === locationId &&
      facility.Status !== 'Needs Data' &&
      facility['Facility Type'] === 'Special Production Station',
  )

  const stations: SpecialProductionStation[] = []
  for (const facility of facilities) {
    const skillIds = new Set(
      db.Projects.filter(
        (project) =>
          isCompleteProject(project) && project['Facility ID'] === facility['Facility ID'],
      ).map((project) => project['Skill ID']),
    )
    for (const skillId of skillIds) {
      const skillName =
        db.Skills.find((skill) => skill['Skill ID'] === skillId)?.['Display Name'] ?? skillId
      stations.push({
        facility,
        skillId,
        skillName,
        label: skillName,
      })
    }
  }

  // Artisanry uses the Crafting Workshop facility (not typed as Special Production Station).
  const workshopProjects = db.Projects.filter(
    (project) =>
      isCompleteProject(project) &&
      project['Skill ID'] === 'SKL-0012' &&
      db.Facilities.some(
        (facility) =>
          facility['Facility ID'] === project['Facility ID'] &&
          facility['Location ID'] === locationId,
      ),
  )
  for (const project of workshopProjects) {
    const facility = db.Facilities.find((row) => row['Facility ID'] === project['Facility ID'])
    if (!facility) continue
    if (stations.some((station) => station.facility['Facility ID'] === facility['Facility ID'] && station.skillId === 'SKL-0012')) {
      continue
    }
    stations.push({
      facility,
      skillId: 'SKL-0012',
      skillName: 'Artisanry',
      label: 'Artisanry',
    })
  }

  return stations.sort((a, b) => a.label.localeCompare(b.label))
}
