import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import type { EquippedStack } from '../save/types'
import { consumeFoodAfterVictory, extraFoodPerRound } from './food'

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
