import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import type { EquippedStack } from '../save/types'
import {
  consumeFoodAfterVictory,
  eatEquippedFood,
  eatInventoryFood,
  extraFoodPerRound,
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

describe('gluttony food on victory', () => {
  it('counts one extra eat per equipped Gluttony and does not eat between rounds', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(extraFoodPerRound(launch, withFoodAndSpells(launch, 4, 0))).toBe(0)
    expect(extraFoodPerRound(launch, withFoodAndSpells(launch, 4, 2))).toBe(2)
  })

  it('adds one victory eat per Gluttony on top of the usual bite', () => {
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

  it('does not eat healing food at full HP even with Gluttony', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const full = consumeFoodAfterVictory(launch, {
      ...withFoodAndSpells(launch, 4, 2),
      currentHp: 99_999,
    })
    expect(full.consumed).toBe(false)
    expect(full.save.equipment.slots['SLOT-0011']?.quantity).toBe(4)
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
      inventory: [{ itemId: 'ITEM-0058', quantity: 1 }],
    }
    expect(eatInventoryFood(launch, save, 0).reason).toBe('You cannot eat during combat.')
    expect(
      eatEquippedFood(launch, { ...withFoodAndSpells(launch, 2, 0), combatEnemyId: 'ENM-0001' })
        .reason,
    ).toBe('You cannot eat during combat.')
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
})
