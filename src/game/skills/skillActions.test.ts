import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import {
  actionsForSkill,
  projectsForSkill,
  skillMenuDisplayEntries,
  skillMenuEntries,
  skillMenuLine,
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
    expect(potatoes[0]?.level).toBe(10)
    expect(items.every((item) => !item.displayName.startsWith('ACN-'))).toBe(true)
    expect(items.some((item) => item.displayName === 'Gather fernleaf' && item.level === 5)).toBe(
      true,
    )
  })

  it('omits proficiency when the action has none', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const combat = actionsForSkill(launch, 'SKL-0001')
    expect(combat.length).toBeGreaterThan(0)
    expect(combat.every((item) => item.level == null)).toBe(true)
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

  it('groups smithing by material and numbers every menu row', () {
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
