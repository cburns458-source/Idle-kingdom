import type { GameDatabase, RequirementRow } from '../data/types'
import { inventoryCount } from '../production/recipes'
import {
  hasQuestFlag,
  questIsActive,
  questIsActiveOrComplete,
  questIsComplete,
} from '../quests/progress'
import type { PlayerSave } from '../save/types'
import { getSkillProgress } from './xp'

/** Requirement types the runtime knows how to evaluate. Unknown types fail closed. */
export const KNOWN_REQUIREMENT_TYPES = [
  'Tool Capability',
  'Empty Slot',
  'Station',
  'Skill Level',
  'Quest Access',
  'Quest Active',
  'Quest Complete',
  'Quest Flag',
  'Item Absent',
] as const

export type KnownRequirementType = (typeof KNOWN_REQUIREMENT_TYPES)[number]

export function isKnownRequirementType(type: string): type is KnownRequirementType {
  return (KNOWN_REQUIREMENT_TYPES as readonly string[]).includes(type)
}

function equippedCapabilityTags(db: GameDatabase, save: PlayerSave): Set<string> {
  const tags = new Set<string>()
  for (const stack of Object.values(save.equipment.slots)) {
    if (!stack?.itemId) continue
    const equipment = db.Equipment.find((row) => row['Item ID'] === stack.itemId)
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

  if (type === 'Empty Slot') {
    const stack = save.equipment.slots[reference]
    const empty = !stack?.itemId || stack.quantity <= 0
    const slotName = db.EquipmentSlots.find((row) => row['Slot ID'] === reference)?.['Display Name']
    const name = slotName || reference
    return {
      met: empty,
      detail: empty ? `No ${name} equipped` : `Requires no equipped ${name}`,
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

  if (type === 'Quest Access') {
    const met = questIsActiveOrComplete(save, reference)
    return {
      met,
      detail: met ? 'Quest unlocked' : 'Requires completing or starting that quest',
    }
  }

  if (type === 'Quest Active') {
    const met = questIsActive(save, reference)
    return {
      met,
      detail: met ? 'Quest in progress' : 'Not available yet',
    }
  }

  if (type === 'Quest Complete') {
    const met = questIsComplete(save, reference)
    return {
      met,
      detail: met ? 'Quest complete' : 'Requires completing that quest',
    }
  }

  if (type === 'Quest Flag') {
    const parts = reference.split(':')
    if (parts.length < 2) {
      return { met: false, detail: 'Quest flag is incomplete.' }
    }
    const questId = parts[0]!
    const key = parts.slice(1).join(':')
    const met = hasQuestFlag(save, questId, key)
    return { met, detail: met ? 'Quest flag set' : 'Not available yet' }
  }

  if (type === 'Item Absent') {
    const met = inventoryCount(save, reference) <= 0
    return {
      met,
      detail: met ? 'Item not held' : 'Already have that item',
    }
  }

  return { met: false, detail: 'Unknown requirement.' }
}

function isQuestGateRequirement(type: string): boolean {
  return (
    type === 'Quest Access' ||
    type === 'Quest Flag' ||
    type === 'Quest Active' ||
    type === 'Quest Complete' ||
    type === 'Item Absent'
  )
}

/** Hide gated activities until their quest flag, access, or item condition is met. */
export function activityVisibleForSave(
  db: GameDatabase,
  save: PlayerSave,
  activityId: string,
): boolean {
  return entityVisibleForSave(db, save, 'Activity', activityId)
}

export function entityVisibleForSave(
  db: GameDatabase,
  save: PlayerSave,
  entityType: string,
  entityId: string,
): boolean {
  for (const requirement of requirementsForEntity(db, entityType, entityId)) {
    if (!isQuestGateRequirement(requirement['Requirement Type'])) continue
    if (!evaluateRequirement(db, save, requirement).met) return false
  }
  return true
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
