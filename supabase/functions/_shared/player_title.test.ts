import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

import { prepareDatabase } from '../../../src/game/data/loadDatabase.ts'
import { createNewSave } from '../../../src/game/save/saveStore.ts'
import { chatTitleForSave, chatTitleFromSavePayload } from '../../../src/game/save/playerTitle.ts'
import { STARTER_TITLE_COSMETIC_ID, TITLE_COSMETIC_SLOT_ID } from '../../../src/game/save/types.ts'
import { chatTitleFromSavePayload as edgeChatTitleFromSavePayload } from './player_title.ts'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('chatTitleFromSavePayload', () => {
  const { launch } = prepareDatabase(rawDatabase)

  it('agrees with titleForSave and leaves junk or missing payloads untitled', () => {
    const save = createNewSave(launch)
    expect(edgeChatTitleFromSavePayload(save, rawDatabase)).toBe('The Undying')
    expect(edgeChatTitleFromSavePayload(save, rawDatabase)).toBe(chatTitleForSave(save, launch))
    expect(edgeChatTitleFromSavePayload(null, rawDatabase)).toBeNull()
    expect(edgeChatTitleFromSavePayload('The Undying', rawDatabase)).toBeNull()
    expect(edgeChatTitleFromSavePayload({ characterName: 'vari' }, rawDatabase)).toBe('The Undying')
  })

  it('drops The Undying after death or when the slot is empty', () => {
    const dead = { ...createNewSave(launch), hasEverDied: true }
    expect(edgeChatTitleFromSavePayload(dead, rawDatabase)).toBeNull()
    expect(edgeChatTitleFromSavePayload(dead, rawDatabase)).toBe(chatTitleForSave(dead, launch))

    const unequipped = createNewSave(launch)
    unequipped.cosmetics.equipped[TITLE_COSMETIC_SLOT_ID] = null
    expect(edgeChatTitleFromSavePayload(unequipped, rawDatabase)).toBeNull()
    expect(chatTitleFromSavePayload(unequipped, launch)).toBeNull()
  })

  it('resolves an equipped faith title from the catalog', () => {
    const save = createNewSave(launch)
    save.cosmetics.unlocked.push('COS-0013')
    save.cosmetics.equipped[TITLE_COSMETIC_SLOT_ID] = 'COS-0013'
    expect(edgeChatTitleFromSavePayload(save, rawDatabase)).toBe('Oruvani')
    expect(edgeChatTitleFromSavePayload(save, rawDatabase)).toBe(chatTitleForSave(save, launch))
    expect(edgeChatTitleFromSavePayload(save)).toBeNull()
  })

  it('keeps a faith title after death and ignores a client-supplied title field', () => {
    const save = {
      ...createNewSave(launch),
      hasEverDied: true,
      title: 'Sir',
    }
    save.cosmetics.unlocked.push('COS-0013')
    save.cosmetics.equipped[TITLE_COSMETIC_SLOT_ID] = 'COS-0013'
    expect(edgeChatTitleFromSavePayload(save, rawDatabase)).toBe('Oruvani')
    expect(edgeChatTitleFromSavePayload(save, rawDatabase)).not.toBe('Sir')
    const starter = { ...createNewSave(launch), title: 'Sir' }
    starter.cosmetics.equipped[TITLE_COSMETIC_SLOT_ID] = STARTER_TITLE_COSMETIC_ID
    expect(edgeChatTitleFromSavePayload(starter, rawDatabase)).toBe('The Undying')
    expect(edgeChatTitleFromSavePayload(starter, rawDatabase)).not.toBe('Sir')
  })

  it('resolves every prefix faith title (cosmetic_faith_*_title) from the catalog', () => {
    const faithTitles = [
      { cosmeticId: 'COS-0013', text: 'Oruvani', key: 'cosmetic_faith_vaelithra_title' },
      { cosmeticId: 'COS-0014', text: 'Khareth', key: 'cosmetic_faith_khavessa_title' },
      { cosmeticId: 'COS-0015', text: 'Nymorathen', key: 'cosmetic_faith_nymorai_title' },
      { cosmeticId: 'COS-0016', text: 'Drazhari', key: 'cosmetic_faith_drazhkar_title' },
      { cosmeticId: 'COS-0017', text: 'Veyrathel', key: 'cosmetic_faith_veyrathi_title' },
      { cosmeticId: 'COS-0018', text: 'Korvathi', key: 'cosmetic_faith_korvethan_title' },
      { cosmeticId: 'COS-0019', text: 'Elyndri', key: 'cosmetic_faith_elyndara_title' },
    ] as const
    for (const { cosmeticId, text, key } of faithTitles) {
      const cosmetic = launch.Cosmetics.find((row) => row['Cosmetic ID'] === cosmeticId)
      expect(cosmetic?.['Title Placement'], cosmeticId).toBe('prefix')
      const item = launch.Items.find((row) => row['Item ID'] === cosmetic?.['Item ID'])
      expect(item?.['Internal Key'], cosmeticId).toBe(key)
      const save = createNewSave(launch)
      save.cosmetics.unlocked.push(cosmeticId)
      save.cosmetics.equipped[TITLE_COSMETIC_SLOT_ID] = cosmeticId
      expect(edgeChatTitleFromSavePayload({ ...save, title: 'Sir' }, rawDatabase)).toBe(text)
    }
  })
})
