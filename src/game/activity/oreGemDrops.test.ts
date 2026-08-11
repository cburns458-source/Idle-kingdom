import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { resolveActionRewards } from './rewards'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

const GEM_IDS = new Set(['ITEM-0012', 'ITEM-0013', 'ITEM-0014'])

/** Deterministic RNG that yields a fixed sequence, then Math.random. */
function sequenceRandom(values: number[]): () => number {
  let index = 0
  return () => {
    if (index < values.length) {
      const next = values[index]!
      index += 1
      return next
    }
    return Math.random()
  }
}

describe('ore gem secondary drop tables', () => {
  it('wires every Launch ore-mining action to the expected gem secondary table', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const expected: Array<{
      actionId: string
      name: string
      secondaryChance: number
      tableId: string
      gems: string[]
    }> = [
      {
        actionId: 'ACN-0018',
        name: 'Mine copper ore',
        secondaryChance: 1,
        tableId: 'RWT-0058',
        gems: ['ITEM-0012'],
      },
      {
        actionId: 'ACN-0020',
        name: 'Mine tin ore',
        secondaryChance: 1,
        tableId: 'RWT-0058',
        gems: ['ITEM-0012'],
      },
      {
        actionId: 'ACN-0021',
        name: 'Mine coal',
        secondaryChance: 2,
        tableId: 'RWT-0059',
        gems: ['ITEM-0012', 'ITEM-0013'],
      },
      {
        actionId: 'ACN-0022',
        name: 'Mine iron ore',
        secondaryChance: 2,
        tableId: 'RWT-0059',
        gems: ['ITEM-0012', 'ITEM-0013'],
      },
      {
        actionId: 'ACN-0097',
        name: 'Mine silver ore',
        secondaryChance: 3,
        tableId: 'RWT-0059',
        gems: ['ITEM-0012', 'ITEM-0013'],
      },
      {
        actionId: 'ACN-0098',
        name: 'Mine gold ore',
        secondaryChance: 4,
        tableId: 'RWT-0060',
        gems: ['ITEM-0012', 'ITEM-0013', 'ITEM-0014'],
      },
      {
        actionId: 'ACN-0026',
        name: 'Mine titanium ore',
        secondaryChance: 4,
        tableId: 'RWT-0060',
        gems: ['ITEM-0012', 'ITEM-0013', 'ITEM-0014'],
      },
      {
        actionId: 'ACN-0027',
        name: 'Mine tungsten ore',
        secondaryChance: 5,
        tableId: 'RWT-0060',
        gems: ['ITEM-0012', 'ITEM-0013', 'ITEM-0014'],
      },
    ]

    for (const row of expected) {
      const action = launch.Actions.find((entry) => entry['Action ID'] === row.actionId)
      expect(action, row.name).toBeTruthy()
      expect(action!['Display Name']).toBe(row.name)
      expect(action!['Secondary Drop Chance']).toBe(row.secondaryChance)
      expect(action!['Secondary Reward Table ID']).toBe(row.tableId)

      const entries = launch.RewardEntries.filter(
        (entry) => entry['Reward Table ID'] === row.tableId,
      )
      expect(entries.length).toBeGreaterThan(0)
      const gemIds = entries.map((entry) => entry['Reward ID / Value']).sort()
      expect(gemIds).toEqual([...row.gems].sort())
      expect(entries.every((entry) => entry.Status !== 'Needs Data')).toBe(true)
      expect(entries.every((entry) => (entry.Weight ?? 0) > 0)).toBe(true)
    }
  })

  it('grants a Sapphire from copper mining when the secondary roll succeeds', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0018')!

    // resolveActionRewards rolls:
    // 1) primary drop chance (95%) — 0 succeeds
    // 2) primary weighted pick — 0 picks the only ore entry
    // 3) secondary drop chance (1%) — 0 succeeds (0 < 0.01)
    // 4) secondary weighted pick — 0 picks Sapphire
    const rewarded = resolveActionRewards(launch, save, action, sequenceRandom([0, 0, 0, 0]))
    const ore = rewarded.loot.find((entry) => entry.itemId === 'ITEM-0003')
    const sapphire = rewarded.loot.find((entry) => entry.itemId === 'ITEM-0012')
    expect(ore?.quantity).toBe(1)
    expect(sapphire?.quantity).toBe(1)
    expect(rewarded.save.inventory.find((stack) => stack.itemId === 'ITEM-0012')?.quantity).toBe(1)
  })

  it('does not grant a gem from copper mining when the secondary roll fails', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0018')!

    // Primary succeeds (0), primary pick (0), secondary fails (0.5 => 50 >= 1).
    const rewarded = resolveActionRewards(launch, save, action, sequenceRandom([0, 0, 0.5]))
    expect(rewarded.loot.some((entry) => GEM_IDS.has(entry.itemId))).toBe(false)
    expect(rewarded.loot.some((entry) => entry.itemId === 'ITEM-0003')).toBe(true)
  })

  it('can grant Emerald or Sapphire from iron mining secondary table', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0022')!

    // RWT-0059: Sapphire weight 75, Emerald weight 25 (total 100).
    // After primary rolls, secondary chance 0 succeeds; pick 0.80 => Emerald.
    const emeraldDrop = resolveActionRewards(
      launch,
      save,
      action,
      sequenceRandom([0, 0, 0, 0.8]),
    )
    expect(emeraldDrop.loot.some((entry) => entry.itemId === 'ITEM-0013')).toBe(true)

    const sapphireDrop = resolveActionRewards(
      launch,
      save,
      action,
      sequenceRandom([0, 0, 0, 0.1]),
    )
    expect(sapphireDrop.loot.some((entry) => entry.itemId === 'ITEM-0012')).toBe(true)
  })

  it('can grant Ruby from tungsten mining all-gems secondary table', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0027')!

    // RWT-0060: Sapphire 70, Emerald 25, Ruby 5. Pick 0.97 => Ruby.
    const rewarded = resolveActionRewards(launch, save, action, sequenceRandom([0, 0, 0, 0.97]))
    expect(rewarded.loot.some((entry) => entry.itemId === 'ITEM-0014')).toBe(true)
  })

  it('matches configured secondary gem rates over many copper ore rolls', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0018')!
    const trials = 20_000
    let gems = 0
    for (let i = 0; i < trials; i += 1) {
      const rewarded = resolveActionRewards(launch, save, action, Math.random)
      if (rewarded.loot.some((entry) => entry.itemId === 'ITEM-0012')) gems += 1
    }
    const rate = gems / trials
    // Configured 1% secondary; allow statistical noise.
    expect(rate).toBeGreaterThan(0.005)
    expect(rate).toBeLessThan(0.02)
  })
})
