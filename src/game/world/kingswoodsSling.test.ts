import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { KINGSWOODS_LOCATION_ID, SLING_ITEM_ID, maybeGrantKingswoodsSling } from './kingswoodsSling'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('Kingswoods sling', () => {
  it('grants a Sling the first time the player stands in the Kingswoods', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = { ...createNewSave(launch), currentLocationId: KINGSWOODS_LOCATION_ID }
    const first = maybeGrantKingswoodsSling(launch, save)
    expect(first.granted).toBe(true)
    expect(first.save.claimedKingswoodsSling).toBe(true)
    expect(first.save.inventory.find((stack) => stack.itemId === SLING_ITEM_ID)?.quantity).toBe(1)
    expect(first.message).toContain('Sling')

    const second = maybeGrantKingswoodsSling(launch, first.save)
    expect(second.granted).toBe(false)
    expect(second.save.inventory.find((stack) => stack.itemId === SLING_ITEM_ID)?.quantity).toBe(1)
  })

  it('does not grant again when the player already has a Sling', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = {
      ...createNewSave(launch),
      currentLocationId: KINGSWOODS_LOCATION_ID,
      inventory: [{ itemId: SLING_ITEM_ID, quantity: 1 }],
    }
    const result = maybeGrantKingswoodsSling(launch, save)
    expect(result.granted).toBe(false)
    expect(result.save.claimedKingswoodsSling).toBe(true)
    expect(result.save.inventory.find((stack) => stack.itemId === SLING_ITEM_ID)?.quantity).toBe(1)
  })
})
