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
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

/** Test helper: unequip a slot, asserting the bag has room (it always does here). */
function forceUnequip(save: import('../save/types').PlayerSave, slotId: string) {
  const result = unequipSlot(save, slotId)
  if (!result.ok) throw new Error(`Expected unequip to succeed: ${result.reason}`)
  return result.save
}

describe('auto-equip for activity requirements', () => {
  it('proposes the highest-tier compatible tool in the bag', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, currentLocationId: 'LOC-0005' }
    save = forceUnequip(save, 'SLOT-0001')
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
    save = forceUnequip(save, 'SLOT-0001')
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
    save = forceUnequip(save, 'SLOT-0001')

    const blocked = validateActivityStart(launch, save, 'ACT-0005')
    expect(blocked.ok).toBe(false)
    if (blocked.ok) return

    expect(proposeAutoEquipForActivity(launch, save, 'ACT-0005', blocked.reason)).toBeNull()
  })

  it('equipping the proposal satisfies activity start', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, currentLocationId: 'LOC-0005' }
    save = forceUnequip(save, 'SLOT-0001')
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

  it('proposes lockpicks from the bag for deposit-box thievery', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      currentLocationId: 'LOC-0034',
      skills: save.skills.map((row) =>
        row.skillId === 'SKL-0015' ? { ...row, level: 50, xp: 0 } : row,
      ),
    }
    save = forceUnequip(save, 'SLOT-0001')
    save = addItemToInventory(save, 'ITEM-0351', 5)

    const blocked = validateActivityStart(launch, save, 'ACT-0059')
    expect(blocked.ok).toBe(false)
    if (blocked.ok) return

    const proposal = proposeAutoEquipForActivity(launch, save, 'ACT-0059', blocked.reason)
    expect(proposal?.itemId).toBe('ITEM-0351')
    expect(proposal?.itemName).toMatch(/Lockpicks/i)
    expect(proposal?.capabilities).toEqual(['lockpick'])

    const equipped = applyAutoEquipProposal(launch, save, proposal!)
    expect(equipped.ok).toBe(true)
    if (!equipped.ok) return
    expect(validateActivityStart(launch, equipped.save, 'ACT-0059').ok).toBe(true)
  })

  it('returns null for lockpick work when the bag has none', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      currentLocationId: 'LOC-0034',
      skills: save.skills.map((row) =>
        row.skillId === 'SKL-0015' ? { ...row, level: 50, xp: 0 } : row,
      ),
    }
    save = forceUnequip(save, 'SLOT-0001')

    const blocked = validateActivityStart(launch, save, 'ACT-0059')
    expect(blocked.ok).toBe(false)
    if (blocked.ok) return
    expect(proposeAutoEquipForActivity(launch, save, 'ACT-0059', blocked.reason)).toBeNull()
  })
})
