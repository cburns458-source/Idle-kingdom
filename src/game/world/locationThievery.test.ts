import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import {
  isActivityBandThievery,
  isBankThieveryActivity,
  isNpcThieveryActivity,
  isShopThieveryActivity,
} from './locationThievery'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('location thievery bands', () => {
  const { launch } = prepareDatabase(rawDatabase)
  const save = createNewSave(launch)

  function activity(id: string) {
    const row = launch.Activities.find((entry) => entry['Activity ID'] === id)
    if (!row) throw new Error(`missing activity ${id}`)
    return row
  }

  it('puts shop steals under Shops when a shop row exists', () => {
    expect(isShopThieveryActivity(launch, save, activity('ACT-0054'))).toBe(true)
    expect(isShopThieveryActivity(launch, save, activity('ACT-0073'))).toBe(true)
    expect(isNpcThieveryActivity(launch, save, activity('ACT-0073'))).toBe(false)
    expect(isActivityBandThievery(launch, save, activity('ACT-0073'))).toBe(false)
  })

  it('keeps kitchen steal in Activities even with an NPC present', () => {
    expect(isShopThieveryActivity(launch, save, activity('ACT-0057'))).toBe(false)
    expect(isNpcThieveryActivity(launch, save, activity('ACT-0057'))).toBe(false)
    expect(isActivityBandThievery(launch, save, activity('ACT-0057'))).toBe(true)
  })

  it('puts barracks steal under People', () => {
    expect(isNpcThieveryActivity(launch, save, activity('ACT-0055'))).toBe(true)
    expect(isShopThieveryActivity(launch, save, activity('ACT-0055'))).toBe(false)
  })

  it('puts deposit box and vault under Bank; other lockpicks stay in Activities', () => {
    expect(isBankThieveryActivity(launch, activity('ACT-0059'))).toBe(true)
    expect(isBankThieveryActivity(launch, activity('ACT-0076'))).toBe(true)
    expect(isActivityBandThievery(launch, save, activity('ACT-0059'))).toBe(false)
    expect(isActivityBandThievery(launch, save, activity('ACT-0056'))).toBe(true)
  })
})
