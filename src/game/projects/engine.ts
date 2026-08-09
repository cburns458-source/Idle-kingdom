import { addItemToInventory } from '../activity/rewards'
import { applyXp } from '../activity/xp'
import type { GameDatabase } from '../data/types'
import { removeIngredients } from '../production/inventory'
import type { PlayerSave } from '../save/types'
import {
  applyEnchantmentToSlot,
  eligibleEnchantmentSlots,
} from './enchantments'
import {
  getEnchantment,
  getProject,
  isCompleteProject,
  isEnchantmentOutput,
  maxProjectQuantity,
  meetsProjectSkills,
  projectInputs,
  projectSkillRequirements,
} from './projects'

export type ProjectCompleteResult =
  | {
      ok: true
      save: PlayerSave
      outputLabel: string
      outputQty: number
      xpGained: number
      goldSpent: number
    }
  | { ok: false; reason: string }

export function validateProjectCompletion(
  db: GameDatabase,
  save: PlayerSave,
  projectId: string,
  quantity: number,
  enchantTargetSlotId?: string | null,
): { ok: true } | { ok: false; reason: string } {
  const project = getProject(db, projectId)
  if (!project || !isCompleteProject(project)) {
    return { ok: false, reason: 'That project is not available.' }
  }

  const facility = db.Facilities.find((row) => row['Facility ID'] === project['Facility ID'])
  if (!facility || facility['Location ID'] !== save.currentLocationId) {
    return { ok: false, reason: 'Travel to the required facility first.' }
  }

  if (!meetsProjectSkills(save, project)) {
    const missing = projectSkillRequirements(project).find(
      (requirement) =>
        (save.skills.find((skill) => skill.skillId === requirement.skillId)?.level ?? 1) <
        requirement.level,
    )
    const skillName = missing
      ? (db.Skills.find((skill) => skill['Skill ID'] === missing.skillId)?.['Display Name'] ??
        missing.skillId)
      : 'skill'
    return {
      ok: false,
      reason: missing
        ? `Requires ${skillName} level ${missing.level}.`
        : 'Skill requirements are not met.',
    }
  }

  const crafts = Math.floor(quantity)
  if (crafts <= 0) return { ok: false, reason: 'Choose a quantity of at least 1.' }
  if (crafts > maxProjectQuantity(save, project)) {
    return { ok: false, reason: 'Missing materials or gold for that quantity.' }
  }

  const outputId = project['Output Item / Target ID']
  if (isEnchantmentOutput(outputId)) {
    const enchantment = getEnchantment(db, outputId)
    if (!enchantment || enchantment.Status === 'Needs Data') {
      return { ok: false, reason: 'That enchantment is not ready yet.' }
    }
    if (crafts !== 1) {
      return { ok: false, reason: 'Enchantment projects complete one at a time.' }
    }
    const slots = eligibleEnchantmentSlots(db, save, enchantment)
    if (slots.length === 0) {
      return {
        ok: false,
        reason: 'Equip a valid item before applying this enchantment.',
      }
    }
    if (!enchantTargetSlotId || !slots.some((slot) => slot.slotId === enchantTargetSlotId)) {
      return { ok: false, reason: 'Choose a valid equipped item to enchant.' }
    }
  } else {
    const item = db.Items.find((row) => row['Item ID'] === outputId)
    if (!item) return { ok: false, reason: 'Project output item is missing from data.' }
  }

  return { ok: true }
}

/** Instantly complete one or more Special Production projects. */
export function completeSpecialProject(
  db: GameDatabase,
  save: PlayerSave,
  projectId: string,
  quantity: number,
  enchantTargetSlotId?: string | null,
): ProjectCompleteResult {
  const validation = validateProjectCompletion(
    db,
    save,
    projectId,
    quantity,
    enchantTargetSlotId,
  )
  if (!validation.ok) return validation

  const project = getProject(db, projectId)!
  const crafts = Math.floor(quantity)
  const inputs = projectInputs(project)
  const withMaterials = removeIngredients(save, inputs, crafts)
  if (!withMaterials) {
    return { ok: false, reason: 'Missing required materials.' }
  }

  const goldCost = project['Gold Cost'] * crafts
  if (withMaterials.gold < goldCost) {
    return { ok: false, reason: 'Not enough gold.' }
  }

  let next: PlayerSave = { ...withMaterials, gold: withMaterials.gold - goldCost }
  const outputId = project['Output Item / Target ID']
  const outputQty = project['Output Quantity'] * crafts
  let outputLabel = project['Display Name']

  if (isEnchantmentOutput(outputId)) {
    const enchantment = getEnchantment(db, outputId)!
    outputLabel = enchantment['Display Name']
    const enchanted = applyEnchantmentToSlot(next, enchantTargetSlotId!, outputId)
    if (!enchanted) return { ok: false, reason: 'Could not apply the enchantment.' }
    next = enchanted
  } else {
    next = addItemToInventory(next, outputId, outputQty)
    outputLabel =
      db.Items.find((item) => item['Item ID'] === outputId)?.['Display Name'] ?? outputLabel
  }

  const xpTotal = project['XP Reward'] * crafts
  const xpApplied = applyXp(next, db, project['Skill ID'], xpTotal)
  next = xpApplied.save

  return {
    ok: true,
    save: next,
    outputLabel,
    outputQty: isEnchantmentOutput(outputId) ? 1 : outputQty,
    xpGained: xpTotal,
    goldSpent: goldCost,
  }
}
