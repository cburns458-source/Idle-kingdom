import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import {
  actionIsQuestOnly,
  actionsForSkill,
  projectsForSkill,
  skillMenuDisplayEntries,
  skillMenuEntries,
  skillMenuLine,
  skillMenuView,
} from './skillActions'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('skill menu entries', () => {
  it('lists harvesting actions by display name and drops duplicate Harvest potato', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const items = actionsForSkill(launch, 'SKL-0004')
    const potatoes = items.filter((item) => item.displayName === 'Harvest potato')
    expect(potatoes).toHaveLength(1)
    expect(potatoes[0]?.level).toBe(1)
    expect(items.every((item) => !item.displayName.startsWith('ACN-'))).toBe(true)
    expect(items.some((item) => item.displayName === 'Gather fernleaf' && item.level === 10)).toBe(
      true,
    )
  })

  it('omits proficiency when the action has none', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const combat = actionsForSkill(launch, 'SKL-0001')
    expect(combat.length).toBeGreaterThan(0)
    expect(combat.every((item) => item.level == null)).toBe(true)
    expect(combat.some((item) => item.displayName === 'Pressure the guards')).toBe(false)
    expect(actionIsQuestOnly(launch, 'ACN-0171')).toBe(true)
  })

  it('lists combat enemies by combat level and keeps steel battleaxes on Basic metal', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const combat = skillMenuView(launch, 'SKL-0001')
    expect(combat.tabs[0]?.label).toBe('Enemies')
    const goblin = combat.tabs[0]?.sections[0]?.entries.find((item) => item.displayName === 'Goblin Scout')
    expect(goblin?.level).toEqual(expect.any(Number))
    expect(skillMenuLine(goblin!)).toMatch(/^\d+\. Goblin Scout$/)

    const smithing = skillMenuView(launch, 'SKL-0011')
    expect(smithing.tabs.map((tab) => tab.label)).toEqual(['Basic metal', 'Other'])
    expect(
      smithing.tabs[0]?.sections[0]?.entries.some(
        (item) => item.displayName === 'Steel items' && item.level === 35,
      ),
    ).toBe(true)
    expect(smithing.tabs[1]?.sections[0]?.entries.some((item) => item.displayName === 'Warhammer')).toBe(
      true,
    )

    const artisanry = skillMenuView(launch, 'SKL-0012')
    expect(
      artisanry.tabs
        .find((tab) => tab.id === 'jewelry')
        ?.sections[0]?.entries.some((item) => item.displayName === 'Lucky Necklace'),
    ).toBe(true)
  })

  it('groups same-tier combat armor as material equipment', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const combat = skillMenuView(launch, 'SKL-0001')
    const gear = combat.tabs.find((tab) => tab.id === 'gear')?.sections[0]?.entries ?? []
    expect(gear.some((item) => item.displayName === 'Tungsten equipment')).toBe(true)
    expect(gear.some((item) => item.displayName === 'Reinforced Steel equipment')).toBe(true)
    expect(gear.some((item) => item.displayName === 'Bull Horn equipment')).toBe(true)
    expect(gear.some((item) => item.displayName === 'Tungsten Helmet')).toBe(false)
    expect(gear.some((item) => item.displayName === 'Tungsten Sword')).toBe(true)
    expect(gear.some((item) => item.displayName === 'Wooden Sword')).toBe(true)
  })

  it('lists smithing projects by output item name and required level', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const items = projectsForSkill(launch, 'SKL-0011')
    expect(items.length).toBeGreaterThan(0)
    expect(items.every((item) => !item.displayName.startsWith('PRJ-'))).toBe(true)
    expect(items.every((item) => !item.displayName.startsWith('ITEM-'))).toBe(true)
    const copperAxe = items.find((item) => item.displayName === 'Copper Axe')
    expect(copperAxe?.level).toBeTypeOf('number')
    expect(items[0]!.level!).toBeLessThanOrEqual(items[items.length - 1]!.level ?? Infinity)
  })

  it('lists arcana projects including enchantment and spell output names', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const items = skillMenuEntries(launch, 'SKL-0013')
    expect(items.some((item) => item.displayName === 'Strength Spell')).toBe(true)
    expect(items.some((item) => item.displayName === 'Minor Gathering Enchantment')).toBe(true)
    expect(items.find((item) => item.displayName === 'Minor Gathering Enchantment')?.level).toBe(20)
  })

  it('puts battle staves on an Arcana Weapons tab', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const arcana = skillMenuView(launch, 'SKL-0013')
    expect(arcana.tabs.map((tab) => tab.label)).toEqual(['Spells', 'Weapons', 'Enchantments'])
    const weapons = arcana.tabs.find((tab) => tab.id === 'weapons')?.sections[0]?.entries ?? []
    expect(weapons.map((item) => item.displayName)).toEqual([
      'Staff of Sparks',
      'Staff of Binding',
      "Mage's Wand",
      'Staff of Power',
    ])
    expect(weapons.find((item) => item.displayName === 'Staff of Sparks')?.level).toBe(35)
    expect(weapons.find((item) => item.displayName === 'Staff of Binding')?.level).toBe(45)
    expect(weapons.find((item) => item.displayName === 'Staff of Power')?.level).toBe(65)
    expect(
      arcana.tabs
        .find((tab) => tab.id === 'enchantments')
        ?.sections[0]?.entries.some((item) => item.displayName.startsWith('Staff of')),
    ).toBe(false)
  })

  it('does not list a net on the fishing Tools tab', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const fishing = skillMenuView(launch, 'SKL-0003')
    const tools = fishing.tabs.find((tab) => tab.id === 'tools')?.sections[0]?.entries ?? []
    expect(tools.some((item) => item.displayName === 'Net')).toBe(false)
    expect(tools.some((item) => item.displayName === 'Fishing Net')).toBe(false)
    expect(tools.some((item) => item.displayName.includes('Fishing Rod'))).toBe(true)
  })

  it('lists net and sling on the hunting Tools tab', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const hunting = skillMenuView(launch, 'SKL-0005')
    expect(hunting.tabs.map((tab) => tab.label)).toEqual(['Actions', 'Tools'])
    const tools = hunting.tabs.find((tab) => tab.id === 'tools')?.sections[0]?.entries ?? []
    expect(tools.some((item) => item.displayName === 'Net' && item.level === 1)).toBe(true)
    expect(tools.some((item) => item.displayName === 'Sling' && item.level === 5)).toBe(true)
  })

  it('groups smithing by material and numbers every menu row', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const mining = skillMenuDisplayEntries(launch, 'SKL-0002')
    expect(mining.some((item) => skillMenuLine(item).includes('Mine copper ore'))).toBe(true)
    expect(skillMenuLine(mining[0]!)).toMatch(/^\d+\. /)

    const smithing = skillMenuDisplayEntries(launch, 'SKL-0011')
    expect(smithing.some((item) => item.displayName === 'Tungsten items' && item.level === 70)).toBe(
      true,
    )
    expect(smithing.some((item) => item.displayName === 'Tungsten Sword')).toBe(false)
    expect(projectsForSkill(launch, 'SKL-0011').length).toBeGreaterThan(smithing.length)
  })
})
