import {
  applyCombatDefeat,
  applyCombatVictory,
  beginCombatSave,
  clearCombatSave,
  deathPauseRemainingMs,
  enemyForAction,
  getEnemy,
  isDeathPaused,
  resolveCombatRound,
} from '../../game/combat/engine'
import { tryConsumeFoodAfterVictory } from '../../game/combat/food'
import { parsePotionEffect } from '../../game/potions/effects'
import { mulberry32 } from '../../game/rng/mulberry32'
import type { PlayerSave } from '../../game/save/types'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import { contentDatabase } from './contentDatabase'
import { asJson, baseSave, combatSave, fullBagSave, gearedSave } from './saveFixtures'

type SaveKind = 'base' | 'combat' | 'geared'

function saveFor(kind: SaveKind): PlayerSave {
  const db = contentDatabase()
  if (kind === 'base') return baseSave(db)
  if (kind === 'combat') return combatSave(db)
  return gearedSave(db)
}

function withSave(kind: SaveKind, extra: Record<string, JsonValue> = {}): JsonValue {
  return { source: 'content', save: asJson(saveFor(kind)), ...extra }
}

/** A base save holding two poison potions in the consumable slot. */
function poisonPotionSave(): PlayerSave {
  const base = saveFor('base')
  return {
    ...base,
    equipment: {
      slots: { ...base.equipment.slots, 'SLOT-0012': { itemId: 'ITEM-0073', quantity: 2 } },
    },
  }
}

function equippedPotionSave(itemId: string, currentHp = 400): PlayerSave {
  const base = saveFor('base')
  return {
    ...base,
    currentHp,
    equipment: {
      slots: { ...base.equipment.slots, 'SLOT-0012': { itemId, quantity: 2 } },
    },
  }
}

function activePotionSave(itemId: string, currentHp = 400): PlayerSave {
  const db = contentDatabase()
  const base = saveFor('base')
  const equipment = db.Equipment.find((row) => row['Item ID'] === itemId)
  const effect = parsePotionEffect(equipment, itemId, 'one_combat_encounter')
  return { ...base, currentHp, activePotionEffect: effect }
}

const NOW_MS = Date.parse('2026-01-01T00:00:00.000Z')
const NOW_ISO = '2026-01-01T00:00:00.000Z'
const SEED = 424242
const ROUNDS = 12

/** A goblin (weak), a skeleton (armored), and an unknown id. */
const ENEMY_IDS = ['ENM-0001', 'ENM-0003', 'ENM-0008', 'ENM-9999']
const COMBAT_ACTIONS = ['ACN-0003', 'ACN-0006', 'ACN-0009', 'ACN-0046']

export const combatScenarios: ParityScenario[] = [
  scenario('combat/lookups', 'enemies', { source: 'content', enemyIds: ENEMY_IDS }, () => {
    const db = contentDatabase()
    return {
      enemies: ENEMY_IDS.map((enemyId) => getEnemy(db, enemyId)?.['Enemy ID'] ?? null),
      byAction: COMBAT_ACTIONS.map((actionId) => {
        const action = db.Actions.find((row) => row['Action ID'] === actionId)!
        return { actionId, enemyId: enemyForAction(db, action)?.['Enemy ID'] ?? null }
      }),
    } as unknown as JsonValue
  }),

  ...(['combat', 'geared'] as const).map((kind) =>
    scenario('combat/begin', kind, withSave(kind, { nowIso: NOW_ISO }), () => {
      const db = contentDatabase()
      const action = db.Actions.find((row) => row['Action ID'] === 'ACN-0003')!
      const enemy = getEnemy(db, 'ENM-0003')!
      const begun = beginCombatSave(db, saveFor(kind), action, enemy, NOW_ISO)
      return { begun: asJson(begun), cleared: asJson(clearCombatSave(begun)) }
    }),
  ),

  // Poison potion is consumed at start; damage waits until after each swing.
  scenario(
    'combat/begin',
    'poison-potion',
    { source: 'content', save: asJson(poisonPotionSave()), nowIso: NOW_ISO },
    () => {
      const db = contentDatabase()
      const action = db.Actions.find((row) => row['Action ID'] === 'ACN-0003')!
      const enemy = getEnemy(db, 'ENM-0003')!
      const save = poisonPotionSave()
      return {
        begun: asJson(beginCombatSave(db, save, action, enemy, NOW_ISO)),
        cleared: asJson(clearCombatSave(beginCombatSave(db, save, action, enemy, NOW_ISO))),
      }
    },
  ),

  scenario(
    'combat/begin',
    'fernleaf-tonic',
    { source: 'content', save: asJson(equippedPotionSave('ITEM-0439')), nowIso: NOW_ISO },
    () => {
      const db = contentDatabase()
      const action = db.Actions.find((row) => row['Action ID'] === 'ACN-0003')!
      const enemy = getEnemy(db, 'ENM-0003')!
      const save = equippedPotionSave('ITEM-0439')
      return {
        begun: asJson(beginCombatSave(db, save, action, enemy, NOW_ISO)),
        cleared: asJson(clearCombatSave(beginCombatSave(db, save, action, enemy, NOW_ISO))),
      }
    },
  ),

  scenario(
    'combat/begin',
    'augur-draught',
    { source: 'content', save: asJson(equippedPotionSave('ITEM-0441')), nowIso: NOW_ISO },
    () => {
      const db = contentDatabase()
      const action = db.Actions.find((row) => row['Action ID'] === 'ACN-0003')!
      const enemy = getEnemy(db, 'ENM-0003')!
      const save = equippedPotionSave('ITEM-0441')
      return {
        begun: asJson(beginCombatSave(db, save, action, enemy, NOW_ISO)),
        cleared: asJson(clearCombatSave(beginCombatSave(db, save, action, enemy, NOW_ISO))),
      }
    },
  ),

  ...(['combat', 'geared'] as const).flatMap((kind) =>
    ENEMY_IDS.filter((enemyId) => enemyId !== 'ENM-9999').map((enemyId) =>
      scenario(
        'combat/rounds',
        `${kind}-${enemyId.toLowerCase()}`,
        withSave(kind, { enemyId, seed: SEED, rounds: ROUNDS }),
        () => {
          const db = contentDatabase()
          const enemy = getEnemy(db, enemyId)!
          const random = mulberry32(SEED)
          let save = saveFor(kind)
          let enemyHp = enemy['Maximum HP']
          const rounds: JsonValue[] = []
          for (let index = 0; index < ROUNDS; index += 1) {
            const round = resolveCombatRound(db, save, enemy, enemyHp, random)
            rounds.push(round as unknown as JsonValue)
            enemyHp = round.enemyHp
            save = { ...save, currentHp: round.playerHp, combatEnemyHp: round.enemyHp }
            if (round.outcome !== 'ongoing') break
          }
          return { rounds, save: asJson(save) }
        },
      ),
    ),
  ),

  scenario(
    'combat/rounds',
    'mosstole-brew-enm-0001',
    {
      source: 'content',
      save: asJson(activePotionSave('ITEM-0440')),
      enemyId: 'ENM-0001',
      seed: SEED,
      rounds: ROUNDS,
    },
    () => {
      const db = contentDatabase()
      const enemy = getEnemy(db, 'ENM-0001')!
      const random = mulberry32(SEED)
      let save = activePotionSave('ITEM-0440')
      let enemyHp = enemy['Maximum HP']
      const rounds: JsonValue[] = []
      for (let index = 0; index < ROUNDS; index += 1) {
        const round = resolveCombatRound(db, save, enemy, enemyHp, random)
        rounds.push(round as unknown as JsonValue)
        enemyHp = round.enemyHp
        save = { ...save, currentHp: round.playerHp, combatEnemyHp: round.enemyHp }
        if (round.outcome !== 'ongoing') break
      }
      return { rounds, save: asJson(save) }
    },
  ),

  ...(['base', 'combat', 'geared'] as const).map((kind) =>
    scenario('combat/victory', kind, withSave(kind, { seed: SEED, nowMs: NOW_MS }), () => {
      const db = contentDatabase()
      const action = db.Actions.find((row) => row['Action ID'] === 'ACN-0003')!
      const enemy = getEnemy(db, 'ENM-0003')!
      const result = applyCombatVictory(db, saveFor(kind), action, enemy, mulberry32(SEED), NOW_MS)
      return {
        save: asJson(result.save),
        xpGained: result.xpGained,
        goldGained: result.goldGained,
        loot: result.loot,
        ...(result.leftBehind?.length ? { leftBehind: result.leftBehind } : {}),
        foodConsumed: result.foodConsumed,
        foodHealed: result.foodHealed,
        foodName: result.foodName,
      } as unknown as JsonValue
    }),
  ),

  scenario(
    'combat/victory',
    'full-bag-left-behind',
    {
      source: 'content',
      save: asJson(fullBagSave(contentDatabase(), ['ITEM-0100'])),
      seed: SEED,
      nowMs: NOW_MS,
    },
    () => {
      const db = contentDatabase()
      const action = db.Actions.find((row) => row['Action ID'] === 'ACN-0003')!
      const enemy = getEnemy(db, 'ENM-0003')!
      const result = applyCombatVictory(
        db,
        fullBagSave(db, ['ITEM-0100']),
        action,
        enemy,
        mulberry32(SEED),
        NOW_MS,
      )
      return {
        save: asJson(result.save),
        xpGained: result.xpGained,
        goldGained: result.goldGained,
        loot: result.loot,
        ...(result.leftBehind?.length ? { leftBehind: result.leftBehind } : {}),
        foodConsumed: result.foodConsumed,
        foodHealed: result.foodHealed,
        foodName: result.foodName,
      } as unknown as JsonValue
    },
  ),

  scenario(
    'combat/victory',
    'luck-potion-combat',
    {
      source: 'content',
      save: asJson(activePotionSave('ITEM-0070')),
      seed: SEED,
      nowMs: NOW_MS,
    },
    () => {
      const db = contentDatabase()
      const action = db.Actions.find((row) => row['Action ID'] === 'ACN-0003')!
      const enemy = getEnemy(db, 'ENM-0003')!
      const result = applyCombatVictory(
        db,
        activePotionSave('ITEM-0070'),
        action,
        enemy,
        mulberry32(SEED),
        NOW_MS,
      )
      return {
        save: asJson(result.save),
        xpGained: result.xpGained,
        goldGained: result.goldGained,
        loot: result.loot,
        ...(result.leftBehind?.length ? { leftBehind: result.leftBehind } : {}),
        foodConsumed: result.foodConsumed,
        foodHealed: result.foodHealed,
        foodName: result.foodName,
      } as unknown as JsonValue
    },
  ),

  ...(['base', 'combat', 'geared'] as const).map((kind) =>
    scenario('combat/food', kind, withSave(kind), () => {
      const db = contentDatabase()
      const hurt: PlayerSave = { ...saveFor(kind), currentHp: 5 }
      const healed = tryConsumeFoodAfterVictory(db, hurt)
      const full = tryConsumeFoodAfterVictory(db, { ...saveFor(kind), currentHp: 99_999 })
      return {
        hurt: {
          save: asJson(healed.save),
          consumed: healed.consumed,
          healed: healed.healed,
          foodName: healed.foodName,
        },
        full: { save: asJson(full.save), consumed: full.consumed, healed: full.healed },
      } as unknown as JsonValue
    }),
  ),

  scenario('combat/defeat', 'pause', withSave('combat', { nowMs: NOW_MS }), () => {
    const db = contentDatabase()
    const defeated = applyCombatDefeat(db, saveFor('combat'), NOW_MS)
    return {
      save: asJson(defeated),
      paused: isDeathPaused(defeated, NOW_MS),
      pausedLater: isDeathPaused(defeated, NOW_MS + 60_000),
      remaining: deathPauseRemainingMs(defeated, NOW_MS),
      remainingLater: deathPauseRemainingMs(defeated, NOW_MS + 60_000),
      noPause: isDeathPaused(saveFor('combat'), NOW_MS),
      noPauseRemaining: deathPauseRemainingMs(saveFor('combat'), NOW_MS),
    }
  }),
]
