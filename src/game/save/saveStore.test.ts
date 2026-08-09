import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createMemoryStorage } from '../../test/memoryStorage'
import { createNewSave, loadOrCreateSave, readSave, writeSave } from './saveStore'
import {
  SAVE_STORAGE_KEY,
  STARTING_GOLD,
  STARTING_HUNTING_TOOL_ID,
  STARTING_LOCATION_ID,
  WEAPON_TOOL_SLOT_ID,
} from './types'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

describe('local save', () => {
  it('creates one Town save with starting hunting Net equipped and no gold', () => {
    const { source } = prepareDatabase(rawDatabase)
    const save = createNewSave(source)

    expect(save.currentLocationId).toBe(STARTING_LOCATION_ID)
    expect(save.gold).toBe(STARTING_GOLD)
    expect(save.inventory).toEqual([])
    expect(save.equipment.slots[WEAPON_TOOL_SLOT_ID]).toEqual({
      itemId: STARTING_HUNTING_TOOL_ID,
      quantity: 1,
    })
    expect(save.currentActivityId).toBeNull()
    expect(save.skills.length).toBeGreaterThan(0)
    expect(save.skills.every((skill) => skill.level === 1 && skill.xp === 0)).toBe(true)
  })

  it('auto-creates then reloads the same save', () => {
    const storage = createMemoryStorage()
    const { source } = prepareDatabase(rawDatabase)

    const first = loadOrCreateSave(source, storage)
    expect(first.created).toBe(true)
    expect(storage.getItem(SAVE_STORAGE_KEY)).toBeTruthy()

    const second = loadOrCreateSave(source, storage)
    expect(second.created).toBe(false)
    expect(second.save.createdAt).toBe(first.save.createdAt)
    expect(second.save.currentLocationId).toBe(STARTING_LOCATION_ID)
    expect(second.save.gold).toBe(0)
  })

  it('persists updates through write/read', () => {
    const storage = createMemoryStorage()
    const { source } = prepareDatabase(rawDatabase)
    const created = createNewSave(source)
    const written = writeSave({ ...created, gold: 0 }, storage)
    const loaded = readSave(storage)

    expect(loaded?.saveVersion).toBe(written.saveVersion)
    expect(loaded?.currentLocationId).toBe(STARTING_LOCATION_ID)
    expect(loaded?.equipment.slots[WEAPON_TOOL_SLOT_ID]?.itemId).toBe(STARTING_HUNTING_TOOL_ID)
  })
})
