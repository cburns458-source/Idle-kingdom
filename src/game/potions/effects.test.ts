import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { POTION_SLOT_ID } from '../equipment/loadout'
import { createNewSave } from '../save/saveStore'
import type { PlayerSave } from '../save/types'
import { beginCombatSave } from '../combat/engine'
import { beginProductionQueue } from '../production/engine'
import { generateNextAction } from '../activity/engine'
import { addItemToInventory } from '../activity/rewards'
import {
  applyPotionDropChance,
  applyPotionDurationMs,
  applyPotionEnemyRoundDamage,
  parsePotionEffect,
  tryConsumePotionForScope,
} from './effects'
import { playerDamageRange } from '../combat/stats'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

function withPotion(save: PlayerSave, itemId: string, quantity = 1): PlayerSave {
  return {
    ...save,
    equipment: {
      ...save.equipment,
      slots: {
        ...save.equipment.slots,
        [POTION_SLOT_ID]: { itemId, quantity },
      },
    },
  }
}

describe('potion effects', () => {
  it('parses every current potion capability tag set', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const cases: Array<{ itemId: string; scope: string; check: (effect: NonNullable<ReturnType<typeof parsePotionEffect>>) => void }> = [
      {
        itemId: 'ITEM-0211',
        scope: 'one_combat_encounter',
        check: (e) => expect(e.damageBonusPercent).toBe(5),
      },
      {
        itemId: 'ITEM-0072',
        scope: 'one_combat_encounter',
        check: (e) => expect(e.damageBonusPercent).toBe(10),
      },
      {
        itemId: 'ITEM-0212',
        scope: 'one_combat_encounter',
        check: (e) => expect(e.damageBonusPercent).toBe(12),
      },
      {
        itemId: 'ITEM-0073',
        scope: 'one_combat_encounter',
        check: (e) => expect(e.enemyMaxHpDamagePercent).toBe(10),
      },
      {
        itemId: 'ITEM-0210',
        scope: 'one_action',
        check: (e) => expect(e.relativeDropChanceBonusPercent).toBe(10),
      },
      {
        itemId: 'ITEM-0070',
        scope: 'one_action',
        check: (e) => expect(e.relativeDropChanceBonusPercent).toBe(25),
      },
      {
        itemId: 'ITEM-0071',
        scope: 'one_standard_production_action',
        check: (e) => expect(e.baseDurationReductionPercent).toBe(10),
      },
      {
        itemId: 'ITEM-0213',
        scope: 'one_standard_production_action',
        check: (e) => expect(e.baseDurationReductionPercent).toBe(15),
      },
    ]

    for (const entry of cases) {
      const equipment = launch.Equipment.find((row) => row['Item ID'] === entry.itemId)
      const effect = parsePotionEffect(equipment, entry.itemId)
      expect(effect, entry.itemId).toBeTruthy()
      expect(effect!.scope).toBe(entry.scope)
      entry.check(effect!)
    }
  })

  it('consumes strength potions on combat start and boosts damage', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = withPotion(createNewSave(launch), 'ITEM-0211', 2)
    const baseline = playerDamageRange(launch, save)
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0001')!
    const started = beginCombatSave(launch, save, action, enemy)

    expect(started.equipment.slots[POTION_SLOT_ID]?.quantity).toBe(1)
    expect(started.activePotionEffect?.damageBonusPercent).toBe(5)
    const boosted = playerDamageRange(launch, started)
    expect(boosted.min).toBe(Math.floor(baseline.min * 1.05))
  })

  it('consumes poison potions on combat start without chipping enemy HP yet', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = withPotion(createNewSave(launch), 'ITEM-0073', 1)
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0001')!
    const started = beginCombatSave(launch, save, action, enemy)
    expect(started.equipment.slots[POTION_SLOT_ID]).toBeNull()
    expect(started.combatEnemyHp).toBe(enemy['Maximum HP'])
    expect(started.activePotionEffect?.enemyMaxHpDamagePercent).toBe(10)
  })

  it('still parses the old maximum-HP poison tag', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const equipment = launch.Equipment.find((row) => row['Item ID'] === 'ITEM-0073')!
    const effect = parsePotionEffect(
      { ...equipment, 'Capabilities / Effects': 'potion_slot; one_combat_encounter; deals 10% of enemy maximum HP' },
      'ITEM-0073',
    )
    expect(effect?.enemyMaxHpDamagePercent).toBe(10)
  })

  it('ticks poison after the swing as 10% of current HP and stops at 10% max', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const equipment = launch.Equipment.find((row) => row['Item ID'] === 'ITEM-0073')
    const effect = parsePotionEffect(equipment, 'ITEM-0073')
    expect(applyPotionEnemyRoundDamage(1000, 1000, effect)).toBe(900)
    expect(applyPotionEnemyRoundDamage(900, 1000, effect)).toBe(810)
    expect(applyPotionEnemyRoundDamage(111, 1000, effect)).toBe(100)
    expect(applyPotionEnemyRoundDamage(100, 1000, effect)).toBe(100)
    expect(applyPotionEnemyRoundDamage(5, 1000, effect)).toBe(5)
  })

  it('consumes luck potions when a gathering action starts', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = withPotion(createNewSave(launch), 'ITEM-0070', 1)
    save = { ...save, currentLocationId: 'LOC-0009' }
    const generated = generateNextAction(launch, save, 'ACT-0012', () => 0)
    expect(generated).toBeTruthy()
    expect(generated!.save.equipment.slots[POTION_SLOT_ID]).toBeNull()
    expect(generated!.save.activePotionEffect?.relativeDropChanceBonusPercent).toBe(25)
    expect(applyPotionDropChance(80, generated!.save.activePotionEffect)).toBe(100)
  })

  it('consumes speed potions when a production craft starts', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = withPotion(createNewSave(launch), 'ITEM-0071', 1)
    save = { ...save, inventory: [] }
    save = addItemToInventory(save, 'ITEM-0025', 2)
    const queued = beginProductionQueue(launch, save, 'ACT-0017', 'RCP-0001', 1)
    expect(queued.ok).toBe(true)
    if (!queued.ok) return
    expect(queued.save.equipment.slots[POTION_SLOT_ID]).toBeNull()
    const recipe = launch.Recipes.find((row) => row['Recipe ID'] === 'RCP-0001')!
    const baseMs = recipe['Base Duration Seconds'] * 1000
    expect(queued.save.actionDurationMs).toBe(applyPotionDurationMs(baseMs, queued.save.activePotionEffect))
    expect(queued.save.actionDurationMs).toBe(Math.floor(baseMs * 0.9))
  })

  it('does not consume a combat potion for a gathering action', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = withPotion(createNewSave(launch), 'ITEM-0211', 1)
    const result = tryConsumePotionForScope(launch, save, 'one_action')
    expect(result.consumed).toBe(false)
    expect(result.save.equipment.slots[POTION_SLOT_ID]?.quantity).toBe(1)
  })
})
