import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { confirmTannerJob, quoteTannerJob, tannerOffer } from './tanner'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('hide tanner', () => {
  it('quotes 2 gold per leather and the listed hide yields', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const tanner = launch.NPCs.find((row) => row['NPC ID'] === 'NPC-0018')!
    const save = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0025',
      gold: 100,
      inventory: [
        { itemId: 'ITEM-0378', quantity: 2 },
        { itemId: 'ITEM-0196', quantity: 1 },
      ],
    }
    const offer = tannerOffer(launch, save)
    expect(offer.feeEach).toBe(2)
    expect(offer.hides.map((row) => row.itemId).sort()).toEqual(['ITEM-0196', 'ITEM-0378'])
    expect(quoteTannerJob(launch, save, { 'ITEM-0378': 2, 'ITEM-0196': 1 })).toEqual({
      hideCount: 3,
      leather: 8,
      gold: 16,
    })

    const done = confirmTannerJob(launch, save, tanner, { 'ITEM-0378': 2, 'ITEM-0196': 1 })
    expect(done.ok).toBe(true)
    if (!done.ok) return
    expect(done.save.gold).toBe(84)
    expect(done.save.inventory.find((stack) => stack.itemId === 'ITEM-0045')?.quantity).toBe(8)
    expect(done.save.inventory.some((stack) => stack.itemId === 'ITEM-0378')).toBe(false)
  })

  it('refuses when the player cannot pay', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const tanner = launch.NPCs.find((row) => row['NPC ID'] === 'NPC-0018')!
    const save = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0025',
      gold: 3,
      inventory: [{ itemId: 'ITEM-0195', quantity: 1 }],
    }
    expect(quoteTannerJob(launch, save, { 'ITEM-0195': 1 })).toEqual({
      hideCount: 1,
      leather: 2,
      gold: 4,
    })
    const refused = confirmTannerJob(launch, save, tanner, { 'ITEM-0195': 1 })
    expect(refused).toEqual({ ok: false, reason: 'Need 4 gold.' })
  })

  it('is standing at both crafting workshops and not in existing drop pools as leather', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(launch.NPCs.filter((row) => row.Role === 'Tanner').map((row) => row['Location ID'])).toEqual(
      ['LOC-0025', 'LOC-0030'],
    )
    const cow = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0001')!
    const cowTable = launch.RewardEntries.filter((row) => row['Reward Table ID'] === cow['Reward Table ID'])
    expect(cowTable.some((row) => row['Reward ID / Value'] === 'ITEM-0378')).toBe(true)
    expect(cowTable.some((row) => row['Reward ID / Value'] === 'ITEM-0045')).toBe(false)
    const elkHunt = launch.RewardEntries.find((row) => row['Reward Entry ID'] === 'RWE-0169')!
    expect(elkHunt['Reward ID / Value']).toBe('ITEM-0379')
  })
})
