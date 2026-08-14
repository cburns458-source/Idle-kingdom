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

    const names = launch.Activities.filter((row) => row['Location ID'] === 'LOC-0036').map(
      (row) => row['Contextual Name'],
    )
    expect(names).toEqual(['Train with the monks', 'Be blessed'])
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
    expect(save.combatEnemyHp).toBe(500)
  })

  it('blesses the player to full health without leaving an activity running', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0036',
      currentHp: 250,
    }
    save = equipStackToSlot(save, WEAPON_TOOL_SLOT_ID, 'ITEM-0100', 1)

    const blessed = requestActivityStart(launch, save, 'ACT-0036', Date.parse('2026-01-01T00:00:00.000Z'), () => 0)
    expect(blessed.ok).toBe(true)
    if (!blessed.ok) return
    save = blessed.save
    expect(save.equipment.slots[WEAPON_TOOL_SLOT_ID]).toBeNull()
    expect(save.currentHp).toBe(playerMaxHp(launch, save))
    expect(save.currentActivityId).toBeNull()
  })

  it('does not force combat on arrival', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    expect(forcedHostileActivity(launch, save, 'LOC-0036')).toBeNull()
    expect(locationIsHostileFor(launch, save, 'LOC-0036')).toBe(false)
  })
})
