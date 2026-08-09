import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { validateActivityStart } from '../activity/engine'
import { prepareDatabase } from '../data/loadDatabase'
import { addItemToInventory } from '../activity/rewards'
import { createNewSave } from '../save/saveStore'
import {
  applyAutoEquipProposal,
  proposeAutoEquipForActivity,
} from './autoEquip'
import { unequipSlot } from './loadout'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

describe('auto-equip for activity requirements', () => {
  it('proposes the highest-tier compatible tool in the bag', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, currentLocationId: 'LOC-0005' }
    save = unequipSlot(save, 'SLOT-0001')
    save = addItemToInventory(save, 'ITEM-0102', 1) // Wooden Pickaxe
    save = addItemToInventory(save, 'ITEM-0111', 1) // Copper Pickaxe (higher ATR / tier)

    const blocked = validateActivityStart(launch, save, 'ACT-0005')
    expect(blocked.ok).toBe(false)
    if (blocked.ok) return

    const proposal = proposeAutoEquipForActivity(launch, save, 'ACT-0005', blocked.reason)
    expect(proposal?.itemId).toBe('ITEM-0111')
    expect(proposal?.itemName).toMatch(/Copper Pickaxe/i)
  })

  it('skips tools the player cannot equip yet', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, currentLocationId: 'LOC-0005' }
    save = unequipSlot(save, 'SLOT-0001')
    save = addItemToInventory(save, 'ITEM-0119', 1) // Steel Pickaxe, Mining 35
    save = addItemToInventory(save, 'ITEM-0111', 1) // Copper Pickaxe

    const blocked = validateActivityStart(launch, save, 'ACT-0005')
    expect(blocked.ok).toBe(false)
    if (blocked.ok) return

    const proposal = proposeAutoEquipForActivity(launch, save, 'ACT-0005', blocked.reason)
    expect(proposal?.itemId).toBe('ITEM-0111')
  })

  it('returns null when no compatible tool is available', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, currentLocationId: 'LOC-0005' }
    save = unequipSlot(save, 'SLOT-0001')

    const blocked = validateActivityStart(launch, save, 'ACT-0005')
    expect(blocked.ok).toBe(false)
    if (blocked.ok) return

    expect(proposeAutoEquipForActivity(launch, save, 'ACT-0005', blocked.reason)).toBeNull()
  })

  it('equipping the proposal satisfies activity start', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, currentLocationId: 'LOC-0005' }
    save = unequipSlot(save, 'SLOT-0001')
    save = addItemToInventory(save, 'ITEM-0111', 1)

    const blocked = validateActivityStart(launch, save, 'ACT-0005')
    expect(blocked.ok).toBe(false)
    if (blocked.ok) return

    const proposal = proposeAutoEquipForActivity(launch, save, 'ACT-0005', blocked.reason)
    expect(proposal).toBeTruthy()
    if (!proposal) return

    const equipped = applyAutoEquipProposal(launch, save, proposal)
    expect(equipped.ok).toBe(true)
    if (!equipped.ok) return
    expect(validateActivityStart(launch, equipped.save, 'ACT-0005').ok).toBe(true)
  })
})
