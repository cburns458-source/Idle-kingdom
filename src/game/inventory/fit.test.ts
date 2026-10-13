import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { INVENTORY_SLOT_LIMIT, INVENTORY_STACK_MAX } from './capacity'
import { noRoomFor, noRoomReason } from './fit'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('noRoomFor', () => {
  const { launch } = prepareDatabase(rawDatabase)

  it('counts an enchanted grant as a new slot even when a plain stack is present', () => {
    const save = {
      ...createNewSave(launch),
      inventory: [
        { itemId: 'ITEM-0100', quantity: 1 },
        ...Array.from({ length: INVENTORY_SLOT_LIMIT - 1 }, (_, index) => ({
          itemId: `FILL-${index}`,
          quantity: 1,
        })),
      ],
    }
    expect(noRoomFor(save, [{ itemId: 'ITEM-0100', quantity: 1 }])).toBeNull()
    expect(
      noRoomFor(save, [{ itemId: 'ITEM-0100', quantity: 1, enchantmentId: 'ENCH-0001' }]),
    ).toEqual({ slotsNeeded: 1, slotsFree: 0 })
  })

  it('returns stack_full with no slot count when only a capped stack blocks the grant', () => {
    const save = {
      ...createNewSave(launch),
      inventory: [{ itemId: 'ITEM-0002', quantity: INVENTORY_STACK_MAX }],
    }
    const blocked = noRoomFor(save, [{ itemId: 'ITEM-0002', quantity: 1 }])
    expect(blocked).toEqual({ reason: 'stack_full' })
    expect(blocked).not.toHaveProperty('slotsNeeded')
    expect(blocked).not.toHaveProperty('slotsFree')
    expect(noRoomReason(blocked!)).toBe('That stack cannot hold more of this item.')
  })

  it('still reports slot counts when the bag is also full', () => {
    const save = {
      ...createNewSave(launch),
      inventory: [
        { itemId: 'ITEM-0002', quantity: INVENTORY_STACK_MAX },
        ...Array.from({ length: INVENTORY_SLOT_LIMIT - 1 }, (_, index) => ({
          itemId: `FILL-${index}`,
          quantity: 1,
        })),
      ],
    }
    expect(noRoomFor(save, [{ itemId: 'ITEM-0002', quantity: 1 }])).toEqual({
      slotsNeeded: 1,
      slotsFree: 0,
    })
  })
})
