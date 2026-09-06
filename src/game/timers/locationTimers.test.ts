import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import {
  canPlaceTrap,
  canPlantBotanySeed,
  collectLocationTimer,
  FISHING_TRAP_ITEM_ID,
  HUNTING_TRAP_ITEM_ID,
  placeTrap,
  plantBotanySeed,
  timerAtLocation,
  timerIsReady,
} from './locationTimers'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('locationTimers', () => {
  it('plants a botany seed in the courtyard after the Grand Feast', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      currentLocationId: 'LOC-0014',
      quests: [{ questId: 'QST-0001', status: 'completed', progress: 1 }],
      inventory: [{ itemId: 'ITEM-0324', quantity: 1 }],
    }
    expect(canPlantBotanySeed(launch, save, 'ITEM-0324').ok).toBe(true)
    const planted = plantBotanySeed(launch, save, 'ITEM-0324', Date.parse('2026-01-01T00:00:00.000Z'))
    expect(planted.ok).toBe(true)
    if (!planted.ok) return
    expect(planted.save.inventory.find((stack) => stack.itemId === 'ITEM-0324')).toBeUndefined()
    const timer = timerAtLocation(planted.save, 'LOC-0014')
    expect(timer?.kind).toBe('botany')
    expect(timer?.outputItemId).toBe('ITEM-0025')
    expect(timerIsReady(timer!, Date.parse('2026-01-01T00:01:00.000Z'))).toBe(false)
    expect(timerIsReady(timer!, Date.parse('2026-01-01T00:03:00.000Z'))).toBe(true)

    const collected = collectLocationTimer(
      launch,
      planted.save,
      'LOC-0014',
      Date.parse('2026-01-01T00:03:00.000Z'),
    )
    expect(collected.ok).toBe(true)
    if (!collected.ok) return
    expect(collected.loot.some((row) => row.itemId === 'ITEM-0025')).toBe(true)
    expect(timerAtLocation(collected.save, 'LOC-0014')).toBeUndefined()
  })

  it('places and collects a hunting trap in the Kingswoods', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      currentLocationId: 'LOC-0008',
      inventory: [{ itemId: HUNTING_TRAP_ITEM_ID, quantity: 1 }],
    }
    expect(canPlaceTrap(launch, save, HUNTING_TRAP_ITEM_ID).ok).toBe(true)
    expect(canPlaceTrap(launch, save, FISHING_TRAP_ITEM_ID).ok).toBe(false)
    const placed = placeTrap(launch, save, HUNTING_TRAP_ITEM_ID, Date.parse('2026-01-01T00:00:00.000Z'))
    expect(placed.ok).toBe(true)
    if (!placed.ok) return
    const collected = collectLocationTimer(
      launch,
      placed.save,
      'LOC-0008',
      Date.parse('2026-01-01T00:06:00.000Z'),
      () => 0,
    )
    expect(collected.ok).toBe(true)
    if (!collected.ok) return
    expect(collected.loot.length).toBeGreaterThan(0)
    expect(
      collected.save.inventory.find((stack) => stack.itemId === HUNTING_TRAP_ITEM_ID)?.quantity,
    ).toBe(1)
  })
})
