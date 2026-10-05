import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { resolveActionRewards } from './rewards'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

function seqRandom(values: number[]): () => number {
  let i = 0
  return () => values[Math.min(i++, values.length - 1)]!
}

describe('hunting Animal Tendon drops', () => {
  const { launch } = prepareDatabase(rawDatabase)

  it('grants tendons on duck and rabbit secondary rolls', () => {
    const save = createNewSave(launch)
    const duck = launch.Actions.find((row) => row['Action ID'] === 'ACN-0013')!
    const rabbit = launch.Actions.find((row) => row['Action ID'] === 'ACN-0016')!

    const duckDrop = resolveActionRewards(launch, save, duck, seqRandom([0, 0, 0, 0]))
    expect(duckDrop.loot).toContainEqual(
      expect.objectContaining({ itemId: 'ITEM-0044', quantity: 1 }),
    )

    // Primary weight 0 → Raw Rabbit; secondary chance 0 → tendons.
    const rabbitDrop = resolveActionRewards(launch, save, rabbit, seqRandom([0, 0, 0, 0]))
    expect(rabbitDrop.loot).toContainEqual(
      expect.objectContaining({ itemId: 'ITEM-0052', quantity: 1 }),
    )
    expect(rabbitDrop.loot).toContainEqual(
      expect.objectContaining({ itemId: 'ITEM-0044', quantity: 1 }),
    )
  })

  it('can roll Rabbit\'s Foot from the rabbit main table', () => {
    const save = createNewSave(launch)
    const rabbit = launch.Actions.find((row) => row['Action ID'] === 'ACN-0016')!
    // Entries are meat 60, foot 10, hide 30 → foot sits in the 60–70 band.
    const rabbitDrop = resolveActionRewards(launch, save, rabbit, seqRandom([0, 0.65, 1, 1]))
    expect(rabbitDrop.loot).toContainEqual(
      expect.objectContaining({ itemId: 'ITEM-0038', quantity: 1 }),
    )
  })

  it('can roll Rabbit Hide from the rabbit main table', () => {
    const save = createNewSave(launch)
    const rabbit = launch.Actions.find((row) => row['Action ID'] === 'ACN-0016')!
    const rabbitDrop = resolveActionRewards(launch, save, rabbit, seqRandom([0, 0.95, 1, 1]))
    expect(rabbitDrop.loot).toContainEqual(
      expect.objectContaining({ itemId: 'ITEM-0426', quantity: 1 }),
    )
  })

  it('does not grant tendons on weasel hunt', () => {
    const save = createNewSave(launch)
    const weasel = launch.Actions.find((row) => row['Action ID'] === 'ACN-0015')!
    expect(weasel['Drop Chance']).toBe(30)
    const result = resolveActionRewards(launch, save, weasel, seqRandom([0, 0]))
    expect(result.loot.every((grant) => grant.itemId !== 'ITEM-0044')).toBe(true)
  })
})
