import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { addItemToInventory } from '../activity/rewards'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { completeSpecialProject } from './engine'
import { projectsForFacility, specialProductionStationsAt } from './projects'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

describe('special production', () => {
  it('lists Smithing and Artisanry stations in Town', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const stations = specialProductionStationsAt(launch, 'LOC-0002')
    expect(stations.map((station) => station.skillId).sort()).toEqual(['SKL-0011', 'SKL-0012'])
  })

  it('lists Arcana at the Wizard Tower including locked Launch projects', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const stations = specialProductionStationsAt(launch, 'LOC-0007')
    expect(stations.some((station) => station.skillId === 'SKL-0013')).toBe(true)
    const listed = projectsForFacility(launch, 'FAC-0008', 'SKL-0013')
    expect(listed.map((project) => project['Project ID']).sort()).toEqual([
      'PRJ-0134',
      'PRJ-0135',
    ])
    expect(listed.every((project) => project['Required Skill 1 Level']! > 1)).toBe(true)
    // Level-1 saves still see projects; completion remains hard-gated.
    expect(save.skills.find((skill) => skill.skillId === 'SKL-0013')?.level ?? 1).toBe(1)
  })

  it('instantly completes a L1 smithing project and consumes materials once', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0074', 10)
    save = addItemToInventory(save, 'ITEM-0214', 2)
    save = addItemToInventory(save, 'ITEM-0084', 10)

    const known = projectsForFacility(launch, 'FAC-0005', 'SKL-0011')
    expect(known.some((project) => project['Project ID'] === 'PRJ-0007')).toBe(true)

    const result = completeSpecialProject(launch, save, 'PRJ-0007', 1)
    expect(result.ok).toBe(true)
    if (!result.ok) return

    expect(result.save.inventory.find((stack) => stack.itemId === 'ITEM-0132')?.quantity).toBe(1)
    expect(result.save.inventory.find((stack) => stack.itemId === 'ITEM-0074')).toBeUndefined()
    expect(result.save.skills.find((skill) => skill.skillId === 'SKL-0011')?.xp).toBe(120000)
    expect(result.save.currentActivityId).toBeNull()
  })

  it('rejects projects when materials are missing', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const result = completeSpecialProject(launch, save, 'PRJ-0007', 1)
    expect(result.ok).toBe(false)
  })

  it('rejects projects away from the required facility', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      currentLocationId: 'LOC-0001',
    }
    save = addItemToInventory(save, 'ITEM-0074', 10)
    save = addItemToInventory(save, 'ITEM-0214', 2)
    save = addItemToInventory(save, 'ITEM-0084', 10)
    const result = completeSpecialProject(launch, save, 'PRJ-0007', 1)
    expect(result.ok).toBe(false)
    if (result.ok) return
    expect(result.reason).toMatch(/facility/i)
  })
})
