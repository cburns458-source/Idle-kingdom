import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import type { EquippedStack } from '../save/types'
import { consumeFoodBetweenRounds, extraFoodPerRound, tryConsumeFoodAfterVictory } from './food'

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

describe('gluttony food between rounds', () => {
  it('does not eat between rounds without Gluttony', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = withFoodAndSpells(launch, 4, 0)
    expect(extraFoodPerRound(launch, save)).toBe(0)
    const result = consumeFoodBetweenRounds(launch, save)
    expect(result.consumed).toBe(false)
    expect(result.save.equipment.slots['SLOT-0011']?.quantity).toBe(4)
  })

  it('eats once per equipped Gluttony and stops when the stack runs out', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const two = consumeFoodBetweenRounds(launch, withFoodAndSpells(launch, 5, 2))
    expect(two.consumed).toBe(true)
    expect(two.save.equipment.slots['SLOT-0011']?.quantity).toBe(3)

    const empty = consumeFoodBetweenRounds(launch, withFoodAndSpells(launch, 1, 4))
    expect(empty.consumed).toBe(true)
    expect(empty.save.equipment.slots['SLOT-0011']).toBeNull()

    const full = consumeFoodBetweenRounds(launch, {
      ...withFoodAndSpells(launch, 4, 2),
      currentHp: 99_999,
    })
    expect(full.consumed).toBe(false)
    expect(full.save.equipment.slots['SLOT-0011']?.quantity).toBe(4)
  })

  it('still eats once after victory with Gluttony equipped', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = withFoodAndSpells(launch, 4, 2)
    const victory = tryConsumeFoodAfterVictory(launch, save)
    expect(victory.consumed).toBe(true)
    expect(victory.save.equipment.slots['SLOT-0011']?.quantity).toBe(3)
  })
})
