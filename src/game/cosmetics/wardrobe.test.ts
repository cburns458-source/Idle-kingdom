import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { OUTFIT_COSMETIC_SLOT_ID, PET_COSMETIC_SLOT_ID } from '../save/types'
import {
  appearanceSliders,
  cosmeticUnlockNotice,
  wardrobeSlotTabs,
  wardrobeSlotView,
} from './wardrobe'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

const { launch } = prepareDatabase(rawDatabase)

describe('wardrobe view', () => {
  it('tabs the cosmetic slots in table order', () => {
    expect(wardrobeSlotTabs(launch)).toEqual([
      { slotId: OUTFIT_COSMETIC_SLOT_ID, label: 'Outfit' },
      { slotId: PET_COSMETIC_SLOT_ID, label: 'Pet' },
    ])
  })

  it('shows the starter outfit as owned and worn', () => {
    const save = createNewSave(launch)
    const slot = wardrobeSlotView(launch, save, OUTFIT_COSMETIC_SLOT_ID)
    expect(slot?.equippedCosmeticId).toBe('COS-0001')
    expect(slot?.tiles).toEqual([
      { cosmeticId: 'COS-0001', itemId: 'ITEM-0296', name: "Traveler's Tunic", equipped: true },
    ])
  })

  it('lists nothing for a slot the player owns nothing in', () => {
    const save = createNewSave(launch)
    const slot = wardrobeSlotView(launch, save, PET_COSMETIC_SLOT_ID)
    expect(slot?.tiles).toEqual([])
    expect(slot?.emptyNote).toBe('No Pet unlocked yet.')
  })

  it('hides a cosmetic that has not been unlocked', () => {
    const save = createNewSave(launch)
    const locked = { ...save, cosmetics: { unlocked: [], equipped: {} } }
    const slot = wardrobeSlotView(launch, locked, OUTFIT_COSMETIC_SLOT_ID)
    expect(slot?.tiles).toEqual([])
    expect(slot?.equippedCosmeticId).toBeNull()
  })

  it('falls back to the first slot when the slot id is unknown', () => {
    const save = createNewSave(launch)
    expect(wardrobeSlotView(launch, save, 'CSLOT-9999')?.slotId).toBe(OUTFIT_COSMETIC_SLOT_ID)
  })
})

describe('appearance sliders', () => {
  it('gives every category its options and the save selection', () => {
    const save = createNewSave(launch)
    const sliders = appearanceSliders(launch, save.appearance)
    expect(sliders.map((slider) => slider.category)).toEqual([
      'skinTone',
      'hairstyle',
      'hairColor',
      'expression',
      'beard',
      'genderPresentation',
    ])
    const skinTone = sliders[0]!
    expect(skinTone.label).toBe('Skin tone')
    expect(skinTone.optionIds).toEqual(['APR-0001', 'APR-0002', 'APR-0003'])
    expect(skinTone.optionIds[skinTone.selectedIndex]).toBe(save.appearance.skinTone)
  })

  it('points at the selected option after a change', () => {
    const save = createNewSave(launch)
    const changed = { ...save, appearance: { ...save.appearance, skinTone: 'APR-0003' } }
    expect(appearanceSliders(launch, changed.appearance)[0]!.selectedIndex).toBe(2)
  })

  it('falls back to the first stop when the save holds an unknown option', () => {
    const save = createNewSave(launch)
    const stale = { ...save, appearance: { ...save.appearance, hairstyle: 'APR-9999' } }
    const hairstyle = appearanceSliders(launch, stale.appearance)[1]!
    expect(hairstyle.category).toBe('hairstyle')
    expect(hairstyle.selectedIndex).toBe(0)
  })
})

describe('cosmetic unlock notice', () => {
  it('names the cosmetic and adds the hint only for the first one ever', () => {
    expect(cosmeticUnlockNotice(launch, 'COS-0001', true)).toEqual({
      cosmeticId: 'COS-0001',
      itemId: 'ITEM-0296',
      name: "Traveler's Tunic",
      hint: 'Tap your portrait in the top-left corner anytime to open the Wardrobe and equip it.',
    })
    expect(cosmeticUnlockNotice(launch, 'COS-0001', false)?.hint).toBeNull()
  })

  it('has nothing to say about an unknown cosmetic', () => {
    expect(cosmeticUnlockNotice(launch, 'COS-9999', true)).toBeNull()
  })
})
