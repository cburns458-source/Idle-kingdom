import { eligiblePoolEntries } from '../activity/pools'
import {
  evaluateRequirement,
  isHardRequirement,
  requirementsForEntity,
} from '../activity/requirements'
import type { EquipmentRow, GameDatabase, RequirementRow } from '../data/types'
import type { PlayerSave } from '../save/types'
import { equipmentRequirementFailure, equipItemFromInventory, type EquipResult } from './loadout'

export interface AutoEquipProposal {
  activityId: string
  itemId: string
  itemName: string
  capabilities: string[]
  failureReason: string
}

function capabilityTags(effects: string | null | undefined): string[] {
  if (typeof effects !== 'string') return []
  return effects
    .split(';')
    .map((part) => part.trim().toLowerCase())
    .filter(Boolean)
}

function equipmentProvidesAll(equipment: EquipmentRow, needed: string[]): boolean {
  const tags = new Set(capabilityTags(equipment['Capabilities / Effects']))
  return needed.every((cap) => tags.has(cap))
}

function toolTierScore(equipment: EquipmentRow): number {
  const level = Number(equipment['Required Level'] ?? 0)
  const atr = Number(equipment['Action Time Reduction %'] ?? 0)
  return level * 1_000 + atr
}

/** Hard tool-capability requirements checked when starting an activity. */
export function toolCapabilitiesRequiredForActivity(
  db: GameDatabase,
  activityId: string,
): string[] {
  const needed = new Set<string>()
  for (const requirement of requirementsForEntity(db, 'Activity', activityId)) {
    if (!isHardRequirement(requirement)) continue
    if (requirement['Requirement Type'] !== 'Tool Capability') continue
    const cap = String(requirement['Reference ID / Value'] ?? '')
      .trim()
      .toLowerCase()
    if (cap) needed.add(cap)
  }

  const activity = db.Activities.find((row) => row['Activity ID'] === activityId)
  if (activity?.['Pool ID']) {
    for (const { action } of eligiblePoolEntries(db, activity['Pool ID'])) {
      for (const requirement of requirementsForEntity(db, 'Action', action['Action ID'])) {
        if (!isHardRequirement(requirement)) continue
        if (requirement['Requirement Type'] !== 'Tool Capability') continue
        const cap = String(requirement['Reference ID / Value'] ?? '')
          .trim()
          .toLowerCase()
        if (cap) needed.add(cap)
      }
    }
  }

  return [...needed]
}

function toolCapabilityRequirement(activityId: string, capability: string): RequirementRow {
  return {
    'Requirement ID': 'auto-equip',
    'Entity Type': 'Activity',
    'Entity ID': activityId,
    'Requirement Group': 'A',
    'Group Logic': 'AND',
    'Requirement Type': 'Tool Capability',
    'Reference ID / Value': capability,
    Operator: null,
    'Required Value': null,
    Status: 'Planned',
    Notes: null,
  }
}

export function missingToolCapabilities(
  db: GameDatabase,
  save: PlayerSave,
  activityId: string,
): string[] {
  return toolCapabilitiesRequiredForActivity(db, activityId).filter(
    (capability) =>
      !evaluateRequirement(db, save, toolCapabilityRequirement(activityId, capability)).met,
  )
}

/**
 * If activity start is blocked by missing tool capabilities and the bag has a
 * compatible item the player can equip, propose the highest-tier option.
 */
export function proposeAutoEquipForActivity(
  db: GameDatabase,
  save: PlayerSave,
  activityId: string,
  failureReason: string,
): AutoEquipProposal | null {
  const missing = missingToolCapabilities(db, save, activityId)
  if (missing.length === 0) return null

  let best: { itemId: string; itemName: string; score: number } | null = null

  for (const stack of save.inventory) {
    if (stack.quantity <= 0) continue
    const equipment = db.Equipment.find((row) => row['Item ID'] === stack.itemId)
    if (!equipment?.['Slot ID']) continue
    if (!equipmentProvidesAll(equipment, missing)) continue
    if (equipmentRequirementFailure(db, save, equipment)) continue

    const itemName =
      db.Items.find((item) => item['Item ID'] === stack.itemId)?.['Display Name'] ??
      stack.itemId
    const score = toolTierScore(equipment)
    if (!best || score > best.score || (score === best.score && itemName < best.itemName)) {
      best = { itemId: stack.itemId, itemName, score }
    }
  }

  if (!best) return null

  return {
    activityId,
    itemId: best.itemId,
    itemName: best.itemName,
    capabilities: missing,
    failureReason,
  }
}

/** What the prompt asks, once a proposal exists. */
export interface AutoEquipPromptView {
  title: string
  /** Why the activity refused to start. */
  reason: string
  /** `Equip a Bronze Axe (woodcutting) from your bag and start this activity?` */
  question: string
  cancelLabel: string
  confirmLabel: string
}

export function autoEquipPromptView(proposal: AutoEquipProposal): AutoEquipPromptView {
  const tools = proposal.capabilities.map((capability) => capability.replaceAll('_', ' ')).join(', ')
  return {
    title: 'Equip required tool?',
    reason: proposal.failureReason,
    question: `Equip ${proposal.itemName}${tools ? ` (${tools})` : ''} from your bag and start this activity?`,
    cancelLabel: 'Not now',
    confirmLabel: 'Equip & Start',
  }
}

export function applyAutoEquipProposal(
  db: GameDatabase,
  save: PlayerSave,
  proposal: AutoEquipProposal,
): EquipResult {
  return equipItemFromInventory(db, save, proposal.itemId)
}
