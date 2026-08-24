import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { isTwoHandedItem } from '../equipment/loadout'
import { skillMenuView } from '../skills/skillActions'
import { CASTLE_MAP_ID } from '../world/constants'
import { canTravelTo, locationsForMapView } from '../world/travel'
import { layoutForMap } from '../world/mapLayout'
import { activityIsComingSoon, COMING_SOON_REASON, validateActivityStart } from './engine'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('Castle Crypt', () => {
  it('places the crypt on the castle grounds with a combat warning', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const location = launch.Locations.find((row) => row['Location ID'] === 'LOC-0037')
    expect(location).toMatchObject({
      'Display Name': 'Castle Crypt',
      'Map ID': CASTLE_MAP_ID,
      'Parent Location ID': 'LOC-0013',
    })
    expect(layoutForMap(CASTLE_MAP_ID)['LOC-0037']).toEqual({ x: 22, y: 70 })

    const nodes = locationsForMapView(launch, CASTLE_MAP_ID).map((row) => row['Location ID'])
    expect(nodes).toContain('LOC-0037')
    expect(canTravelTo(launch, 'LOC-0013', 'LOC-0037', CASTLE_MAP_ID)).toBe(true)

    const fend = launch.Activities.find((row) => row['Activity ID'] === 'ACT-0041')
    expect(fend).toMatchObject({
      'Contextual Name': 'Fend off the old spirits',
      'Location ID': 'LOC-0037',
      'Pool ID': 'POOL-0031',
      'Danger Warning Combat Level': 34,
    })

    const pool = launch.PoolEntries.filter((row) => row['Pool ID'] === 'POOL-0031')
    expect(pool).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ 'Action ID': 'ACN-0176', Weight: 90 }),
        expect.objectContaining({ 'Action ID': 'ACN-0006', Weight: 10 }),
      ]),
    )
    expect(pool).toHaveLength(2)

    const ghost = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0022')
    const zombie = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0009')!
    expect(ghost).toMatchObject({
      'Display Name': 'Ghost',
      'Combat Level': zombie['Combat Level'],
      'Maximum HP': zombie['Maximum HP'],
      'Min Damage': zombie['Min Damage'],
      'Max Damage': zombie['Max Damage'],
      'Combat XP': zombie['Combat XP'],
      'Minimum Gold': 0,
      'Maximum Gold': 0,
      'Drop Chance': 0,
      'Reward Table ID': null,
    })

    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0176')
    expect(action).toMatchObject({
      'Target ID': 'ENM-0022',
      'Drop Chance': 0,
      'Reward Table ID': null,
      'XP Reward': 6000,
    })
  })

  it('refuses Enter the catacombs as coming soon', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const activity = launch.Activities.find((row) => row['Activity ID'] === 'ACT-0042')
    expect(activity?.['Contextual Name']).toBe('Enter the catacombs')
    expect(activityIsComingSoon(activity)).toBe(true)

    const save = { ...createNewSave(launch), currentLocationId: 'LOC-0037' }
    expect(validateActivityStart(launch, save, 'ACT-0042')).toEqual({
      ok: false,
      reason: COMING_SOON_REASON,
    })
  })
})

describe("Mage's Wand", () => {
  it('is a one-handed Arcana weapon with sparks', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const item = launch.Items.find((row) => row['Item ID'] === 'ITEM-0307')
    expect(item?.['Display Name']).toBe("Mage's Wand")
    expect(item?.['Functional / Source Tags']).toContain('staff_sparks')
    expect(item?.['Functional / Source Tags']).not.toContain('two_handed')
    expect(isTwoHandedItem(launch, 'ITEM-0307')).toBe(false)

    const equipment = launch.Equipment.find((row) => row['Equipment ID'] === 'EQP-0185')
    expect(equipment).toMatchObject({
      'Item ID': 'ITEM-0307',
      'Required Skill ID': 'SKL-0013',
      'Required Level': 50,
      'Secondary Required Skill ID': null,
      'Min Damage': 25,
      'Max Damage': 50,
    })
    expect(equipment?.['Capabilities / Effects']).toContain('staff_sparks')
    expect(equipment?.['Capabilities / Effects']).not.toContain('two_handed')

    const project = launch.Projects.find((row) => row['Project ID'] === 'PRJ-0147')
    expect(project).toMatchObject({
      'Output Item / Target ID': 'ITEM-0307',
      'Facility ID': 'FAC-0008',
      'Required Skill 1 ID': 'SKL-0013',
      'Required Skill 1 Level': 55,
      'Input 1 Item ID': 'ITEM-0217',
      'Input 1 Quantity': 5,
      'Input 2 Item ID': 'ITEM-0011',
      'Input 2 Quantity': 5,
      'Input 3 Item ID': 'ITEM-0089',
      'Input 3 Quantity': 1,
      'XP Reward': 200000,
    })

    const weapons =
      skillMenuView(launch, 'SKL-0013').tabs.find((tab) => tab.id === 'weapons')?.sections[0]
        ?.entries ?? []
    expect(weapons.map((entry) => entry.displayName)).toEqual([
      'Staff of Sparks',
      'Staff of Binding',
      "Mage's Wand",
      'Staff of Power',
    ])
  })
})
