import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { addItemToInventory } from '../activity/rewards'
import { createNewSave } from '../save/saveStore'
import { getEnchantment } from './projects'
import { eligibleEnchantmentTargets, isAxeItem } from './enchantments'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

describe('axe enchantment eligibility', () => {
  it('treats axe items as combat axes', () => {
    const { launch } = prepareDatabase(rawDatabase)
    for (const itemId of ['ITEM-0100', 'ITEM-0132', 'ITEM-0133', 'ITEM-0226']) {
      const item = launch.Items.find((row) => row['Item ID'] === itemId)
      const equipment = launch.Equipment.find((row) => row['Item ID'] === itemId)
      expect(equipment, itemId).toBeTruthy()
      expect(isAxeItem(item, equipment!), itemId).toBe(true)
    }
    const hatchet = launch.Items.find((row) => row['Item ID'] === 'ITEM-0110')
    const hatchetEq = launch.Equipment.find((row) => row['Item ID'] === 'ITEM-0110')!
    expect(isAxeItem(hatchet, hatchetEq)).toBe(false)
  })

  it('allows axes for combat enchantments but not gathering', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, inventory: [] }
    save = addItemToInventory(save, 'ITEM-0132', 1) // Copper Axe
    save = addItemToInventory(save, 'ITEM-0110', 1) // Copper Hatchet
    save = addItemToInventory(save, 'ITEM-0111', 1) // Copper Pickaxe

    const gathering = getEnchantment(launch, 'ENCH-0002')!
    const combat = getEnchantment(launch, 'ENCH-0003')!

    const gatheringIds = eligibleEnchantmentTargets(launch, save, gathering).map((option) => {
      if (option.target.kind !== 'inventory') return null
      return save.inventory[option.target.index]?.itemId ?? null
    })
    const combatIds = eligibleEnchantmentTargets(launch, save, combat).map((option) => {
      if (option.target.kind !== 'inventory') return null
      return save.inventory[option.target.index]?.itemId ?? null
    })

    expect(gatheringIds).toContain('ITEM-0110')
    expect(gatheringIds).toContain('ITEM-0111')
    expect(gatheringIds).not.toContain('ITEM-0132')

    expect(combatIds).toContain('ITEM-0132')
  })

  it('allows craftable Jewelry to take gathering or combat enchantments', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, inventory: [] }
    save = addItemToInventory(save, 'ITEM-0170', 1) // Silver Necklace
    save = addItemToInventory(save, 'ITEM-0171', 1) // Silver Ring

    const gathering = getEnchantment(launch, 'ENCH-0002')!
    const combat = getEnchantment(launch, 'ENCH-0003')!

    const gatheringIds = eligibleEnchantmentTargets(launch, save, gathering).map(
      (option) => (option.target.kind === 'inventory' ? save.inventory[option.target.index]?.itemId : null),
    )
    const combatIds = eligibleEnchantmentTargets(launch, save, combat).map(
      (option) => (option.target.kind === 'inventory' ? save.inventory[option.target.index]?.itemId : null),
    )

    expect(gatheringIds).toContain('ITEM-0170')
    expect(gatheringIds).toContain('ITEM-0171')
    expect(combatIds).toContain('ITEM-0170')
    expect(combatIds).toContain('ITEM-0171')
  })

  it('allows armor to take the Thorns enchantment but not weapon enchantments', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, inventory: [] }
    save = addItemToInventory(save, 'ITEM-0229', 1) // Chest armor with Damage Reduction

    const thorns = getEnchantment(launch, 'ENCH-0006')!
    const combat = getEnchantment(launch, 'ENCH-0003')!

    const thornsIds = eligibleEnchantmentTargets(launch, save, thorns).map(
      (option) => (option.target.kind === 'inventory' ? save.inventory[option.target.index]?.itemId : null),
    )
    const combatIds = eligibleEnchantmentTargets(launch, save, combat).map(
      (option) => (option.target.kind === 'inventory' ? save.inventory[option.target.index]?.itemId : null),
    )

    expect(thornsIds).toContain('ITEM-0229')
    expect(combatIds).not.toContain('ITEM-0229')
  })
})
