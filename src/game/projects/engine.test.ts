import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { addItemToInventory } from '../activity/rewards'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { completeSpecialProject } from './engine'
import { encodeEnchantTarget } from './enchantments'
import { projectsForFacility, specialProductionStationsAt } from './projects'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

describe('special production', () => {
  it('lists Smithing and Artisanry stations in Town', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const stations = specialProductionStationsAt(launch, 'LOC-0025')
    expect(stations.map((station) => station.skillId).sort()).toEqual(['SKL-0011', 'SKL-0012'])
    expect(stations.map((station) => station.label).sort()).toEqual([
      'Artisans workshop',
      'Smithing forge',
    ])
  })

  it('lists Arcana at the Wizard Tower including locked Launch projects', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const stations = specialProductionStationsAt(launch, 'LOC-0007')
    expect(stations.some((station) => station.skillId === 'SKL-0013')).toBe(true)
    expect(stations.find((station) => station.skillId === 'SKL-0013')?.label).toBe('Mages quarters')
    const listed = projectsForFacility(launch, 'FAC-0008', 'SKL-0013')
    expect(listed.map((project) => project['Project ID']).sort()).toEqual([
      'PRJ-0134',
      'PRJ-0135',
      'PRJ-0139',
      'PRJ-0140',
      'PRJ-0141',
      'PRJ-0142',
    ])
    expect(listed.find((project) => project['Project ID'] === 'PRJ-0139')?.['Display Name']).toBe(
      'Strength Spell',
    )
    expect(listed.find((project) => project['Project ID'] === 'PRJ-0139')?.['Output Item / Target ID']).toBe(
      'ITEM-0295',
    )
    expect(launch.Items.find((item) => item['Item ID'] === 'ITEM-0295')?.['Display Name']).toBe(
      'Strength Spell',
    )
    expect(listed.every((project) => project['Required Skill 1 Level']! > 1)).toBe(true)
    // Level-1 saves still see projects; completion remains hard-gated.
    expect(save.skills.find((skill) => skill.skillId === 'SKL-0013')?.level ?? 1).toBe(1)
  })

  it('crafts Strength Spell as a named inventory item', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      unlockedNpcIds: ['NPC-0004'],
      currentLocationId: 'LOC-0007',
      skills: save.skills.map((skill) =>
        skill.skillId === 'SKL-0013' || skill.skillId === 'SKL-0009'
          ? { ...skill, level: 20, xp: 50_000 }
          : skill,
      ),
    }
    save = addItemToInventory(save, 'ITEM-0099', 1)
    save = addItemToInventory(save, 'ITEM-0040', 10)

    const result = completeSpecialProject(launch, save, 'PRJ-0139', 1)
    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(result.outputLabel).toBe('Strength Spell')
    expect(result.save.inventory.find((stack) => stack.itemId === 'ITEM-0295')?.quantity).toBe(1)
    expect(launch.Items.find((item) => item['Item ID'] === 'ITEM-0295')?.['Display Name']).toBe(
      'Strength Spell',
    )
  })

  it('no longer requires a secondary Crafting level for any Special Production project', () => {
    const { launch } = prepareDatabase(rawDatabase)
    for (const project of launch.Projects) {
      expect(project['Required Skill 2 ID']).not.toBe('SKL-0009')
      expect(project['Required Skill 3 ID']).not.toBe('SKL-0009')
    }
  })

  it('crafts Strength Spell with zero Crafting skill now that the requirement is removed', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      unlockedNpcIds: ['NPC-0004'],
      currentLocationId: 'LOC-0007',
      skills: save.skills.map((skill) =>
        skill.skillId === 'SKL-0013' ? { ...skill, level: 20, xp: 50_000 } : skill,
      ),
    }
    save = addItemToInventory(save, 'ITEM-0099', 1)
    save = addItemToInventory(save, 'ITEM-0040', 10)

    const result = completeSpecialProject(launch, save, 'PRJ-0139', 1)
    expect(result.ok).toBe(true)
  })

  it('instantly completes a L1 smithing project and consumes materials once', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, unlockedNpcIds: ['NPC-0003'], currentLocationId: 'LOC-0025' }
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
    expect(result.save.skills.find((skill) => skill.skillId === 'SKL-0011')?.xp).toBe(1200)
    expect(result.save.currentActivityId).toBeNull()
  })

  it('rejects smithing projects before Master Dwarf knowledge', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, currentLocationId: 'LOC-0025' }
    save = addItemToInventory(save, 'ITEM-0074', 10)
    save = addItemToInventory(save, 'ITEM-0214', 2)
    save = addItemToInventory(save, 'ITEM-0084', 10)
    const result = completeSpecialProject(launch, save, 'PRJ-0007', 1)
    expect(result.ok).toBe(false)
    if (result.ok) return
    expect(result.reason).toMatch(/Master Dwarf/i)
  })

  it('rejects projects when materials are missing', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = {
      ...createNewSave(launch),
      unlockedNpcIds: ['NPC-0003'],
      currentLocationId: 'LOC-0025',
    }
    const result = completeSpecialProject(launch, save, 'PRJ-0007', 1)
    expect(result.ok).toBe(false)
  })

  it('rejects projects away from the required facility', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      unlockedNpcIds: ['NPC-0003'],
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

  it('can enchant an inventory item and keeps enchanted stacks unique', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      unlockedNpcIds: ['NPC-0004'],
      currentLocationId: 'LOC-0007',
      skills: save.skills.map((skill) =>
        skill.skillId === 'SKL-0013' || skill.skillId === 'SKL-0009'
          ? { ...skill, level: 20, xp: 50_000 }
          : skill,
      ),
    }
    save = addItemToInventory(save, 'ITEM-0098', 1)
    save = addItemToInventory(save, 'ITEM-0011', 2)
    save = addItemToInventory(save, 'ITEM-0031', 10)
    // Steel pickaxe is gathering gear eligible for minor gathering enchantment.
    save = addItemToInventory(save, 'ITEM-0119', 2)
    const invIndex = save.inventory.findIndex((stack) => stack.itemId === 'ITEM-0119')
    expect(invIndex).toBeGreaterThanOrEqual(0)

    const result = completeSpecialProject(
      launch,
      save,
      'PRJ-0134',
      1,
      encodeEnchantTarget({ kind: 'inventory', index: invIndex }),
    )
    expect(result.ok).toBe(true)
    if (!result.ok) return

    const enchanted = result.save.inventory.filter(
      (stack) => stack.itemId === 'ITEM-0119' && stack.enchantmentId === 'ENCH-0002',
    )
    const plain = result.save.inventory.filter(
      (stack) => stack.itemId === 'ITEM-0119' && !stack.enchantmentId,
    )
    expect(enchanted).toHaveLength(1)
    expect(enchanted[0]?.quantity).toBe(1)
    expect(plain[0]?.quantity).toBe(1)

    const merged = addItemToInventory(result.save, 'ITEM-0119', 1, 'ENCH-0002')
    expect(
      merged.inventory.filter(
        (stack) => stack.itemId === 'ITEM-0119' && stack.enchantmentId === 'ENCH-0002',
      ),
    ).toHaveLength(2)
  })
})
