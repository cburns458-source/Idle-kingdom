import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import {
  BOTANY_PATCH_LOCATIONS,
  canPlaceTrap,
  canPlantBotanySeed,
  collectLocationTimer,
  discoverTimerSpotsForLocation,
  FISHING_POT_ITEM_ID,
  locationHasBotanyPatch,
  parseTimerSpotKey,
  placeTrap,
  plantBotanySeed,
  timerAtLocation,
  timerAtLocationKind,
  timerIsReady,
  timerSpotKey,
} from './locationTimers'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('locationTimers', () => {
  it('builds and parses timer spot keys', () => {
    expect(timerSpotKey('botany', 'LOC-0001')).toBe('botany:LOC-0001')
    expect(timerSpotKey('fishing_pot', 'LOC-0003')).toBe('fishing_pot:LOC-0003')
    expect(parseTimerSpotKey('botany:LOC-0001')).toEqual({
      kind: 'botany',
      locationId: 'LOC-0001',
    })
    expect(parseTimerSpotKey('hunting_trap:LOC-0009')).toBeNull()
    expect(parseTimerSpotKey('')).toBeNull()
    expect(parseTimerSpotKey('botany')).toBeNull()
    expect(parseTimerSpotKey('botany:')).toBeNull()
    expect(parseTimerSpotKey(':LOC-0001')).toBeNull()
    expect(parseTimerSpotKey('unknown:LOC-0001')).toBeNull()
  })

  it('discovers botany and fishing pot spots for a location without duplicates', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    expect(save.discoveredTimerSpotIds).toEqual([])

    save = discoverTimerSpotsForLocation(save, 'LOC-0001')
    expect(save.discoveredTimerSpotIds).toEqual(['botany:LOC-0001'])
    expect(discoverTimerSpotsForLocation(save, 'LOC-0001')).toBe(save)

    save = discoverTimerSpotsForLocation(save, 'LOC-0008')
    expect(save.discoveredTimerSpotIds).toEqual(['botany:LOC-0001'])
    expect(discoverTimerSpotsForLocation(save, 'LOC-0008')).toBe(save)

    save = discoverTimerSpotsForLocation(save, 'LOC-0009')
    expect(save.discoveredTimerSpotIds).toContain('botany:LOC-0009')
    expect(save.discoveredTimerSpotIds).not.toContain('hunting_trap:LOC-0009')

    save = discoverTimerSpotsForLocation(save, 'LOC-0003')
    expect(save.discoveredTimerSpotIds).toContain('fishing_pot:LOC-0003')

    expect(discoverTimerSpotsForLocation(save, 'LOC-9999')).toBe(save)
  })

  it('records discovery when planting or placing', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      currentLocationId: 'LOC-0001',
      inventory: [{ itemId: 'ITEM-0324', quantity: 3 }],
    }
    const planted = plantBotanySeed(
      launch,
      save,
      'ITEM-0324',
      Date.parse('2026-01-01T00:00:00.000Z'),
      3,
    )
    expect(planted.ok).toBe(true)
    if (!planted.ok) return
    expect(planted.save.discoveredTimerSpotIds).toContain('botany:LOC-0001')

    save = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0003',
      skills: createNewSave(launch).skills.map((row) =>
        row.skillId === 'SKL-0003' ? { ...row, level: 50, xp: 848633 } : row,
      ),
      inventory: [{ itemId: FISHING_POT_ITEM_ID, quantity: 1 }],
    }
    const placed = placeTrap(launch, save, FISHING_POT_ITEM_ID, Date.parse('2026-01-01T00:00:00.000Z'))
    expect(placed.ok).toBe(true)
    if (!placed.ok) return
    expect(placed.save.discoveredTimerSpotIds).toContain('fishing_pot:LOC-0003')
  })

  it('allows botany patches at multi-location set, with courtyard Grand Feast gate', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    expect(locationHasBotanyPatch('LOC-0001')).toBe(true)
    expect(locationHasBotanyPatch('LOC-0031')).toBe(true)
    expect(BOTANY_PATCH_LOCATIONS.has('LOC-0043')).toBe(true)
    expect(locationHasBotanyPatch('LOC-0008')).toBe(false)

    save = {
      ...save,
      currentLocationId: 'LOC-0014',
      inventory: [{ itemId: 'ITEM-0324', quantity: 3 }],
    }
    expect(canPlantBotanySeed(launch, save, 'ITEM-0324').ok).toBe(false)

    save = {
      ...save,
      quests: [{ questId: 'QST-0001', status: 'completed', progress: 1 }],
    }
    expect(canPlantBotanySeed(launch, save, 'ITEM-0324').ok).toBe(true)
  })

  it('plants up to 3 seeds (or 1 sapling) and rolls harvest 1-5 plus 50% seed return', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      currentLocationId: 'LOC-0001',
      inventory: [{ itemId: 'ITEM-0324', quantity: 5 }],
    }
    const gate = canPlantBotanySeed(launch, save, 'ITEM-0324', 'LOC-0001', 5)
    expect(gate.ok).toBe(true)
    if (!gate.ok) return
    expect(gate.quantity).toBe(3)

    const planted = plantBotanySeed(
      launch,
      save,
      'ITEM-0324',
      Date.parse('2026-01-01T00:00:00.000Z'),
      5,
    )
    expect(planted.ok).toBe(true)
    if (!planted.ok) return
    expect(planted.save.inventory.find((stack) => stack.itemId === 'ITEM-0324')?.quantity).toBe(2)
    const timer = timerAtLocation(planted.save, 'LOC-0001')
    expect(timer?.kind).toBe('botany')
    expect(timer?.outputItemId).toBe('ITEM-0025')
    expect(timer?.outputQuantity).toBe(3)
    expect(timerIsReady(timer!, Date.parse('2026-01-01T01:00:00.000Z'))).toBe(false)
    expect(timerIsReady(timer!, Date.parse('2026-01-01T03:00:00.000Z'))).toBe(true)

    // Produce rolls first (3x), then seed-return rolls (3x).
    const rolls = [0, 0, 0, 0.99, 0.99, 0.99]
    let i = 0
    const collected = collectLocationTimer(
      launch,
      planted.save,
      'LOC-0001',
      'botany',
      Date.parse('2026-01-01T03:00:00.000Z'),
      () => rolls[i++] ?? 0,
    )
    expect(collected.ok).toBe(true)
    if (!collected.ok) return
    const produce = collected.loot.find((row) => row.itemId === 'ITEM-0025')
    expect(produce?.quantity).toBe(3)
    expect(collected.loot.some((row) => row.itemId === 'ITEM-0324')).toBe(false)
    expect(
      collected.save.inventory.find((stack) => stack.itemId === 'ITEM-0025')?.quantity,
    ).toBe(3)
    expect(timerAtLocation(collected.save, 'LOC-0001')).toBeUndefined()
    expect(timerAtLocationKind(collected.save, 'LOC-0001', 'botany')).toBeUndefined()
  })

  it('restricts The Shallows to kelp-only plantables', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      currentLocationId: 'LOC-0043',
      skills: save.skills.map((row) =>
        row.skillId === 'SKL-0014' ? { ...row, level: 40, xp: 0 } : row,
      ),
      inventory: [
        { itemId: 'ITEM-0324', quantity: 1 },
        { itemId: 'ITEM-0350', quantity: 1 },
      ],
    }
    expect(canPlantBotanySeed(launch, save, 'ITEM-0324').ok).toBe(false)
    expect(canPlantBotanySeed(launch, save, 'ITEM-0350').ok).toBe(true)

    save = { ...save, currentLocationId: 'LOC-0001' }
    expect(canPlantBotanySeed(launch, save, 'ITEM-0350').ok).toBe(false)
  })

  it('places fishing pots once per UTC day and rolls 6-12 level-gated fish', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const dayStart = Date.parse('2026-03-01T12:00:00.000Z')
    let save = createNewSave(launch)
    save = {
      ...save,
      currentLocationId: 'LOC-0003',
      skills: save.skills.map((row) =>
        row.skillId === 'SKL-0003' ? { ...row, level: 50, xp: 848633 } : row,
      ),
      inventory: [{ itemId: FISHING_POT_ITEM_ID, quantity: 2 }],
    }
    expect(canPlaceTrap(launch, save, FISHING_POT_ITEM_ID, 'LOC-0003', dayStart).ok).toBe(true)
    const placed = placeTrap(launch, save, FISHING_POT_ITEM_ID, dayStart)
    expect(placed.ok).toBe(true)
    if (!placed.ok) return
    expect(placed.save.fishingPotDayKeyByLocationId['LOC-0003']).toBe('2026-03-01')
    expect(timerAtLocationKind(placed.save, 'LOC-0003', 'fishing_pot')?.kind).toBe('fishing_pot')

    const collected = collectLocationTimer(
      launch,
      placed.save,
      'LOC-0003',
      'fishing_pot',
      Date.parse('2026-03-01T18:00:00.000Z'),
      () => 0,
    )
    expect(collected.ok).toBe(true)
    if (!collected.ok) return
    expect(collected.loot.some((row) => row.itemId === 'ITEM-0352')).toBe(true)
    const qty = collected.loot.find((row) => row.itemId === 'ITEM-0352')?.quantity ?? 0
    expect(qty).toBeGreaterThanOrEqual(6)
    expect(qty).toBeLessThanOrEqual(12)
    expect(
      collected.save.inventory.find((stack) => stack.itemId === FISHING_POT_ITEM_ID)?.quantity,
    ).toBe(2)

    const blocked = canPlaceTrap(launch, collected.save, FISHING_POT_ITEM_ID, 'LOC-0003', dayStart)
    expect(blocked.ok).toBe(false)
    if (blocked.ok) return
    expect(blocked.reason.toLowerCase()).toContain('overfish')

    const nextDay = Date.parse('2026-03-02T00:00:00.000Z')
    expect(canPlaceTrap(launch, collected.save, FISHING_POT_ITEM_ID, 'LOC-0003', nextDay).ok).toBe(
      true,
    )
  })

  it('blocks dock pots until Fishing 35 and goblin pots until Fishing 14', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      currentLocationId: 'LOC-0004',
      inventory: [{ itemId: FISHING_POT_ITEM_ID, quantity: 1 }],
    }
    const docks = canPlaceTrap(launch, save, FISHING_POT_ITEM_ID)
    expect(docks.ok).toBe(false)
    if (docks.ok) return
    expect(docks.reason).toContain('35')

    save = {
      ...save,
      currentLocationId: 'LOC-0003',
      skills: save.skills.map((row) =>
        row.skillId === 'SKL-0003' ? { ...row, level: 10, xp: 10873 } : row,
      ),
    }
    const goblin = canPlaceTrap(launch, save, FISHING_POT_ITEM_ID)
    expect(goblin.ok).toBe(false)
    if (goblin.ok) return
    expect(goblin.reason).toContain('14')
  })
})
