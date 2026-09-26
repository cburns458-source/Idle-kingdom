import type { ActionRow, GameDatabase } from '../data/types'
import { normalizeAttackStyle, splitCombatVictoryXp } from '../combat/stats'
import { WEAPON_TOOL_SLOT_ID } from '../equipment/loadout'
import type { PlayerSave } from '../save/types'
import { configNumber } from './gathering'

/** Extra skill XP granted on specific Actions beyond Relevant Skill ID / XP Reward. */
const BONUS_SKILL_XP: Record<string, { skillId: string; xp: number }> = {}

export function bonusSkillXpForAction(
  action: ActionRow | Pick<ActionRow, 'Action ID'>,
): { skillId: string; xp: number } | null {
  return BONUS_SKILL_XP[action['Action ID']] ?? null
}

const HUNTING_SKILL_ID = 'SKL-0005'
const MIGHT_SKILL_ID = 'SKL-0001'
const VITALITY_SKILL_ID = 'SKL-0016'
const BOW_CAPABILITY_TAG = 'bow_combat_xp'

function equippedWeaponHasCapability(db: GameDatabase, save: PlayerSave, tag: string): boolean {
  const stack = save.equipment.slots[WEAPON_TOOL_SLOT_ID]
  if (!stack?.itemId) return false
  const equipment = db.Equipment.find((row) => row['Item ID'] === stack.itemId)
  const effects = equipment?.['Capabilities / Effects']
  if (typeof effects !== 'string') return false
  return effects
    .split(';')
    .some((part) => part.trim().toLowerCase() === tag)
}

/**
 * Qualifying bow-based Hunting Actions grant stance-routed Might / Vitality XP
 * equal to a percentage (default 10%, see Config `bow_hunting_combat_xp_percent`)
 * of the Hunting XP just awarded, whenever the equipped Weapon/Tool is a bow
 * (`bow_combat_xp` capability on its Equipment row).
 * See docs/Game_Bible.txt section 8.4.
 */
export function bowHuntingCombatXpBonus(
  db: GameDatabase,
  save: PlayerSave,
  action: Pick<ActionRow, 'Relevant Skill ID'>,
  huntingXpAwarded: number,
): Array<{ skillId: string; xp: number }> {
  if (action['Relevant Skill ID'] !== HUNTING_SKILL_ID) return []
  if (huntingXpAwarded <= 0) return []
  if (!equippedWeaponHasCapability(db, save, BOW_CAPABILITY_TAG)) return []
  const percent = configNumber(db, 'bow_hunting_combat_xp_percent', 10)
  const xp = Math.floor(huntingXpAwarded * (percent / 100))
  if (xp <= 0) return []
  const split = splitCombatVictoryXp(xp, normalizeAttackStyle(save.attackStyle))
  const grants: Array<{ skillId: string; xp: number }> = []
  if (split.mightXp > 0) grants.push({ skillId: MIGHT_SKILL_ID, xp: split.mightXp })
  if (split.vitalityXp > 0) grants.push({ skillId: VITALITY_SKILL_ID, xp: split.vitalityXp })
  return grants
}
