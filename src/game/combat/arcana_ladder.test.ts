import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { addItemToInventory } from '../activity/rewards'
import { equipItemFromInventory, unequipSlot } from '../equipment/loadout'
import { applyEnchantmentToTarget } from '../projects/enchantments'
import { createNewSave } from '../save/saveStore'
import { gatheringDurationMs } from '../activity/gathering'
import { productionCraftDurationMs } from '../production/engine'
import { playerDamageRange, playerDamageReduction, playerMaxHp } from './stats'
import { applyCombatVictory, beginCombatSave, resolveCombatRound } from './engine'
import {
  activeSpellDamageReductionPercent,
  activeSpellGatheringDurationMultiplier,
  activeSpellGoldDoubleChancePercent,
  activeSpellLifestealPercent,
  activeSpellProductionDurationMultiplier,
} from '../spells/spells'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

function equipSpell(db: ReturnType<typeof prepareDatabase>['launch'], save: ReturnType<typeof createNewSave>, itemId: string) {
  let next = addItemToInventory(save, itemId, 1)
  const equipped = equipItemFromInventory(db, next, itemId)
  expect(equipped.ok).toBe(true)
  if (!equipped.ok) throw new Error('equip failed')
  return equipped.save
}

describe('arcana ladder runtime', () => {
  it('applies Iron Ward spell damage reduction', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    const base = playerDamageReduction(launch, save)
    save = equipSpell(launch, save, 'ITEM-0395')
    expect(activeSpellDamageReductionPercent(launch, save)).toBe(5)
    expect(playerDamageReduction(launch, save)).toBe(base + 5)
  })

  it('applies Hoard gold double on victory when chance hits', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0003')!
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0003')!
    const without = applyCombatVictory(launch, save, action, enemy, () => 0)
    save = equipSpell(launch, save, 'ITEM-0394')
    expect(activeSpellGoldDoubleChancePercent(launch, save)).toBe(10)
    // Same RNG stream as without: gold rolls match, then Hoard procs at random()===0.
    const withHoard = applyCombatVictory(launch, save, action, enemy, () => 0)
    expect(withHoard.goldGained).toBe(without.goldGained * 2)
  })

  it('heals from Lifesteal after dealing damage', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    const cleared = unequipSlot(save, 'SLOT-0001')
    expect(cleared.ok).toBe(true)
    if (!cleared.ok) return
    save = cleared.save
    save = equipSpell(launch, save, 'ITEM-0396')
    expect(activeSpellLifestealPercent(launch, save)).toBe(5)

    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0003')!
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === action['Target ID'])!
    save = { ...beginCombatSave(launch, save, action, enemy), currentHp: 100 }
    const round = resolveCombatRound(launch, save, enemy, enemy['Maximum HP'], () => 0)
    const damageDealt = round.playerHit + (round.offhandHit ?? 0) + (round.staffHit ?? 0)
    const expectedHeal = Math.floor((damageDealt * 5) / 100)
    if (round.enemyHit == null) {
      expect(round.playerHp).toBe(Math.min(playerMaxHp(launch, save), 100 + expectedHeal))
    } else {
      expect(round.playerHp).toBe(
        Math.max(0, Math.min(playerMaxHp(launch, save), 100 + expectedHeal) - round.enemyHit),
      )
    }
  })

  it('applies Haste and Pathfinder duration multipliers', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    const action = launch.Actions.find(
      (row) => row.Category === 'Gathering' && row['Relevant Skill ID'] === 'SKL-0002',
    )!
    const recipe = launch.Recipes.find((row) => row['Skill ID'] === 'SKL-0007')!
    const baseGather = gatheringDurationMs(launch, save, action)
    const baseCraft = productionCraftDurationMs(launch, save, recipe, null)

    save = equipSpell(launch, save, 'ITEM-0398')
    save = equipSpell(launch, save, 'ITEM-0399')
    expect(activeSpellProductionDurationMultiplier(launch, save)).toBeCloseTo(0.9)
    expect(activeSpellGatheringDurationMultiplier(launch, save)).toBeCloseTo(0.9)
    expect(gatheringDurationMs(launch, save, action)).toBeCloseTo(baseGather * 0.9)
    expect(productionCraftDurationMs(launch, save, recipe, null)).toBeCloseTo(baseCraft * 0.9)
  })

  it('applies Minor Strength as percent damage range and Vital Plating as max HP%', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      equipment: {
        ...save.equipment,
        slots: {
          ...save.equipment.slots,
          'SLOT-0001': { itemId: 'ITEM-0124', quantity: 1 },
          'SLOT-0003': { itemId: 'ITEM-0155', quantity: 1 },
        },
      },
    }
    const baseDamage = playerDamageRange(launch, save)
    const beforePlate = playerMaxHp(launch, save)

    const weaponEnch = applyEnchantmentToTarget(
      save,
      { kind: 'equipped', slotId: 'SLOT-0001' },
      'ENCH-0003',
    )!
    expect(playerDamageRange(launch, weaponEnch).min).toBe(Math.floor(baseDamage.min * 1.05))
    expect(playerDamageRange(launch, weaponEnch).max).toBe(
      Math.max(Math.floor(baseDamage.min * 1.05), Math.floor(baseDamage.max * 1.05)),
    )

    const plated = applyEnchantmentToTarget(
      save,
      { kind: 'equipped', slotId: 'SLOT-0003' },
      'ENCH-0013',
    )!
    expect(playerMaxHp(launch, plated) / beforePlate).toBeCloseTo(1.05, 1)
  })

  it('procs Double Shot on enchanted bows', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      equipment: {
        ...save.equipment,
        slots: {
          ...save.equipment.slots,
          'SLOT-0001': { itemId: 'ITEM-0135', quantity: 1, enchantmentId: 'ENCH-0018' },
          'SLOT-0002': null,
        },
      },
    }

    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0003')!
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === action['Target ID'])!
    save = beginCombatSave(launch, save, action, enemy)
    const seq =
      (...values: number[]) =>
      () => {
        const next = values.shift()
        return next ?? 0.5
      }
    // Main hit min, Double Shot procs, second hit min → 30+30.
    const withProc = resolveCombatRound(launch, save, enemy, 50_000, seq(0, 0, 0))
    // Main hit min, Double Shot misses → 30.
    const withoutProc = resolveCombatRound(launch, save, enemy, 50_000, seq(0, 0.9))
    expect(withProc.playerHit).toBe(60)
    expect(withoutProc.playerHit).toBe(30)
  })
})
