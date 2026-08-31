import { capabilityTags } from '../potions/effects'
import type { GameDatabase } from '../data/types'
import type { PlayerSave } from '../save/types'

/** Sum every `+N% relative Drop Chance` tag in a capability string. */
export function parseRelativeDropChanceBonusPercent(
  effects: string | null | undefined,
): number {
  let total = 0
  for (const tag of capabilityTags(effects)) {
    const match = tag.match(/^\+(\d+(?:\.\d+)?)%\s+relative\s+drop\s+chance$/)
    if (match) total += Number(match[1])
  }
  return total
}

const SKILL_RELATIVE_DROP_CHANCE_TAG =
  /^\+(\d+(?:\.\d+)?)%\s+relative\s+(.+?)\s+drop\s+chance$/

/** Sum `+N% relative <skill> drop chance` tags that match this skill name. */
export function parseSkillRelativeDropChanceBonusPercent(
  effects: string | null | undefined,
  skillName: string | null | undefined,
): number {
  if (!skillName) return 0
  const needle = skillName.trim().toLowerCase()
  if (!needle) return 0
  let total = 0
  for (const tag of capabilityTags(effects)) {
    const match = tag.match(SKILL_RELATIVE_DROP_CHANCE_TAG)
    if (!match) continue
    if (match[2] === needle) total += Number(match[1])
  }
  return total
}

export function skillRelativeDropChanceTooltipLines(
  effects: string | null | undefined,
): string[] {
  const lines: string[] = []
  for (const tag of capabilityTags(effects)) {
    const match = tag.match(SKILL_RELATIVE_DROP_CHANCE_TAG)
    if (!match) continue
    const labeled = match[2]!.replace(/\b\w/g, (ch) => ch.toUpperCase())
    lines.push(`+${match[1]}% relative ${labeled} Drop Chance`)
  }
  return lines
}

function skillDisplayNameForId(db: GameDatabase, skillId: string | null | undefined): string | null {
  if (!skillId) return null
  const name = db.Skills.find((skill) => skill['Skill ID'] === skillId)?.['Display Name']
  return typeof name === 'string' && name.length > 0 ? name : null
}

/** Skill-gated gear bonuses (Scythe). Same bonus types add. */
export function equippedSkillRelativeDropChanceBonusPercent(
  db: GameDatabase,
  save: PlayerSave,
  skillId: string | null | undefined,
): number {
  const skillName = skillDisplayNameForId(db, skillId)
  if (!skillName) return 0
  let total = 0
  for (const stack of Object.values(save.equipment.slots)) {
    if (!stack?.itemId) continue
    const equipment = db.Equipment.find((row) => row['Item ID'] === stack.itemId)
    total += parseSkillRelativeDropChanceBonusPercent(
      equipment?.['Capabilities / Effects'],
      skillName,
    )
  }
  return total
}

/** Equipped gear bonuses (Lucky Necklace, future luck items). Same bonus types add. */
export function equippedRelativeDropChanceBonusPercent(
  db: GameDatabase,
  save: PlayerSave,
): number {
  let total = 0
  for (const stack of Object.values(save.equipment.slots)) {
    if (!stack?.itemId) continue
    const equipment = db.Equipment.find((row) => row['Item ID'] === stack.itemId)
    total += parseRelativeDropChanceBonusPercent(equipment?.['Capabilities / Effects'])
  }
  return total
}

/**
 * Total relative drop-chance bonus from all sources (gear + active luck potion).
 * Same bonus types stack by addition.
 */
export function totalRelativeDropChanceBonusPercent(
  db: GameDatabase,
  save: PlayerSave,
): number {
  let total = equippedRelativeDropChanceBonusPercent(db, save)
  if (save.activePotionEffect?.scope === 'one_action') {
    total += save.activePotionEffect.relativeDropChanceBonusPercent ?? 0
  }
  return total
}

/** Apply a summed relative drop-chance bonus: base × (1 + bonus/100), capped at 100. */
export function applyRelativeDropChance(
  baseChance: number | null,
  relativeBonusPercent: number,
): number | null {
  if (typeof baseChance !== 'number') return baseChance
  if (!relativeBonusPercent) return baseChance
  return Math.min(100, baseChance * (1 + relativeBonusPercent / 100))
}

/** Add flat percentage points after relative bonuses, capped at 100. */
export function applyFlatDropChanceBonus(
  chance: number | null,
  flatBonusPercent: number,
): number | null {
  if (typeof chance !== 'number') return chance
  if (!flatBonusPercent) return chance
  return Math.min(100, chance + flatBonusPercent)
}
