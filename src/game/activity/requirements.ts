import type { GameDatabase, RequirementRow } from '../data/types'
import type { PlayerSave } from '../save/types'
import { getSkillProgress } from './xp'

function equippedCapabilityTags(db: GameDatabase, save: PlayerSave): Set<string> {
  const tags = new Set<string>()
  for (const itemId of Object.values(save.equipment.slots)) {
    if (!itemId) continue
    const equipment = db.Equipment.find((row) => row['Item ID'] === itemId)
    const caps = equipment?.['Capabilities / Effects']
    if (typeof caps !== 'string') continue
    for (const part of caps.split(';')) {
      const tag = part.trim().toLowerCase()
      if (tag) tags.add(tag)
    }
  }
  return tags
}

/** Soft proficiency markers are not hard gates for Gathering. */
export function isHardRequirement(requirement: RequirementRow): boolean {
  if (requirement['Requirement Type'] === 'Tool Capability') return true
  if (requirement['Requirement Type'] === 'Station') return true
  if (requirement['Requirement Type'] === 'Skill Level') {
    const operator = (requirement.Operator ?? '').toLowerCase()
    if (operator === 'proficiency') return false
    return true
  }
  return true
}

export function requirementsForEntity(
  db: GameDatabase,
  entityType: string,
  entityId: string,
): RequirementRow[] {
  return db.Requirements.filter(
    (row) => row['Entity Type'] === entityType && row['Entity ID'] === entityId,
  )
}

export function evaluateRequirement(
  db: GameDatabase,
  save: PlayerSave,
  requirement: RequirementRow,
): { met: boolean; detail: string } {
  const type = requirement['Requirement Type']
  const reference = String(requirement['Reference ID / Value'] ?? '')

  if (type === 'Tool Capability') {
    const tags = equippedCapabilityTags(db, save)
    const met = tags.has(reference.toLowerCase())
    return {
      met,
      detail: met ? `Has ${reference}` : `Requires equipped ${reference.replaceAll('_', ' ')}`,
    }
  }

  if (type === 'Station') {
    const facility = db.Facilities.find((row) => row['Facility ID'] === reference)
    const atLocation = facility?.['Location ID'] === save.currentLocationId
    return {
      met: Boolean(facility && atLocation),
      detail: atLocation
        ? `At ${facility?.['Display Name'] ?? 'station'}`
        : `Requires ${facility?.['Display Name'] ?? 'station'} at this location`,
    }
  }

  if (type === 'Skill Level') {
    const skill = getSkillProgress(save, reference)
    const required = Number(requirement['Required Value'] ?? 1)
    const operator = (requirement.Operator ?? '>=').toLowerCase()
    if (operator === 'proficiency') {
      // Soft gate — always "met" for start validation; duration handles penalty.
      return {
        met: true,
        detail:
          skill.level >= required
            ? `Proficiency ${required}`
            : `Below proficiency ${required} (slower)`,
      }
    }
    const met = skill.level >= required
    return {
      met,
      detail: met
        ? `Level ${skill.level}`
        : `Requires ${reference} level ${required}`,
    }
  }

  return { met: true, detail: 'OK' }
}

export function unmetHardRequirements(
  db: GameDatabase,
  save: PlayerSave,
  requirements: RequirementRow[],
): string[] {
  const failures: string[] = []
  for (const requirement of requirements) {
    if (!isHardRequirement(requirement)) continue
    const result = evaluateRequirement(db, save, requirement)
    if (!result.met) failures.push(result.detail)
  }
  return failures
}
