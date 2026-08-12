import {
  applyMitigation,
  combatLevelBonusMultiplier,
  playerDamageRange,
  playerDamageReduction,
  playerMaxHp,
  playerOffhandDamageRange,
  rollDamage,
} from '../../game/combat/stats'
import { mulberry32 } from '../../game/rng/mulberry32'
import type { PlayerSave } from '../../game/save/types'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import { contentDatabase } from './contentDatabase'
import { asJson, baseSave, gearedSave, richSave } from './saveFixtures'

type SaveKind = 'base' | 'rich' | 'geared'

function saveFor(kind: SaveKind): PlayerSave {
  const db = contentDatabase()
  if (kind === 'base') return baseSave(db)
  if (kind === 'rich') return richSave(db)
  return gearedSave(db)
}

function withSave(kind: SaveKind, extra: Record<string, JsonValue> = {}): JsonValue {
  return { source: 'content', save: asJson(saveFor(kind)), ...extra }
}

/** Combat levels around the level-10 bonus threshold. */
const COMBAT_LEVELS = [1, 9, 10, 11, 25, 99]

const ROLL_SEED = 20260812
const ROLL_COUNT = 24

const MITIGATION_CASES: Array<[number, number, number]> = [
  [100, 0, 1],
  [100, 40, 1],
  [100, 150, 1],
  [100, -10, 1],
  [0, 0, 5],
  [12.5, 2.5, 1],
]

function withCombatLevel(save: PlayerSave, level: number): PlayerSave {
  return {
    ...save,
    skills: save.skills.map((skill) =>
      skill.skillId === 'SKL-0001' ? { ...skill, level } : skill,
    ),
  }
}

export const combatStatScenarios: ParityScenario[] = [
  ...(['base', 'rich', 'geared'] as const).map((kind) =>
    scenario('combat/stats', kind, withSave(kind), () => {
      const db = contentDatabase()
      const save = saveFor(kind)
      return {
        maxHp: playerMaxHp(db, save),
        damageReduction: playerDamageReduction(db, save),
        damageRange: playerDamageRange(db, save),
        offhandRange: playerOffhandDamageRange(db, save),
        levelMultiplier: combatLevelBonusMultiplier(save),
      } as unknown as JsonValue
    }),
  ),

  scenario('combat/stats', 'level-thresholds', withSave('geared', { levels: COMBAT_LEVELS }), () => {
    const db = contentDatabase()
    return {
      byLevel: COMBAT_LEVELS.map((level) => {
        const save = withCombatLevel(saveFor('geared'), level)
        return {
          level,
          multiplier: combatLevelBonusMultiplier(save),
          maxHp: playerMaxHp(db, save),
          damageRange: playerDamageRange(db, save),
        }
      }),
    } as unknown as JsonValue
  }),

  scenario(
    'combat/roll-damage',
    'seeded-sequence',
    { source: 'content', seed: ROLL_SEED, count: ROLL_COUNT },
    () => {
      const random = mulberry32(ROLL_SEED)
      const rolls: number[] = []
      for (let index = 0; index < ROLL_COUNT; index += 1) {
        rolls.push(rollDamage(10, 30, random))
      }
      // Reversed bounds must behave the same as ordered ones.
      const swapped = mulberry32(ROLL_SEED)
      return {
        rolls,
        swapped: Array.from({ length: ROLL_COUNT }, () => rollDamage(30, 10, swapped)),
      }
    },
  ),

  scenario(
    'combat/mitigation',
    'cases',
    { source: 'content', cases: MITIGATION_CASES },
    () => ({
      results: MITIGATION_CASES.map(([raw, reduction, floor]) =>
        applyMitigation(raw, reduction, floor),
      ),
    }),
  ),
]
