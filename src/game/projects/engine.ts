import { addItemToInventoryExact } from '../activity/rewards'
import { applyXp } from '../activity/xp'
import type { GameDatabase } from '../data/types'
import { removeIngredients } from '../production/inventory'
import { applyRaceSkillXp } from '../races/races'
import type { PlayerSave } from '../save/types'
import {
  applyEnchantmentToTarget,
  decodeEnchantTarget,
  eligibleEnchantmentTargets,
} from './enchantments'
import { hasProjectKnowledge } from '../npcs/knowledge'
import { applyBountyProjectProgress } from '../bounties/progress'
import { projectFacilityIdForLookup } from '../production/recipes'
import { applyQuestProcessProgress } from '../quests/progress'
import {
  getEnchantment,
  getProject,
  isCompleteProject,
  isEnchantmentOutput,
  maxProjectQuantity,
  meetsProjectKnowledge,
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
  enchantTargetId?: string | null,
): { ok: true } | { ok: false; reason: string } {
  const project = getProject(db, projectId)
  if (!project || !isCompleteProject(project)) {
    return { ok: false, reason: 'That project is not available.' }
  }

  const atLocation = db.Facilities.some(
    (row) =>
      row['Location ID'] === save.currentLocationId &&
      projectFacilityIdForLookup(row['Facility ID']) === project['Facility ID'],
  )
  if (!atLocation) {
    return { ok: false, reason: 'Travel to the required facility first.' }
  }

  if (!meetsProjectKnowledge(db, save, project)) {
    const knowledge = hasProjectKnowledge(db, save, project['Skill ID'])
    if (!knowledge.ok) {
      return {
        ok: false,
        reason: `Speak with the ${knowledge.npcName} to unlock these projects.`,
      }
    }
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
    const targets = eligibleEnchantmentTargets(db, save, enchantment)
    if (targets.length === 0) {
      return {
        ok: false,
        reason: 'Select a valid equipped or inventory item to enchant.',
      }
    }
    if (!enchantTargetId || !targets.some((target) => target.id === enchantTargetId)) {
      return { ok: false, reason: 'Choose a valid item to enchant.' }
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
  enchantTargetId?: string | null,
  nowMs: number = Date.now(),
): ProjectCompleteResult {
  const validation = validateProjectCompletion(
    db,
    save,
    projectId,
    quantity,
    enchantTargetId,
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
    const target = decodeEnchantTarget(enchantTargetId)
    if (!target) return { ok: false, reason: 'Choose a valid item to enchant.' }

    // Inventory indexes can shift when materials are removed; re-resolve by item id.
    let resolved = target
    if (target.kind === 'inventory') {
      const prior = save.inventory[target.index]
      if (!prior || prior.enchantmentId) {
        return { ok: false, reason: 'Choose a valid item to enchant.' }
      }
      const refreshed = next.inventory.findIndex(
        (stack) => stack.itemId === prior.itemId && !stack.enchantmentId,
      )
      if (refreshed < 0) {
        return { ok: false, reason: 'Choose a valid item to enchant.' }
      }
      resolved = { kind: 'inventory', index: refreshed }
    }

    const enchanted = applyEnchantmentToTarget(next, resolved, outputId)
    if (!enchanted) return { ok: false, reason: 'Could not apply the enchantment.' }
    next = enchanted
  } else {
    const granted = addItemToInventoryExact(next, outputId, outputQty)
    if (!granted.ok) return granted
    next = granted.save
    outputLabel =
      db.Items.find((item) => item['Item ID'] === outputId)?.['Display Name'] ?? outputLabel
  }

  const xpTotal = applyRaceSkillXp(db, save, project['Skill ID'], project['XP Reward'] * crafts)
  const xpApplied = applyXp(next, db, project['Skill ID'], xpTotal)
  next = xpApplied.save
  next = applyQuestProcessProgress(db, next, project['Project ID'], crafts)
  next = applyBountyProjectProgress(next, project['Project ID'], crafts, nowMs)

  return {
    ok: true,
    save: next,
    outputLabel,
    outputQty: isEnchantmentOutput(outputId) ? 1 : outputQty,
    xpGained: xpTotal,
    goldSpent: goldCost,
  }
}
