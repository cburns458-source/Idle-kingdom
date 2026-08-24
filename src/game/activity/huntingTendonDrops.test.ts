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

  it('grants tendons on duck hunt secondary roll without blocking other secondaries on rabbit', () => {
    const save = createNewSave(launch)
    const duck = launch.Actions.find((row) => row['Action ID'] === 'ACN-0013')!
    const rabbit = launch.Actions.find((row) => row['Action ID'] === 'ACN-0016')!

    const duckDrop = resolveActionRewards(launch, save, duck, seqRandom([0.95, 0.05]))
    expect(duckDrop.loot).toContainEqual(
      expect.objectContaining({ itemId: 'ITEM-0044', quantity: 1 }),
    )

    const rabbitDrop = resolveActionRewards(launch, save, rabbit, seqRandom([0, 0, 0.02, 0.03]))
    expect(rabbitDrop.loot).toContainEqual(
      expect.objectContaining({ itemId: 'ITEM-0038', quantity: 1 }),
    )
    expect(rabbitDrop.loot).toContainEqual(
      expect.objectContaining({ itemId: 'ITEM-0044', quantity: 1 }),
    )
  })

  it('does not grant tendons on butterfly hunt', () => {
    const save = createNewSave(launch)
    const butterfly = launch.Actions.find((row) => row['Action ID'] === 'ACN-0015')!
    const result = resolveActionRewards(launch, save, butterfly, seqRandom([0, 0]))
    expect(result.loot.every((grant) => grant.itemId !== 'ITEM-0044')).toBe(true)
  })
})
