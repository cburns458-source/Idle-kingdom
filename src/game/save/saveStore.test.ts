import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createMemoryStorage } from '../../test/memoryStorage'
import { createNewSave, loadOrCreateSave, readSave, writeSave } from './saveStore'
import {
  RETIRED_COOKED_BABY_GIANT_SQUID_ITEM_ID,
  SAVE_STORAGE_KEY,
  SAVE_VERSION,
  SQUID_NOODLE_SOUP_ITEM_ID,
  STARTING_GOLD,
  STARTING_LOCATION_ID,
  WEAPON_TOOL_SLOT_ID,
} from './types'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('local save', () => {
  it('creates one Town save with gold and no race kit until race is chosen', () => {
    const { source } = prepareDatabase(rawDatabase)
    const save = createNewSave(source)

    expect(save.currentLocationId).toBe(STARTING_LOCATION_ID)
    expect(save.gold).toBe(STARTING_GOLD)
    expect(save.gold).toBe(0)
    expect(save.raceId).toBeNull()
    expect(save.inventory).toEqual([])
    expect(save.equipment.slots[WEAPON_TOOL_SLOT_ID]).toBeNull()
    expect(save.currentActivityId).toBeNull()
    expect(save.skills.length).toBeGreaterThan(0)
    expect(save.skills.every((skill) => skill.level === 1 && skill.xp === 0)).toBe(true)
    expect(save.playTimeMs).toBe(0)
    expect(save.combatSkipEnemyAttack).toBe(false)
    expect(save.combatBossSleepRoundsRemaining).toBeNull()
    expect(save.bossRespawnUntilByEnemyId).toEqual({})
    expect(save.mailbox.some((message) => message.id === 'mail-mailbox-test')).toBe(true)
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
    expect(second.save.gold).toBe(STARTING_GOLD)
  })

  it('persists updates through write/read', () => {
    const storage = createMemoryStorage()
    const { source } = prepareDatabase(rawDatabase)
    const created = createNewSave(source)
    const written = writeSave({ ...created, gold: 0 }, storage)
    const loaded = readSave(storage)

    expect(loaded?.saveVersion).toBe(written.saveVersion)
    expect(loaded?.currentLocationId).toBe(STARTING_LOCATION_ID)
    expect(loaded?.inventory).toEqual([])
    expect(loaded?.raceId).toBeNull()
  })

  it('migrates older saves to playTimeMs 0', () => {
    const storage = createMemoryStorage()
    const { source } = prepareDatabase(rawDatabase)
    const created = createNewSave(source)
    const legacy = { ...created, saveVersion: 29 } as Record<string, unknown>
    delete legacy.playTimeMs
    storage.setItem(SAVE_STORAGE_KEY, JSON.stringify(legacy))

    const loaded = readSave(storage)
    expect(loaded?.saveVersion).toBe(SAVE_VERSION)
    expect(loaded?.playTimeMs).toBe(0)
    expect(loaded?.combatSkipEnemyAttack).toBe(false)
  })

  it('turns leftover cooked squid into soup and defaults auto-eat on', () => {
    const storage = createMemoryStorage()
    const { source } = prepareDatabase(rawDatabase)
    const created = createNewSave(source)
    const legacy = {
      ...created,
      saveVersion: 49,
      inventory: [{ itemId: RETIRED_COOKED_BABY_GIANT_SQUID_ITEM_ID, quantity: 2 }],
      bank: [{ itemId: RETIRED_COOKED_BABY_GIANT_SQUID_ITEM_ID, quantity: 1 }],
      equipment: {
        slots: {
          ...created.equipment.slots,
          'SLOT-0011': { itemId: RETIRED_COOKED_BABY_GIANT_SQUID_ITEM_ID, quantity: 3 },
        },
      },
      settings: { ...created.settings, autoEat: undefined },
    } as Record<string, unknown>
    storage.setItem(SAVE_STORAGE_KEY, JSON.stringify(legacy))

    const loaded = readSave(storage)
    expect(loaded?.saveVersion).toBe(SAVE_VERSION)
    expect(loaded?.inventory).toEqual([{ itemId: SQUID_NOODLE_SOUP_ITEM_ID, quantity: 2 }])
    expect(loaded?.bank).toEqual([{ itemId: SQUID_NOODLE_SOUP_ITEM_ID, quantity: 1 }])
    expect(loaded?.equipment.slots['SLOT-0011']).toEqual({
      itemId: SQUID_NOODLE_SOUP_ITEM_ID,
      quantity: 3,
    })
    expect(loaded?.settings.autoEat).toBe(true)
  })
})
