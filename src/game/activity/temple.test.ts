import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { equipStackToSlot, OFFHAND_SLOT_ID, WEAPON_TOOL_SLOT_ID } from '../equipment/loadout'
import { createNewSave } from '../save/saveStore'
import { playerMaxHp } from '../combat/stats'
import { forcedHostileActivity, locationIsHostileFor } from '../world/hostility'
import { canTravelTo } from '../world/travel'
import { MAIN_MAP_ID } from '../world/constants'
import { locationHasBlessing, requestBlessing } from '../world/blessing'
import { requestActivityStart } from './transition'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('Temple', () => {
  it('is a reachable main-map node with monk training and a blessing', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const location = launch.Locations.find((row) => row['Location ID'] === 'LOC-0036')
    expect(location?.['Display Name']).toBe('Temple')
    expect(canTravelTo(launch, 'LOC-0002', 'LOC-0036', MAIN_MAP_ID)).toBe(true)
    expect(locationHasBlessing(location)).toBe(true)

    const names = launch.Activities.filter((row) => row['Location ID'] === 'LOC-0036').map(
      (row) => row['Contextual Name'],
    )
    expect(names).toEqual(['Train with the monks', 'Pick weeds'])
    expect(launch.Activities.some((row) => row['Activity ID'] === 'ACT-0036')).toBe(false)
  })

  it('starts monk training unarmed after unequipping weapon and off-hand', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0036',
    }
    save = equipStackToSlot(save, WEAPON_TOOL_SLOT_ID, 'ITEM-0100', 1)
    save = equipStackToSlot(save, OFFHAND_SLOT_ID, 'ITEM-0145', 1)

    const started = requestActivityStart(launch, save, 'ACT-0035', Date.parse('2026-01-01T00:00:00.000Z'), () => 0)
    expect(started.ok).toBe(true)
    if (!started.ok) return
    save = started.save
    expect(save.equipment.slots[WEAPON_TOOL_SLOT_ID]).toBeNull()
    expect(save.equipment.slots[OFFHAND_SLOT_ID]).toBeNull()
    expect(save.currentActivityId).toBe('ACT-0035')
    expect(save.combatEnemyId).toBe('ENM-0020')
    expect(save.combatEnemyHp).toBe(350)
  })

  it('restores full health without unequipping or starting an activity', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0036',
      currentHp: 250,
    }
    save = equipStackToSlot(save, WEAPON_TOOL_SLOT_ID, 'ITEM-0100', 1)
    save = equipStackToSlot(save, OFFHAND_SLOT_ID, 'ITEM-0145', 1)

    const blessed = requestBlessing(launch, save, Date.parse('2026-01-01T00:00:00.000Z'))
    expect(blessed.ok).toBe(true)
    if (!blessed.ok) return
    expect(blessed.alreadyFull).toBe(false)
    expect(blessed.message).toBe('The monks restore you to full health.')
    save = blessed.save
    expect(save.equipment.slots[WEAPON_TOOL_SLOT_ID]?.itemId).toBe('ITEM-0100')
    expect(save.equipment.slots[OFFHAND_SLOT_ID]?.itemId).toBe('ITEM-0145')
    expect(save.currentHp).toBe(playerMaxHp(launch, save))
    expect(save.currentActivityId).toBeNull()
  })

  it('reports when health is already full', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0036',
    }
    const blessed = requestBlessing(launch, save, Date.parse('2026-01-01T00:00:00.000Z'))
    expect(blessed.ok).toBe(true)
    if (!blessed.ok) return
    expect(blessed.alreadyFull).toBe(true)
    expect(blessed.message).toBe('You are already at full health.')
    expect(blessed.save.currentHp).toBe(playerMaxHp(launch, blessed.save))
  })

  it('does not force combat on arrival', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    expect(forcedHostileActivity(launch, save, 'LOC-0036')).toBeNull()
    expect(locationIsHostileFor(launch, save, 'LOC-0036')).toBe(false)
  })

  it('pick weeds rolls augur weed or moonblossom with empty hands', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const activity = launch.Activities.find((row) => row['Activity ID'] === 'ACT-0039')
    expect(activity?.['Contextual Name']).toBe('Pick weeds')
    expect(activity?.['Pool ID']).toBe('POOL-0029')

    const pool = launch.PoolEntries.filter((row) => row['Pool ID'] === 'POOL-0029')
    expect(pool).toHaveLength(2)
    expect(pool.map((row) => `${row['Action ID']}:${row.Weight}`)).toEqual(
      expect.arrayContaining(['ACN-0109:90', 'ACN-0110:10']),
    )

    const augur = launch.Actions.find((row) => row['Action ID'] === 'ACN-0109')
    expect(augur?.['Display Name']).toBe('Gather augur weed')
    expect(augur?.['Base Duration Seconds']).toBe(360)
    expect(augur?.['XP Reward']).toBe(50000)

    const moon = launch.Actions.find((row) => row['Action ID'] === 'ACN-0110')
    expect(moon?.['Base Duration Seconds']).toBe(540)
    expect(moon?.['XP Reward']).toBe(75000)

    expect(launch.Actions.some((row) => row['Action ID'] === 'ACN-0174')).toBe(false)

    let save = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0036',
    }
    save = equipStackToSlot(save, WEAPON_TOOL_SLOT_ID, 'ITEM-0100', 1)
    save = equipStackToSlot(save, OFFHAND_SLOT_ID, 'ITEM-0145', 1)

    const started = requestActivityStart(
      launch,
      save,
      'ACT-0039',
      Date.parse('2026-01-01T00:00:00.000Z'),
      () => 0,
    )
    expect(started.ok).toBe(true)
    if (!started.ok) return
    save = started.save
    expect(save.equipment.slots[WEAPON_TOOL_SLOT_ID]).toBeNull()
    expect(save.equipment.slots[OFFHAND_SLOT_ID]).toBeNull()
    expect(save.currentActivityId).toBe('ACT-0039')
    expect(save.currentActionId).toBe('ACN-0109')
  })
})
