import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { addItemToInventory } from '../activity/rewards'
import { prepareDatabase } from '../data/loadDatabase'
import { equipItemFromInventory } from '../equipment/loadout'
import { completeSpecialProject } from '../projects/engine'
import { createNewSave, parseSave } from '../save/saveStore'
import { SAVE_VERSION, type PlayerSave } from '../save/types'
import { beginProductionQueue } from './engine'
import { getRecipe, inventoryCount } from './recipes'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

const TOWN = 'LOC-0025'
const FURNACE_ACTIVITY = 'ACT-0018'
const MASTER_DWARF = 'NPC-0003'
const METALLURGY = 'SKL-0008'
const SMITHING = 'SKL-0011'
const MIGHT = 'SKL-0001'
const VITALITY = 'SKL-0016'

const TUNGSTEN_ORE = 'ITEM-0010'
const TITANIUM_ORE = 'ITEM-0009'
const COPPER_ORE = 'ITEM-0003'
const TIN_ORE = 'ITEM-0004'
const IRON_ORE = 'ITEM-0005'
const TUNGSTEN_BAR = 'ITEM-0080'
const TITANIUM_BAR = 'ITEM-0079'
const IRONWOOD_TIMBER = 'ITEM-0408'
const MAHOGANY_TIMBER = 'ITEM-0218'
const TUNGSTEN_SWORD = 'ITEM-0263'
const TITANIUM_HELMET = 'ITEM-0254'

const TUNGSTEN_BAR_RECIPE = 'RCP-0020'
const TITANIUM_BAR_RECIPE = 'RCP-0019'
const TUNGSTEN_SWORD_PROJECT = 'PRJ-0110'
const TITANIUM_SWORD_PROJECT = 'PRJ-0097'

function withLevels(save: PlayerSave, levels: Record<string, number>): PlayerSave {
  return {
    ...save,
    skills: save.skills.map((skill) =>
      skill.skillId in levels ? { ...skill, level: levels[skill.skillId]! } : skill,
    ),
  }
}

describe('tungsten and titanium gates', () => {
  const { launch } = prepareDatabase(rawDatabase)

  function smelter(metallurgy: number): PlayerSave {
    let save = withLevels(createNewSave(launch), { [METALLURGY]: metallurgy })
    save = { ...save, currentLocationId: TOWN }
    save = addItemToInventory(save, TUNGSTEN_ORE, 20)
    save = addItemToInventory(save, TITANIUM_ORE, 20)
    save = addItemToInventory(save, COPPER_ORE, 10)
    save = addItemToInventory(save, TIN_ORE, 10)
    save = addItemToInventory(save, IRON_ORE, 10)
    return save
  }

  function smith(levels: { smithing: number; metallurgy: number }): PlayerSave {
    let save = withLevels(createNewSave(launch), {
      [SMITHING]: levels.smithing,
      [METALLURGY]: levels.metallurgy,
    })
    save = { ...save, currentLocationId: TOWN, unlockedNpcIds: [MASTER_DWARF] }
    save = addItemToInventory(save, TUNGSTEN_BAR, 20)
    save = addItemToInventory(save, TITANIUM_BAR, 20)
    save = addItemToInventory(save, IRONWOOD_TIMBER, 10)
    save = addItemToInventory(save, MAHOGANY_TIMBER, 10)
    return save
  }

  it('data: bars unlock at Metallurgy 60 and 70 with the recorded ingredients', () => {
    const tungsten = getRecipe(launch, TUNGSTEN_BAR_RECIPE)!
    expect(tungsten['Proficiency Level']).toBe(60)
    expect(tungsten['Ingredient 1 Item ID']).toBe(TUNGSTEN_ORE)
    expect(tungsten['Ingredient 1 Quantity']).toBe(2)
    expect(tungsten['Ingredient 2 Item ID']).toBe(TIN_ORE)
    expect(tungsten['Ingredient 2 Quantity']).toBe(1)
    expect(launch.Actions.find((row) => row['Action ID'] === 'ACN-0136')?.['Proficiency Level']).toBe(60)

    const titanium = getRecipe(launch, TITANIUM_BAR_RECIPE)!
    expect(titanium['Proficiency Level']).toBe(70)
    expect(titanium['Ingredient 1 Item ID']).toBe(TITANIUM_ORE)
    expect(titanium['Ingredient 1 Quantity']).toBe(2)
    expect(titanium['Ingredient 2 Item ID']).toBe(IRON_ORE)
    expect(titanium['Ingredient 3 Item ID']).toBe(COPPER_ORE)
    expect(launch.Actions.find((row) => row['Action ID'] === 'ACN-0135')?.['Proficiency Level']).toBe(70)
  })

  it('data: every tungsten and titanium smithing project gates on 60 / 70 for both skills', () => {
    const projectIds = (from: number, to: number) =>
      Array.from({ length: to - from + 1 }, (_, i) => `PRJ-${String(from + i).padStart(4, '0')}`)
    for (const id of projectIds(105, 117)) {
      const project = launch.Projects.find((row) => row['Project ID'] === id)!
      expect(project['Display Name'], id).toMatch(/^Tungsten /)
      expect([project['Required Skill 1 ID'], project['Required Skill 1 Level']], id).toEqual([SMITHING, 60])
      expect([project['Required Skill 2 ID'], project['Required Skill 2 Level']], id).toEqual([METALLURGY, 60])
    }
    for (const id of projectIds(92, 104)) {
      const project = launch.Projects.find((row) => row['Project ID'] === id)!
      expect(project['Display Name'], id).toMatch(/^Titanium /)
      expect([project['Required Skill 1 ID'], project['Required Skill 1 Level']], id).toEqual([SMITHING, 70])
      expect([project['Required Skill 2 ID'], project['Required Skill 2 Level']], id).toEqual([METALLURGY, 70])
    }
  })

  it('data: mining the ores did not move (tungsten 55, titanium 70)', () => {
    expect(launch.Actions.find((row) => row['Action ID'] === 'ACN-0027')?.['Proficiency Level']).toBe(55)
    expect(
      launch.Requirements.find((row) => row['Requirement ID'] === 'REQ-0042')?.['Required Value'],
    ).toBe(55)
    expect(launch.Actions.find((row) => row['Action ID'] === 'ACN-0026')?.['Proficiency Level']).toBe(70)
  })

  it('refuses tungsten smelting at Metallurgy 59 and allows it at 60', () => {
    const refused = beginProductionQueue(launch, smelter(59), FURNACE_ACTIVITY, TUNGSTEN_BAR_RECIPE, 1, 0)
    expect(refused.ok).toBe(false)
    if (refused.ok) return
    expect(refused.reason).toBe('You have not learned that recipe yet.')

    const queued = beginProductionQueue(launch, smelter(60), FURNACE_ACTIVITY, TUNGSTEN_BAR_RECIPE, 1, 0)
    expect(queued.ok).toBe(true)
    if (!queued.ok) return
    expect(queued.save.productionRecipeId).toBe(TUNGSTEN_BAR_RECIPE)
    expect(inventoryCount(queued.save, TUNGSTEN_ORE)).toBe(18)
    expect(inventoryCount(queued.save, TIN_ORE)).toBe(9)
  })

  it('refuses titanium smelting at Metallurgy 69 and allows it at 70', () => {
    const refused = beginProductionQueue(launch, smelter(69), FURNACE_ACTIVITY, TITANIUM_BAR_RECIPE, 1, 0)
    expect(refused.ok).toBe(false)
    if (refused.ok) return
    expect(refused.reason).toBe('You have not learned that recipe yet.')

    const queued = beginProductionQueue(launch, smelter(70), FURNACE_ACTIVITY, TITANIUM_BAR_RECIPE, 1, 0)
    expect(queued.ok).toBe(true)
    if (!queued.ok) return
    expect(queued.save.productionRecipeId).toBe(TITANIUM_BAR_RECIPE)
    expect(inventoryCount(queued.save, TITANIUM_ORE)).toBe(18)
    expect(inventoryCount(queued.save, IRON_ORE)).toBe(9)
    expect(inventoryCount(queued.save, COPPER_ORE)).toBe(9)
  })

  it('refuses tungsten smithing below 60 on either skill and allows it at 60 / 60', () => {
    const lowSmithing = completeSpecialProject(
      launch,
      smith({ smithing: 59, metallurgy: 60 }),
      TUNGSTEN_SWORD_PROJECT,
      1,
      null,
      0,
    )
    expect(lowSmithing).toEqual({ ok: false, reason: 'Requires Smithing level 60.' })

    const lowMetallurgy = completeSpecialProject(
      launch,
      smith({ smithing: 60, metallurgy: 59 }),
      TUNGSTEN_SWORD_PROJECT,
      1,
      null,
      0,
    )
    expect(lowMetallurgy).toEqual({ ok: false, reason: 'Requires Metallurgy level 60.' })

    const forged = completeSpecialProject(
      launch,
      smith({ smithing: 60, metallurgy: 60 }),
      TUNGSTEN_SWORD_PROJECT,
      1,
      null,
      0,
    )
    expect(forged.ok).toBe(true)
    if (!forged.ok) return
    expect(forged.outputLabel).toBe('Tungsten Sword')
    expect(inventoryCount(forged.save, TUNGSTEN_SWORD)).toBe(1)
  })

  it('refuses titanium smithing below 70 on either skill and allows it at 70 / 70', () => {
    const lowSmithing = completeSpecialProject(
      launch,
      smith({ smithing: 69, metallurgy: 70 }),
      TITANIUM_SWORD_PROJECT,
      1,
      null,
      0,
    )
    expect(lowSmithing).toEqual({ ok: false, reason: 'Requires Smithing level 70.' })

    const lowMetallurgy = completeSpecialProject(
      launch,
      smith({ smithing: 70, metallurgy: 69 }),
      TITANIUM_SWORD_PROJECT,
      1,
      null,
      0,
    )
    expect(lowMetallurgy).toEqual({ ok: false, reason: 'Requires Metallurgy level 70.' })

    const forged = completeSpecialProject(
      launch,
      smith({ smithing: 70, metallurgy: 70 }),
      TITANIUM_SWORD_PROJECT,
      1,
      null,
      0,
    )
    expect(forged.ok).toBe(true)
    if (!forged.ok) return
    expect(forged.outputLabel).toBe('Titanium Sword')
    expect(inventoryCount(forged.save, 'ITEM-0250')).toBe(1)
  })

  it('a save that already holds tungsten and titanium bars and gear still loads and equips', () => {
    // Forged under the old 50 / 65 gates: the save format itself did not change,
    // so the stored version is current and only the player's levels are low.
    let before = withLevels(createNewSave(launch, 0), {
      [METALLURGY]: 50,
      [SMITHING]: 50,
      [MIGHT]: 60,
      [VITALITY]: 70,
    })
    before = addItemToInventory(before, TUNGSTEN_BAR, 7)
    before = addItemToInventory(before, TITANIUM_BAR, 3)
    before = addItemToInventory(before, TUNGSTEN_SWORD, 1)
    before = addItemToInventory(before, TITANIUM_HELMET, 1)
    const stored = JSON.parse(JSON.stringify({ ...before, saveVersion: SAVE_VERSION }))

    const loaded = parseSave(stored, 0)
    expect(inventoryCount(loaded, TUNGSTEN_BAR)).toBe(7)
    expect(inventoryCount(loaded, TITANIUM_BAR)).toBe(3)
    expect(inventoryCount(loaded, TUNGSTEN_SWORD)).toBe(1)
    expect(inventoryCount(loaded, TITANIUM_HELMET)).toBe(1)
    expect(loaded.skills.find((skill) => skill.skillId === METALLURGY)?.level).toBe(50)

    const sword = equipItemFromInventory(launch, loaded, TUNGSTEN_SWORD)
    expect(sword.ok).toBe(true)
    if (!sword.ok) return
    expect(sword.save.equipment.slots['SLOT-0001']?.itemId).toBe(TUNGSTEN_SWORD)

    const helmet = equipItemFromInventory(launch, sword.save, TITANIUM_HELMET)
    expect(helmet.ok).toBe(true)
    if (!helmet.ok) return
    expect(helmet.save.equipment.slots['SLOT-0003']?.itemId).toBe(TITANIUM_HELMET)
    expect(inventoryCount(helmet.save, TUNGSTEN_BAR)).toBe(7)
    expect(inventoryCount(helmet.save, TITANIUM_BAR)).toBe(3)
  })
})
