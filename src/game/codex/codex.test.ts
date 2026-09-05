import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { GROUP_MINING, InventorySorter } from '../inventory/sort'
import { CodexIndex } from './codex'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('codex index', () => {
  const { launch } = prepareDatabase(rawDatabase)
  const sorter = new InventorySorter(launch)
  const codex = new CodexIndex(launch)

  it('lists every launch item and enemy', () => {
    expect(new Set(codex.items.map((row) => row.itemId))).toEqual(
      new Set(launch.Items.map((row) => row['Item ID'])),
    )
    expect(new Set(codex.enemies.map((row) => row.enemyId))).toEqual(
      new Set(launch.Enemies.map((row) => row['Enemy ID'])),
    )
    expect(codex.item('ITEM-0209')?.displayName).toBe('Ancient Alloy')
    expect(codex.item('ITEM-0276')?.displayName).toBe('Ancient Alloy Sword')
  })

  it('uses the same inventory groups as the bag', () => {
    for (const item of launch.Items) {
      expect(codex.item(item['Item ID'])!.group).toBe(sorter.groupOf(item['Item ID']))
    }
    expect(codex.itemsMatching(GROUP_MINING).every((row) => row.group === GROUP_MINING)).toBe(true)
    expect(codex.itemsMatching(undefined, 'copper').map((row) => row.itemId)).toContain('ITEM-0003')
  })

  it('links copper ore to its mine action', () => {
    const ore = codex.item('ITEM-0003')!
    expect(ore.obtainedFrom.some((row) => row.actionId === 'ACN-0018')).toBe(true)
    const mine = ore.obtainedFrom.find((row) => row.actionId === 'ACN-0018')!
    expect(mine.title.toLowerCase()).toContain('copper')
    expect(mine.locations.length).toBeGreaterThan(0)
  })

  it('shows recipes that make and use items', () => {
    const potato = codex.item('ITEM-0058')!
    expect(potato.craftedBy[0]?.isProject).toBe(false)
    expect(potato.craftedBy[0]?.ingredients.map((row) => row.itemId)).toContain('ITEM-0025')
    expect(codex.item('ITEM-0025')!.usedIn.some((row) => row.output.itemId === 'ITEM-0058')).toBe(
      true,
    )
  })

  it('shows projects that make and use items', () => {
    const sword = codex.item('ITEM-0128')!
    expect(sword.craftedBy[0]?.isProject).toBe(true)
    expect(sword.craftedBy[0]?.id).toBe('PRJ-0003')
    expect(codex.item('ITEM-0045')!.usedIn.some((row) => row.output.itemId === 'ITEM-0308')).toBe(
      true,
    )
  })

  it('lists cow drops and skeleton locations', () => {
    expect(codex.item('ITEM-0054')!.obtainedFrom.some((row) => row.enemyId === 'ENM-0001')).toBe(
      true,
    )
    const cow = codex.enemy('ENM-0001')!
    expect(cow.drops.map((row) => row.itemId)).toEqual(
      expect.arrayContaining(['ITEM-0054', 'ITEM-0045']),
    )
    expect(cow.drops.filter((row) => row.itemId === 'ITEM-0054')).toHaveLength(1)
    expect(cow.locations.map((row) => row.displayName)).toContain('The Farm')
    expect(codex.enemy('ENM-0008')!.locations.map((row) => row.displayName)).toEqual(
      expect.arrayContaining(["Wizard's Tower", 'Castle Crypt']),
    )
  })
})
