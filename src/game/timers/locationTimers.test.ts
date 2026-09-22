import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import {
  BOTANY_PATCH_LOCATIONS,
  botanySuccessChancePercent,
  canPlaceTrap,
  canPlantBotanySeed,
  collectLocationTimer,
  CARROT_SEED_ITEM_ID,
  COMPOST_ITEM_ID,
  compostCollectActivityAt,
  ELDER_BERRY_SEED_ITEM_ID,
  GRAPE_SEED_ITEM_ID,
  locationHasCompostCollect,
  MOONBLOSSOM_SEED_ITEM_ID,
  parseBotanySeedSpec,
  POTATO_SEED_ITEM_ID,
  rollReturnedBotanySeed,
  TURNIP_SEED_ITEM_ID,
  discoverTimerSpotsForLocation,
  FISHING_POT_ITEM_ID,
  TIMER_INVENTORY_FULL_CATCH_REASON,
  TIMER_INVENTORY_FULL_HARVEST_REASON,
  locationHasBotanyPatch,
  parseTimerSpotKey,
  placeTrap,
  farmBotanyUnlocked,
  plantBotanySeed,
  plantBotanySelection,
  potBaitOptionsForLocation,
  timerAtLocation,
  timerAtLocationKind,
  timerIsReady,
  timerSpotKey,
} from './locationTimers'
import { getSkillProgress } from '../activity/xp'

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
    expect(save.discoveredTimerSpotIds).toEqual([])

    save = {
      ...save,
      quests: [{ questId: 'QST-0011', status: 'completed', progress: 1 }],
    }
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
      quests: [{ questId: 'QST-0011', status: 'completed', progress: 1 }],
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
      quests: [{ questId: 'QST-0011', status: 'completed', progress: 1 }],
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

    // Success (3x), produce (3x), then seed-return (3x).
    const rolls = [0, 0, 0, 0, 0, 0, 0.99, 0.99, 0.99]
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

    save = {
      ...save,
      currentLocationId: 'LOC-0001',
      quests: [{ questId: 'QST-0011', status: 'completed', progress: 1 }],
    }
    expect(canPlantBotanySeed(launch, save, 'ITEM-0350').ok).toBe(false)
  })

  it('places fishing pots once per UTC day and rolls 3-6 fish per bait slot', () => {
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
    expect(timerAtLocationKind(placed.save, 'LOC-0003', 'fishing_pot')?.baitItemIds).toBeUndefined()

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
    expect(collected.loot.map((row) => row.itemId)).toEqual(['ITEM-0352', FISHING_POT_ITEM_ID])
    expect(collected.loot.find((row) => row.itemId === 'ITEM-0352')?.quantity).toBe(9)
    expect(collected.xpGained).toBe(4050)
    expect(collected.bonusXp).toEqual([{ skillId: 'SKL-0005', xp: 4050 }])
    expect(getSkillProgress(collected.save, 'SKL-0003').xp).toBe(
      getSkillProgress(placed.save, 'SKL-0003').xp + 4050,
    )
    expect(getSkillProgress(collected.save, 'SKL-0005').xp).toBe(
      getSkillProgress(placed.save, 'SKL-0005').xp + 4050,
    )
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

  it('baits pots by overall fishing level and awards matching hunter XP', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const dayStart = Date.parse('2026-03-01T12:00:00.000Z')
    const base = createNewSave(launch)
    const camp = {
      ...base,
      currentLocationId: 'LOC-0003',
      skills: base.skills.map((row) =>
        row.skillId === 'SKL-0003' ? { ...row, level: 75, xp: 0 } : row,
      ),
      inventory: [
        { itemId: FISHING_POT_ITEM_ID, quantity: 1 },
        { itemId: 'ITEM-0047', quantity: 3 },
        { itemId: 'ITEM-0048', quantity: 3 },
        { itemId: 'ITEM-0191', quantity: 3 },
      ],
    }
    const campBait = potBaitOptionsForLocation(launch, camp, 'LOC-0003').map((row) => row.itemId)
    expect(campBait).toEqual(['ITEM-0047', 'ITEM-0049', 'ITEM-0051'])
    expect(placeTrap(launch, camp, FISHING_POT_ITEM_ID, dayStart, ['ITEM-0048', 'ITEM-0048', 'ITEM-0048']).ok).toBe(
      false,
    )
    expect(placeTrap(launch, camp, FISHING_POT_ITEM_ID, dayStart, ['ITEM-0047']).ok).toBe(false)

    const baited = placeTrap(launch, camp, FISHING_POT_ITEM_ID, dayStart, [
      'ITEM-0047',
      'ITEM-0047',
      'ITEM-0047',
    ])
    expect(baited.ok).toBe(true)
    if (!baited.ok) return
    expect(baited.save.inventory.find((stack) => stack.itemId === 'ITEM-0047')).toBeUndefined()
    expect(timerAtLocationKind(baited.save, 'LOC-0003', 'fishing_pot')?.baitItemIds).toEqual([
      'ITEM-0047',
      'ITEM-0047',
      'ITEM-0047',
    ])

    const haul = collectLocationTimer(
      launch,
      baited.save,
      'LOC-0003',
      'fishing_pot',
      Date.parse('2026-03-01T18:00:00.000Z'),
      () => 0,
    )
    expect(haul.ok).toBe(true)
    if (!haul.ok) return
    expect(haul.loot.find((row) => row.itemId === 'ITEM-0352')?.quantity).toBe(9)
    expect(haul.xpGained).toBe(4050)
    expect(haul.bonusXp).toEqual([{ skillId: 'SKL-0005', xp: 4050 }])

    const docks = {
      ...base,
      currentLocationId: 'LOC-0004',
      skills: base.skills.map((row) =>
        row.skillId === 'SKL-0003' ? { ...row, level: 75, xp: 0 } : row,
      ),
      inventory: [
        { itemId: FISHING_POT_ITEM_ID, quantity: 1 },
        { itemId: 'ITEM-0191', quantity: 3 },
      ],
    }
    expect(potBaitOptionsForLocation(launch, docks, 'LOC-0004').map((row) => row.itemId)).toEqual([
      'ITEM-0048',
      'ITEM-0050',
      'ITEM-0191',
    ])
    const lobsterPot = placeTrap(launch, docks, FISHING_POT_ITEM_ID, dayStart, [
      'ITEM-0191',
      'ITEM-0191',
      'ITEM-0191',
    ])
    expect(lobsterPot.ok).toBe(true)
    if (!lobsterPot.ok) return
    const lobster = collectLocationTimer(
      launch,
      lobsterPot.save,
      'LOC-0004',
      'fishing_pot',
      Date.parse('2026-03-01T18:00:00.000Z'),
      () => 0,
    )
    expect(lobster.ok).toBe(true)
    if (!lobster.ok) return
    expect(lobster.loot.find((row) => row.itemId === 'ITEM-0357')?.quantity).toBe(9)
    expect(lobster.xpGained).toBe(17550)
    expect(lobster.bonusXp).toEqual([{ skillId: 'SKL-0005', xp: 17550 }])
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

  it('leaves a ready timer in place when the bag cannot hold the haul', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const planted = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0001',
      inventory: Array.from({ length: 180 }, (_, index) => ({
        itemId: `FILL-${index}`,
        quantity: 1,
      })),
      locationTimers: [
        {
          locationId: 'LOC-0001',
          kind: 'botany' as const,
          inputItemId: 'ITEM-0324',
          outputItemId: 'ITEM-0025',
          outputQuantity: 1,
          skillId: 'SKL-0014',
          xpReward: 10,
          startedAt: '2026-01-01T00:00:00.000Z',
          durationMs: 1,
        },
      ],
    }
    const collected = collectLocationTimer(
      launch,
      planted,
      'LOC-0001',
      'botany',
      Date.parse('2026-01-01T01:00:00.000Z'),
      () => 0,
    )
    expect(collected.ok).toBe(false)
    if (collected.ok) return
    expect(collected.reason).toBe(TIMER_INVENTORY_FULL_HARVEST_REASON)
    expect(timerAtLocationKind(planted, 'LOC-0001', 'botany')).toBeTruthy()
    expect(planted.inventory).toHaveLength(180)
  })

  it('asks for room to collect a catch when a pot haul will not fit', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const soaked = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0003',
      skills: createNewSave(launch).skills.map((row) =>
        row.skillId === 'SKL-0003' ? { ...row, level: 14, xp: 2000 } : row,
      ),
      inventory: Array.from({ length: 180 }, (_, index) => ({
        itemId: `FILL-${index}`,
        quantity: 1,
      })),
      locationTimers: [
        {
          locationId: 'LOC-0003',
          kind: 'fishing_pot' as const,
          inputItemId: FISHING_POT_ITEM_ID,
          outputItemId: null,
          outputQuantity: 1,
          skillId: 'SKL-0003',
          xpReward: 150,
          startedAt: '2026-01-01T00:00:00.000Z',
          durationMs: 1,
        },
      ],
    }
    const collected = collectLocationTimer(
      launch,
      soaked,
      'LOC-0003',
      'fishing_pot',
      Date.parse('2026-01-01T08:00:00.000Z'),
      () => 0,
    )
    expect(collected.ok).toBe(false)
    if (collected.ok) return
    expect(collected.reason).toBe(TIMER_INVENTORY_FULL_CATCH_REASON)
    expect(timerAtLocationKind(soaked, 'LOC-0003', 'fishing_pot')).toBeTruthy()
  })

  it('hides the farm patch until Fennel is heard or First Planting is complete', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0001',
      inventory: [{ itemId: 'ITEM-0324', quantity: 2 }],
    }
    expect(farmBotanyUnlocked(save)).toBe(false)
    expect(canPlantBotanySeed(launch, save, 'ITEM-0324').ok).toBe(false)

    save = {
      ...save,
      quests: [
        {
          questId: 'QST-0011',
          status: 'active',
          progress: 1,
          counters: { 'talk:NPC-0014': 1 },
        },
      ],
    }
    expect(farmBotanyUnlocked(save)).toBe(true)
    expect(canPlantBotanySeed(launch, save, 'ITEM-0324', 'LOC-0001', 2).ok).toBe(true)
  })

  it('plants mixed seed types on one patch and harvests each crop', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0031',
      skills: createNewSave(launch).skills.map((row) =>
        row.skillId === 'SKL-0014' ? { ...row, level: 10, xp: 0 } : row,
      ),
      inventory: [
        { itemId: 'ITEM-0324', quantity: 1 },
        { itemId: 'ITEM-0339', quantity: 2 },
      ],
    }
    const planted = plantBotanySelection(launch, save, ['ITEM-0324', 'ITEM-0339'], 0)
    expect(planted.ok).toBe(true)
    if (!planted.ok) return
    expect(planted.save.inventory.find((stack) => stack.itemId === 'ITEM-0324')).toBeUndefined()
    expect(planted.save.inventory.find((stack) => stack.itemId === 'ITEM-0339')?.quantity).toBe(1)
    const timer = timerAtLocationKind(planted.save, 'LOC-0031', 'botany')
    expect(timer?.plantedItemIds).toEqual(['ITEM-0324', 'ITEM-0339'])
    expect(timer?.outputQuantity).toBe(2)
    expect(timer?.xpReward).toBe(1600)

    const rolls = [0, 0, 0, 0, 0.99, 0.99]
    let i = 0
    const collected = collectLocationTimer(
      launch,
      planted.save,
      'LOC-0031',
      'botany',
      10800 * 1000,
      () => rolls[i++] ?? 0,
    )
    expect(collected.ok).toBe(true)
    if (!collected.ok) return
    expect(collected.loot.find((row) => row.itemId === 'ITEM-0025')?.quantity).toBe(1)
    expect(collected.loot.find((row) => row.itemId === 'ITEM-0027')?.quantity).toBe(1)
    expect(collected.loot.some((row) => row.itemId === 'ITEM-0324')).toBe(false)
    expect(collected.loot.some((row) => row.itemId === 'ITEM-0339')).toBe(false)
  })

  it('splits returned seeds by planted pool, not plant order', () => {
    const planted = [POTATO_SEED_ITEM_ID, CARROT_SEED_ITEM_ID, GRAPE_SEED_ITEM_ID]
    expect(rollReturnedBotanySeed(planted, POTATO_SEED_ITEM_ID, () => 0.0)).toBe(POTATO_SEED_ITEM_ID)
    expect(rollReturnedBotanySeed(planted, POTATO_SEED_ITEM_ID, () => 0.49)).toBe(
      POTATO_SEED_ITEM_ID,
    )
    expect(rollReturnedBotanySeed(planted, POTATO_SEED_ITEM_ID, () => 0.5)).toBe(TURNIP_SEED_ITEM_ID)
    expect(rollReturnedBotanySeed(planted, POTATO_SEED_ITEM_ID, () => 0.74)).toBe(TURNIP_SEED_ITEM_ID)
    expect(rollReturnedBotanySeed(planted, POTATO_SEED_ITEM_ID, () => 0.75)).toBe(
      ELDER_BERRY_SEED_ITEM_ID,
    )
    expect(rollReturnedBotanySeed(planted, GRAPE_SEED_ITEM_ID, () => 0.5)).toBe(
      ELDER_BERRY_SEED_ITEM_ID,
    )
    expect(rollReturnedBotanySeed(planted, CARROT_SEED_ITEM_ID, () => 0.5)).toBe(TURNIP_SEED_ITEM_ID)

    const twoPotato = [POTATO_SEED_ITEM_ID, POTATO_SEED_ITEM_ID, CARROT_SEED_ITEM_ID]
    expect(rollReturnedBotanySeed(twoPotato, POTATO_SEED_ITEM_ID, () => 0.5)).toBe(
      TURNIP_SEED_ITEM_ID,
    )
    expect(rollReturnedBotanySeed(twoPotato, CARROT_SEED_ITEM_ID, () => 0.5)).toBe(
      TURNIP_SEED_ITEM_ID,
    )
    expect(rollReturnedBotanySeed([POTATO_SEED_ITEM_ID], POTATO_SEED_ITEM_ID, () => 0.9)).toBe(
      POTATO_SEED_ITEM_ID,
    )
  })

  it('returns mutated seeds on a mixed harvest when the return roll succeeds', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      currentLocationId: 'LOC-0031',
      skills: save.skills.map((row) =>
        row.skillId === 'SKL-0014' ? { ...row, level: 55, xp: 0 } : row,
      ),
      inventory: [
        { itemId: POTATO_SEED_ITEM_ID, quantity: 1 },
        { itemId: CARROT_SEED_ITEM_ID, quantity: 1 },
        { itemId: GRAPE_SEED_ITEM_ID, quantity: 1 },
      ],
    }
    const planted = plantBotanySelection(launch, save, [
      POTATO_SEED_ITEM_ID,
      CARROT_SEED_ITEM_ID,
      GRAPE_SEED_ITEM_ID,
    ], 0)
    expect(planted.ok).toBe(true)
    if (!planted.ok) return
    // 3 successes, 3 produce rolls, 3 successful returns, then potato/grape/carrot mutations.
    const rolls = [0, 0, 0, 0, 0, 0, 0, 0.6, 0, 0.6, 0, 0.6]
    let i = 0
    const collected = collectLocationTimer(
      launch,
      planted.save,
      'LOC-0031',
      'botany',
      10800 * 1000,
      () => rolls[i++] ?? 0,
    )
    expect(collected.ok).toBe(true)
    if (!collected.ok) return
    expect(collected.loot.find((row) => row.itemId === TURNIP_SEED_ITEM_ID)?.quantity).toBe(2)
    expect(collected.loot.find((row) => row.itemId === ELDER_BERRY_SEED_ITEM_ID)?.quantity).toBe(1)
    expect(collected.loot.some((row) => row.itemId === POTATO_SEED_ITEM_ID)).toBe(false)
  })

  it('lets moonblossom seeds plant at botany 70', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(parseBotanySeedSpec(launch, MOONBLOSSOM_SEED_ITEM_ID)?.requiresLevel).toBe(70)
    expect(parseBotanySeedSpec(launch, TURNIP_SEED_ITEM_ID)?.xp).toBe(6000)
    expect(parseBotanySeedSpec(launch, TURNIP_SEED_ITEM_ID)?.requiresLevel).toBe(27)
  })

  it('computes live-plant chance from level, requirement, and compost', () => {
    expect(botanySuccessChancePercent(1, 1)).toBe(25.5)
    expect(botanySuccessChancePercent(10, 1)).toBe(34.5)
    expect(botanySuccessChancePercent(10, 10)).toBe(30)
    expect(botanySuccessChancePercent(10, 10, true)).toBe(55)
    expect(botanySuccessChancePercent(200, 1, true)).toBe(100)
  })

  it('offers compost collect at every botany patch except The Shallows', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(locationHasCompostCollect('LOC-0001')).toBe(true)
    expect(locationHasCompostCollect('LOC-0043')).toBe(false)
    expect(locationHasCompostCollect('LOC-0002')).toBe(false)
    expect(compostCollectActivityAt(launch, 'LOC-0001')?.['Activity ID']).toBe('ACT-0062')
    expect(compostCollectActivityAt(launch, 'LOC-0043')).toBeUndefined()
    expect(launch.Items.some((item) => item['Item ID'] === COMPOST_ITEM_ID)).toBe(true)
  })

  it('spends compost when planting and only awards lived plants', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0031',
      skills: createNewSave(launch).skills.map((row) =>
        row.skillId === 'SKL-0014' ? { ...row, level: 1, xp: 0 } : row,
      ),
      inventory: [
        { itemId: POTATO_SEED_ITEM_ID, quantity: 2 },
        { itemId: COMPOST_ITEM_ID, quantity: 3 },
      ],
    }
    const refused = plantBotanySelection(launch, save, [POTATO_SEED_ITEM_ID], 0, true)
    expect(refused.ok).toBe(true)
    if (!refused.ok) return
    expect(refused.save.inventory.find((stack) => stack.itemId === COMPOST_ITEM_ID)?.quantity).toBe(2)
    expect(timerAtLocationKind(refused.save, 'LOC-0031', 'botany')?.usedCompost).toBe(true)

    const short = plantBotanySelection(
      launch,
      { ...save, inventory: [{ itemId: POTATO_SEED_ITEM_ID, quantity: 1 }] },
      [POTATO_SEED_ITEM_ID],
      0,
      true,
    )
    expect(short.ok).toBe(false)
    if (short.ok) return
    expect(short.reason).toBe('You need 1 compost for this planting.')

    const kelp = plantBotanySelection(
      launch,
      {
        ...save,
        currentLocationId: 'LOC-0043',
        skills: save.skills.map((row) =>
          row.skillId === 'SKL-0014' ? { ...row, level: 40, xp: 0 } : row,
        ),
        inventory: [
          { itemId: 'ITEM-0350', quantity: 1 },
          { itemId: COMPOST_ITEM_ID, quantity: 5 },
        ],
      },
      ['ITEM-0350'],
      0,
      true,
    )
    expect(kelp.ok).toBe(false)
    if (kelp.ok) return
    expect(kelp.reason).toBe('Compost cannot be used on kelp.')

    const planted = plantBotanySelection(launch, save, [POTATO_SEED_ITEM_ID, POTATO_SEED_ITEM_ID], 0)
    expect(planted.ok).toBe(true)
    if (!planted.ok) return
    const rolls = [0.99, 0.99]
    let i = 0
    const collected = collectLocationTimer(
      launch,
      planted.save,
      'LOC-0031',
      'botany',
      10800 * 1000,
      () => rolls[i++] ?? 0,
    )
    expect(collected.ok).toBe(true)
    if (!collected.ok) return
    expect(collected.loot).toEqual([])
    expect(collected.xpGained).toBe(0)
  })

  it('mutates only from seeds that lived', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0031',
      skills: createNewSave(launch).skills.map((row) =>
        row.skillId === 'SKL-0014' ? { ...row, level: 55, xp: 0 } : row,
      ),
      inventory: [
        { itemId: POTATO_SEED_ITEM_ID, quantity: 1 },
        { itemId: CARROT_SEED_ITEM_ID, quantity: 1 },
      ],
    }
    const planted = plantBotanySelection(launch, save, [POTATO_SEED_ITEM_ID, CARROT_SEED_ITEM_ID], 0)
    expect(planted.ok).toBe(true)
    if (!planted.ok) return
    // Potato lives + produce, carrot dies, potato seed returns (no mutation roll).
    const rolls = [0, 0, 0.99, 0]
    let i = 0
    const collected = collectLocationTimer(
      launch,
      planted.save,
      'LOC-0031',
      'botany',
      10800 * 1000,
      () => rolls[i++] ?? 0,
    )
    expect(collected.ok).toBe(true)
    if (!collected.ok) return
    expect(collected.loot.some((row) => row.itemId === TURNIP_SEED_ITEM_ID)).toBe(false)
    expect(collected.loot.some((row) => row.itemId === POTATO_SEED_ITEM_ID)).toBe(true)
    expect(collected.xpGained).toBe(1000)
  })
})
