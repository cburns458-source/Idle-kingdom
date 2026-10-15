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
    const starter = { ...createNewSave(launch), title: 'Sir' }
    starter.cosmetics.equipped[TITLE_COSMETIC_SLOT_ID] = STARTER_TITLE_COSMETIC_ID
    expect(edgeChatTitleFromSavePayload(starter, rawDatabase)).toBe('The Undying')
  })
})
