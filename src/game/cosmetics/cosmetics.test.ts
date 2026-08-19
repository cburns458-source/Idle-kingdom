import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { OUTFIT_COSMETIC_SLOT_ID, PET_COSMETIC_SLOT_ID, TITLE_COSMETIC_SLOT_ID } from '../save/types'
import {
  cosmeticSlots,
  cosmeticsForSlot,
  equipCosmetic,
  equippedCosmeticId,
  grantCosmetic,
  isCosmeticUnlocked,
} from './cosmetics'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('cosmetics', () => {
  it('lists the data-driven cosmetic slots (Outfit, Pet, Titles)', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const slots = cosmeticSlots(launch).map((row) => row['Cosmetic Slot ID'])
    expect(slots).toEqual([OUTFIT_COSMETIC_SLOT_ID, PET_COSMETIC_SLOT_ID, TITLE_COSMETIC_SLOT_ID])
  })

  it('starts every new save with the starter outfit and Undying title', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    expect(isCosmeticUnlocked(save, 'COS-0001')).toBe(true)
    expect(isCosmeticUnlocked(save, 'COS-0003')).toBe(true)
    expect(equippedCosmeticId(save, OUTFIT_COSMETIC_SLOT_ID)).toBe('COS-0001')
    expect(equippedCosmeticId(save, PET_COSMETIC_SLOT_ID)).toBeNull()
    expect(equippedCosmeticId(save, TITLE_COSMETIC_SLOT_ID)).toBe('COS-0003')
  })

  it('grantCosmetic is idempotent and reports the first-ever unlock', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    // Simulate a blank slate to test "first ever" detection in isolation.
    save = { ...save, cosmetics: { unlocked: [], equipped: {} } }

    const first = grantCosmetic(save, 'COS-0001')
    expect(first.granted).toBe(true)
    expect(first.isFirstEver).toBe(true)
    expect(first.save.cosmetics.unlocked).toEqual(['COS-0001'])

    const second = grantCosmetic(first.save, 'COS-0001')
    expect(second.granted).toBe(false)
    expect(second.isFirstEver).toBe(false)
    expect(second.save.cosmetics.unlocked).toEqual(['COS-0001'])
  })

  it('blocks equipping a Cosmetic that has not been unlocked', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, cosmetics: { unlocked: [], equipped: {} } }
    const result = equipCosmetic(launch, save, OUTFIT_COSMETIC_SLOT_ID, 'COS-0001')
    expect(result.ok).toBe(false)
  })

  it('blocks equipping a Cosmetic into the wrong slot', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const result = equipCosmetic(launch, save, PET_COSMETIC_SLOT_ID, 'COS-0001')
    expect(result.ok).toBe(false)
  })

  it('equips and unequips freely once unlocked (never blocked by capacity)', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const unequipped = equipCosmetic(launch, save, OUTFIT_COSMETIC_SLOT_ID, null)
    expect(unequipped.ok).toBe(true)
    if (!unequipped.ok) return
    expect(equippedCosmeticId(unequipped.save, OUTFIT_COSMETIC_SLOT_ID)).toBeNull()
    // Still owned — re-equipping the same cosmetic still works.
    expect(isCosmeticUnlocked(unequipped.save, 'COS-0001')).toBe(true)
    const reequipped = equipCosmetic(launch, unequipped.save, OUTFIT_COSMETIC_SLOT_ID, 'COS-0001')
    expect(reequipped.ok).toBe(true)
    if (!reequipped.ok) return
    expect(equippedCosmeticId(reequipped.save, OUTFIT_COSMETIC_SLOT_ID)).toBe('COS-0001')
  })

  it('cosmeticsForSlot returns only cosmetics for that slot', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const outfits = cosmeticsForSlot(launch, OUTFIT_COSMETIC_SLOT_ID)
    expect(outfits.some((row) => row['Cosmetic ID'] === 'COS-0001')).toBe(true)
    expect(cosmeticsForSlot(launch, PET_COSMETIC_SLOT_ID)).toEqual([])
  })
})
