import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { POTION_SLOT_ID } from '../equipment/loadout'
import { createNewSave } from '../save/saveStore'
import type { PlayerSave } from '../save/types'
import { enemyScaledMaxHp } from '../combat/stats'
import { beginCombatSave } from '../combat/engine'
import { beginProductionQueue } from '../production/engine'
import { generateNextAction } from '../activity/engine'
import { addItemToInventory } from '../activity/rewards'
import { migrateSave } from '../save/migrations'
import { resolveCombatRound } from '../combat/engine'
import {
  applyPotionDropChance,
  applyPotionDurationMs,
  applyPotionEnemyRoundDamage,
  applyPotionInstantHeal,
  applyPotionRegenHeal,
  parsePotionEffect,
  tickPotionAction,
  tryConsumePotionForScope,
} from './effects'
import { POTION_ACTION_DURATION } from '../save/types'
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
      {
        itemId: 'ITEM-0439',
        scope: 'one_combat_encounter',
        check: (e) => expect(e.instantHealMaxHpPercent).toBe(5),
      },
      {
        itemId: 'ITEM-0440',
        scope: 'one_combat_encounter',
        check: (e) => expect(e.regenMaxHpPercentPerRound).toBe(3),
      },
      {
        itemId: 'ITEM-0441',
        scope: 'one_combat_encounter',
        check: (e) => {
          expect(e.damageBonusMin).toBe(10)
          expect(e.damageBonusMax).toBe(30)
        },
      },
      {
        itemId: 'ITEM-0442',
        scope: 'one_combat_encounter',
        check: (e) => {
          expect(e.damageBonusMin).toBe(30)
          expect(e.damageBonusMax).toBe(90)
        },
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
    expect(started.combatEnemyHp).toBe(enemyScaledMaxHp(enemy))
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

  it('skips new drinks while potions are paused', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = {
      ...withPotion(createNewSave(launch), 'ITEM-0070', 1),
      settings: { ...createNewSave(launch).settings, potionsPaused: true },
    }
    const result = tryConsumePotionForScope(launch, save, 'one_action')
    expect(result.consumed).toBe(false)
    expect(result.save.equipment.slots[POTION_SLOT_ID]?.quantity).toBe(1)
    expect(result.save.activePotionEffect).toBeNull()
  })

  it('keeps a drunk potion for six actions and only then drinks another', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = withPotion(createNewSave(launch), 'ITEM-0070', 2)
    const first = tryConsumePotionForScope(launch, save, 'one_action')
    expect(first.consumed).toBe(true)
    expect(first.effect?.actionsRemaining).toBe(POTION_ACTION_DURATION)
    expect(first.save.equipment.slots[POTION_SLOT_ID]?.quantity).toBe(1)

    save = first.save
    for (let i = POTION_ACTION_DURATION; i > 1; i -= 1) {
      const reuse = tryConsumePotionForScope(launch, save, 'one_action')
      expect(reuse.consumed).toBe(false)
      expect(reuse.save.equipment.slots[POTION_SLOT_ID]?.quantity).toBe(1)
      save = tickPotionAction(reuse.save)
      expect(save.activePotionEffect?.actionsRemaining).toBe(i - 1)
    }

    save = tickPotionAction(save)
    expect(save.activePotionEffect).toBeNull()
    const next = tryConsumePotionForScope(launch, save, 'one_action')
    expect(next.consumed).toBe(true)
    expect(next.effect?.actionsRemaining).toBe(POTION_ACTION_DURATION)
    expect(next.save.equipment.slots[POTION_SLOT_ID]).toBeNull()
  })

  it('heals a percent of max HP on drink, capped at max HP', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const equipment = launch.Equipment.find((row) => row['Item ID'] === 'ITEM-0439')
    const effect = parsePotionEffect(equipment, 'ITEM-0439')
    expect(applyPotionInstantHeal(400, 1000, effect)).toBe(450)
    expect(applyPotionInstantHeal(980, 1000, effect)).toBe(1000)
    expect(applyPotionInstantHeal(1000, 1000, effect)).toBe(1000)

    const hurt = { ...withPotion(createNewSave(launch), 'ITEM-0439', 1), currentHp: 400 }
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0001')!
    const started = beginCombatSave(launch, hurt, action, enemy)
    expect(started.currentHp).toBe(400 + Math.floor(started.maxHp * 0.05))
    expect(started.currentHp).toBeLessThanOrEqual(started.maxHp)
    const full = beginCombatSave(launch, { ...hurt, currentHp: started.maxHp }, action, enemy)
    expect(full.currentHp).toBe(full.maxHp)
  })

  it('heals a percent of max HP each combat round, capped at max HP', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const equipment = launch.Equipment.find((row) => row['Item ID'] === 'ITEM-0440')
    const effect = parsePotionEffect(equipment, 'ITEM-0440')
    expect(applyPotionRegenHeal(400, 1000, effect)).toBe(430)
    expect(applyPotionRegenHeal(990, 1000, effect)).toBe(1000)
    expect(applyPotionRegenHeal(1000, 1000, effect)).toBe(1000)

    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0001')!
    const started = beginCombatSave(
      launch,
      { ...withPotion(createNewSave(launch), 'ITEM-0440', 1), currentHp: 400 },
      action,
      enemy,
    )
    const before = started.currentHp
    const round = resolveCombatRound(launch, started, enemy, started.combatEnemyHp ?? 0, () => 0)
    expect(round.playerHpAfterPlayer).toBeGreaterThanOrEqual(before)
    expect(round.playerHpAfterPlayer).toBeLessThanOrEqual(started.maxHp)
  })

  it('adds a flat min/max damage bonus', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = withPotion(createNewSave(launch), 'ITEM-0441', 1)
    const baseline = playerDamageRange(launch, save)
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0001')!
    const started = beginCombatSave(launch, save, action, enemy)
    expect(started.activePotionEffect?.damageBonusMin).toBe(10)
    expect(started.activePotionEffect?.damageBonusMax).toBe(30)
    const boosted = playerDamageRange(launch, started)
    expect(boosted.min).toBeGreaterThan(baseline.min)
    expect(boosted.max).toBeGreaterThan(baseline.max)
  })

  it('does not apply Speed to Alchemy, but still applies Masterwork', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const recipe = launch.Recipes.find((row) => row['Recipe ID'] === 'RCP-0078')!
    const baseMs = recipe['Base Duration Seconds'] * 1000
    let herbs = { ...createNewSave(launch), currentLocationId: 'LOC-0026', inventory: [] as PlayerSave['inventory'] }
    herbs = addItemToInventory(herbs, 'ITEM-0031', 4)

    const speed = beginProductionQueue(launch, withPotion(herbs, 'ITEM-0071', 1), 'ACT-0020', 'RCP-0078', 1)
    expect(speed.ok).toBe(true)
    if (!speed.ok) return
    expect(speed.save.equipment.slots[POTION_SLOT_ID]?.itemId).toBe('ITEM-0071')
    expect(speed.save.activePotionEffect).toBeNull()
    expect(speed.save.actionDurationMs).toBe(baseMs)

    const masterwork = beginProductionQueue(launch, withPotion(herbs, 'ITEM-0213', 1), 'ACT-0020', 'RCP-0078', 1)
    expect(masterwork.ok).toBe(true)
    if (!masterwork.ok) return
    expect(masterwork.save.equipment.slots[POTION_SLOT_ID]).toBeNull()
    expect(masterwork.save.activePotionEffect?.itemId).toBe('ITEM-0213')
    expect(masterwork.save.actionDurationMs).toBe(Math.floor(baseMs * 0.85))
  })

  it('loads old saves that still store Poison as enemyMaxHpDamagePercent', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const created = createNewSave(launch)
    const legacy = {
      ...created,
      saveVersion: 64,
      activePotionEffect: {
        scope: 'one_combat_encounter',
        itemId: 'ITEM-0073',
        damageBonusPercent: null,
        enemyMaxHpDamagePercent: 10,
        relativeDropChanceBonusPercent: null,
        baseDurationReductionPercent: null,
        actionsRemaining: 6,
      },
    }
    const migrated = migrateSave(legacy as PlayerSave)
    expect(migrated.saveVersion).toBe(65)
    expect(migrated.activePotionEffect?.enemyMaxHpDamagePercent).toBe(10)
    expect(migrated.activePotionEffect?.instantHealMaxHpPercent).toBeNull()
    expect(migrated.activePotionEffect?.regenMaxHpPercentPerRound).toBeNull()
    expect(applyPotionEnemyRoundDamage(1000, 1000, migrated.activePotionEffect)).toBe(900)
  })
})
