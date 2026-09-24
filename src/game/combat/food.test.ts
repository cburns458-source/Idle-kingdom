import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { addItemToInventory } from '../activity/rewards'
import { prepareDatabase } from '../data/loadDatabase'
import { beginProductionQueue, completeProductionCraft } from '../production/engine'
import { createNewSave } from '../save/saveStore'
import type { EquippedStack } from '../save/types'
import { collectLocationTimer, plantBotanySeed } from '../timers/locationTimers'
import {
  consumeFoodAfterVictory,
  eatEquippedFood,
  eatInventoryFood,
  extraFoodPerRound,
  stageEatBlockedReason,
} from './food'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

function withFoodAndSpells(
  launch: ReturnType<typeof prepareDatabase>['launch'],
  foodQty: number,
  gluttonyCount: number,
) {
  const base = createNewSave(launch)
  const slots: Record<string, EquippedStack | null> = {
    ...base.equipment.slots,
    'SLOT-0011': { itemId: 'ITEM-0058', quantity: foodQty },
  }
  const spellSlots = ['SLOT-0013', 'SLOT-0014', 'SLOT-0015', 'SLOT-0016'] as const
  for (let i = 0; i < gluttonyCount; i += 1) {
    slots[spellSlots[i]!] = { itemId: 'ITEM-0312', quantity: 1 }
  }
  return { ...base, currentHp: 900, equipment: { ...base.equipment, slots } }
}

describe('cooked beef and tablet recipes', () => {
  it('cooks beef at level 1 for 12s / 240 XP and heals 40', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const recipe = launch.Recipes.find((row) => row['Recipe ID'] === 'RCP-0009')!
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0120')!
    const equipment = launch.Equipment.find((row) => row['Equipment ID'] === 'EQP-0010')!
    expect(recipe['Proficiency Level']).toBe(1)
    expect(recipe['Base Duration Seconds']).toBe(12)
    expect(recipe['XP Reward']).toBe(240)
    expect(action['Proficiency Level']).toBe(1)
    expect(action['Base Duration Seconds']).toBe(12)
    expect(action['XP Reward']).toBe(240)
    expect(equipment['Healing Amount']).toBe(40)
  })

  it('swaps tablet herbs onto the cheaper lines', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const enchanting = launch.Recipes.find((row) => row['Recipe ID'] === 'RCP-0036')!
    const spell = launch.Recipes.find((row) => row['Recipe ID'] === 'RCP-0037')!
    expect(enchanting['Ingredient 2 Item ID']).toBe('ITEM-0031')
    expect(enchanting['Ingredient 2 Quantity']).toBe(3)
    expect(spell['Ingredient 2 Item ID']).toBe('ITEM-0033')
    expect(spell['Ingredient 2 Quantity']).toBe(2)
  })

  it('adds soup stock at cooking 16 from water and scraps and uses it in stews', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const stock = launch.Recipes.find((row) => row['Recipe ID'] === 'RCP-0068')!
    expect(stock['Display Name']).toBe('Soup Stock')
    expect(stock['Facility ID']).toBe('FAC-0001')
    expect(stock['Proficiency Level']).toBe(16)
    expect(stock['Base Duration Seconds']).toBe(28)
    expect(stock['XP Reward']).toBe(0)
    expect(stock['Ingredient 1 Item ID']).toBe('ITEM-0365')
    expect(stock['Ingredient 1 Quantity']).toBe(1)
    expect(stock['Ingredient 2 Item ID']).toBe('ITEM-0366')
    expect(stock['Ingredient 2 Quantity']).toBe(1)
    expect(stock['Ingredient 3 Item ID']).toBeNull()
    expect(stock['Ingredient 4 Item ID']).toBeNull()
    for (const recipeId of ['RCP-0012', 'RCP-0013', 'RCP-0060', 'RCP-0063', 'RCP-0064', 'RCP-0065', 'RCP-0066']) {
      const recipe = launch.Recipes.find((row) => row['Recipe ID'] === recipeId)!
      expect(recipe['Ingredient 4 Item ID']).toBe('ITEM-0364')
      expect(recipe['Ingredient 4 Quantity']).toBe(1)
    }
    expect(launch.Recipes.find((row) => row['Recipe ID'] === 'RCP-0012')?.['XP Reward']).toBe(11431)
    expect(launch.Recipes.find((row) => row['Recipe ID'] === 'RCP-0060')?.['XP Reward']).toBe(65329)
    const marlin = launch.Recipes.find((row) => row['Recipe ID'] === 'RCP-0044')!
    expect(marlin.Status).toBe('Planned')
    expect(marlin['Display Name']).toBe('Cooked Marlin')
    expect(launch.Actions.find((row) => row['Action ID'] === 'ACN-0127')?.Status).toBe('Planned')
    expect(launch.Actions.find((row) => row['Action ID'] === 'ACN-0127')?.['Display Name']).toBe(
      'Cooked marlin',
    )
    expect(launch.Actions.find((row) => row['Action ID'] === 'ACN-0104')?.['Proficiency Level']).toBe(70)
    expect(launch.Recipes.find((row) => row['Recipe ID'] === 'RCP-0060')?.['Proficiency Level']).toBe(80)
  })
})

describe('gluttony extra auto-eats', () => {
  it('counts one extra eat per equipped Gluttony', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(extraFoodPerRound(launch, withFoodAndSpells(launch, 4, 0))).toBe(0)
    expect(extraFoodPerRound(launch, withFoodAndSpells(launch, 4, 2))).toBe(2)
  })

  it('adds one auto-eat per Gluttony on top of the usual bite', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const none = consumeFoodAfterVictory(launch, withFoodAndSpells(launch, 4, 0))
    expect(none.consumed).toBe(true)
    expect(none.save.equipment.slots['SLOT-0011']?.quantity).toBe(3)

    const two = consumeFoodAfterVictory(launch, withFoodAndSpells(launch, 4, 2))
    expect(two.consumed).toBe(true)
    expect(two.save.equipment.slots['SLOT-0011']?.quantity).toBe(1)

    const empty = consumeFoodAfterVictory(launch, withFoodAndSpells(launch, 2, 4))
    expect(empty.consumed).toBe(true)
    expect(empty.save.equipment.slots['SLOT-0011']).toBeNull()
  })

  it('does not eat healing food above the eat-at threshold', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = {
      ...withFoodAndSpells(launch, 4, 0),
      currentHp: 800,
      settings: {
        ...withFoodAndSpells(launch, 4, 0).settings,
        eatHealthThresholdPercent: 50,
      },
    }
    const skipped = consumeFoodAfterVictory(launch, save)
    expect(skipped.consumed).toBe(false)
    expect(skipped.save.equipment.slots['SLOT-0011']?.quantity).toBe(4)

    const eaten = consumeFoodAfterVictory(launch, { ...save, currentHp: 500 })
    expect(eaten.consumed).toBe(true)
    expect(eaten.save.equipment.slots['SLOT-0011']?.quantity).toBe(3)
  })

  it('skips healing food and Gluttony extras on a one-hit clean kill', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = withFoodAndSpells(launch, 4, 2)
    const skipped = consumeFoodAfterVictory(launch, save, { skipHealing: true })
    expect(skipped.consumed).toBe(false)
    expect(skipped.save.equipment.slots['SLOT-0011']?.quantity).toBe(4)
  })

  it('does not eat healing food at full HP even with Gluttony', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const full = consumeFoodAfterVictory(launch, {
      ...withFoodAndSpells(launch, 4, 2),
      currentHp: 99_999,
    })
    expect(full.consumed).toBe(false)
    expect(full.save.equipment.slots['SLOT-0011']?.quantity).toBe(4)
  })

  it('skips auto-eat entirely when the toggle is off', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = {
      ...withFoodAndSpells(launch, 4, 2),
      settings: { ...withFoodAndSpells(launch, 4, 2).settings, autoEat: false },
    }
    const skipped = consumeFoodAfterVictory(launch, save)
    expect(skipped.consumed).toBe(false)
    expect(skipped.save.equipment.slots['SLOT-0011']?.quantity).toBe(4)
  })
})

describe('manual eat', () => {
  it('eats from the bag and equipped slot, including +0 at full HP', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const bag = {
      ...base,
      currentHp: 900,
      inventory: [{ itemId: 'ITEM-0058', quantity: 2 }],
    }
    const healed = eatInventoryFood(launch, bag, 0)
    expect(healed.ok).toBe(true)
    if (!healed.ok) return
    expect(healed.healed).toBe(40)
    expect(healed.save.currentHp).toBe(940)
    expect(healed.save.inventory[0]?.quantity).toBe(1)

    const full = eatInventoryFood(launch, { ...healed.save, currentHp: healed.save.maxHp }, 0)
    expect(full.ok).toBe(true)
    if (!full.ok) return
    expect(full.healed).toBe(0)
    expect(full.save.inventory).toEqual([])

    const equipped = eatEquippedFood(launch, withFoodAndSpells(launch, 2, 0))
    expect(equipped.ok).toBe(true)
    if (!equipped.ok) return
    expect(equipped.healed).toBe(40)
    expect(equipped.save.equipment.slots['SLOT-0011']?.quantity).toBe(1)
  })

  it('refuses to eat during combat', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = {
      ...createNewSave(launch),
      combatEnemyId: 'ENM-0001',
      combatRoundStartedAt: '2026-01-01T00:00:00.000Z',
      inventory: [{ itemId: 'ITEM-0058', quantity: 1 }],
    }
    expect(eatInventoryFood(launch, save, 0).reason).toBe('You cannot eat during combat.')
    expect(
      eatEquippedFood(launch, {
        ...withFoodAndSpells(launch, 2, 0),
        combatEnemyId: 'ENM-0001',
        combatRoundStartedAt: '2026-01-01T00:00:00.000Z',
      }).reason,
    ).toBe('You cannot eat during combat.')
  })

  it('lets one manual eat per combat round when auto-eat is off', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const round = '2026-01-01T00:00:00.000Z'
    const save = {
      ...withFoodAndSpells(launch, 3, 0),
      combatEnemyId: 'ENM-0001',
      combatRoundStartedAt: round,
      settings: { ...withFoodAndSpells(launch, 3, 0).settings, autoEat: false },
    }
    const first = eatEquippedFood(launch, save)
    expect(first.ok).toBe(true)
    if (!first.ok) return
    expect(first.save.combatManualEatRoundStartedAt).toBe(round)
    expect(first.save.equipment.slots['SLOT-0011']?.quantity).toBe(2)

    const second = eatEquippedFood(launch, first.save)
    expect(second.ok).toBe(false)
    expect(second.reason).toBe('Already eaten this round.')

    const nextRound = eatEquippedFood(launch, {
      ...first.save,
      combatRoundStartedAt: '2026-01-01T00:00:04.000Z',
    })
    expect(nextRound.ok).toBe(true)
    if (!nextRound.ok) return
    expect(nextRound.save.equipment.slots['SLOT-0011']?.quantity).toBe(1)
  })

  it('blocks the stage eat chip at full HP unless the food damages', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const healing = withFoodAndSpells(launch, 2, 0)
    expect(stageEatBlockedReason(launch, { ...healing, currentHp: healing.maxHp })).toBe(
      'Already at full health.',
    )
    expect(stageEatBlockedReason(launch, { ...healing, currentHp: 900 })).toBeNull()

    const poison = {
      ...createNewSave(launch),
      currentHp: 99_999,
      equipment: {
        ...createNewSave(launch).equipment,
        slots: {
          ...createNewSave(launch).equipment.slots,
          'SLOT-0011': { itemId: 'ITEM-0028', quantity: 1 },
        },
      },
    }
    expect(stageEatBlockedReason(launch, poison)).toBeNull()
  })

  it('still lets manual eat work outside combat when auto-eat is off', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = {
      ...withFoodAndSpells(launch, 2, 0),
      settings: { ...withFoodAndSpells(launch, 2, 0).settings, autoEat: false },
    }
    const eaten = eatEquippedFood(launch, save)
    expect(eaten.ok).toBe(true)
    if (!eaten.ok) return
    expect(eaten.save.equipment.slots['SLOT-0011']?.quantity).toBe(1)
  })

  it('lets damaging food hurt but never drop below 1 HP', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = {
      ...createNewSave(launch),
      currentHp: 8,
      inventory: [{ itemId: 'ITEM-0028', quantity: 1 }],
    }
    const eaten = eatInventoryFood(launch, save, 0)
    expect(eaten.ok).toBe(true)
    if (!eaten.ok) return
    expect(eaten.healed).toBe(-7)
    expect(eaten.save.currentHp).toBe(1)
  })

  it('does not auto-eat after standard production or a botany harvest', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const hungry = withFoodAndSpells(launch, 4, 0)
    const queued = beginProductionQueue(
      launch,
      addItemToInventory(hungry, 'ITEM-0025', 1),
      'ACT-0017',
      'RCP-0001',
      1,
      Date.parse('2026-01-01T00:00:00.000Z'),
    )
    expect(queued.ok).toBe(true)
    if (!queued.ok) return
    const crafted = completeProductionCraft(
      launch,
      queued.save,
      Date.parse('2026-01-01T00:00:20.000Z'),
      () => 0,
    )
    expect(crafted).not.toBeNull()
    expect(crafted?.save.equipment.slots['SLOT-0011']?.quantity).toBe(4)

    const planted = plantBotanySeed(
      launch,
      {
        ...hungry,
        currentLocationId: 'LOC-0001',
        inventory: [{ itemId: 'ITEM-0324', quantity: 1 }],
        quests: [{ questId: 'QST-0011', status: 'completed', progress: 1 }],
      },
      'ITEM-0324',
      Date.parse('2026-01-01T00:00:00.000Z'),
      1,
    )
    expect(planted.ok).toBe(true)
    if (!planted.ok) return
    const harvested = collectLocationTimer(
      launch,
      planted.save,
      'LOC-0001',
      'botany',
      Date.parse('2026-01-01T03:00:00.000Z'),
      () => 0,
    )
    expect(harvested.ok).toBe(true)
    expect(harvested.ok && harvested.save.equipment.slots['SLOT-0011']?.quantity).toBe(4)
  })
})
