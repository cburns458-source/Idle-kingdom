import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { completeGatheringAction } from '../activity/engine'
import { playerDamageRange, playerMaxHp } from '../combat/stats'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { forcedHostileActivity } from '../world/hostility'
import { assignRace } from './assignRace'
import {
  applyRaceGoldGain,
  applyRaceSkillXp,
  raceStartingItems,
  races,
} from './races'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('playable races', () => {
  it('loads seven Launch races with unique starting kits', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const list = races(launch)
    expect(list.map((race) => race['Internal Key'])).toEqual([
      'human',
      'wood_elf',
      'high_elf',
      'orc',
      'goblin',
      'dwarf',
      'halfling',
    ])
    for (const race of list) {
      const kit = raceStartingItems(launch, race['Race ID'])
      expect(kit.length).toBeGreaterThan(0)
    }
  })

  it('grants the race starter kit only on the first race assignment', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const first = assignRace(launch, save, 'RACE-0006') // Dwarf
    expect(first.ok).toBe(true)
    if (!first.ok) return
    expect(first.grantedStarterKit).toBe(true)
    expect(first.save.raceId).toBe('RACE-0006')
    expect(first.save.inventory.find((stack) => stack.itemId === 'ITEM-0102')?.quantity).toBe(1)
    expect(first.save.inventory.find((stack) => stack.itemId === 'ITEM-0058')?.quantity).toBe(5)
    expect(first.save.inventory.find((stack) => stack.itemId === 'ITEM-0211')?.quantity).toBe(1)
    expect(first.save.gold).toBe(25)

    const changed = assignRace(launch, first.save, 'RACE-0001') // Human (test change)
    expect(changed.ok).toBe(true)
    if (!changed.ok) return
    expect(changed.grantedStarterKit).toBe(false)
    // Dwarf pickaxe remains; Human kit is not added again.
    expect(changed.save.inventory.find((stack) => stack.itemId === 'ITEM-0102')?.quantity).toBe(1)
    expect(changed.save.inventory.find((stack) => stack.itemId === 'ITEM-0103')).toBeUndefined()
    expect(changed.save.raceId).toBe('RACE-0001')
  })

  it('grants race-unique starters and shared potatoes/gold/potion', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const expected: Record<string, { uniqueItemId?: string; gold: number }> = {
      'RACE-0001': { uniqueItemId: 'ITEM-0103', gold: 25 }, // Human rod
      'RACE-0002': { uniqueItemId: 'ITEM-0108', gold: 25 }, // Wood Elf net
      'RACE-0003': { gold: 225 }, // High Elf +200 gold
      'RACE-0004': { uniqueItemId: 'ITEM-0224', gold: 25 }, // Orc bronze sword
      'RACE-0005': { uniqueItemId: 'ITEM-0225', gold: 25 }, // Goblin bronze dagger
      'RACE-0006': { uniqueItemId: 'ITEM-0102', gold: 25 }, // Dwarf pickaxe
      'RACE-0007': { uniqueItemId: 'ITEM-0101', gold: 25 }, // Halfling hatchet
    }
    for (const [raceId, { uniqueItemId, gold }] of Object.entries(expected)) {
      const assigned = assignRace(launch, createNewSave(launch), raceId)
      expect(assigned.ok).toBe(true)
      if (!assigned.ok) continue
      expect(assigned.save.gold).toBe(gold)
      expect(assigned.save.inventory.find((s) => s.itemId === 'ITEM-0058')?.quantity).toBe(5)
      expect(assigned.save.inventory.find((s) => s.itemId === 'ITEM-0211')?.quantity).toBe(1)
      if (uniqueItemId) {
        expect(assigned.save.inventory.find((s) => s.itemId === uniqueItemId)?.quantity).toBe(1)
      }
    }
  })

  it('applies High Elf +20% max HP and Orc +5% damage', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    expect(playerMaxHp(launch, base)).toBe(1000)
    expect(playerDamageRange(launch, base)).toEqual({ min: 10, max: 30 })

    const highElf = assignRace(launch, base, 'RACE-0003')
    expect(highElf.ok).toBe(true)
    if (!highElf.ok) return
    expect(playerMaxHp(launch, highElf.save)).toBe(1200)
    expect(highElf.save.maxHp).toBe(1200)

    const orc = assignRace(launch, base, 'RACE-0004')
    expect(orc.ok).toBe(true)
    if (!orc.ok) return
    expect(playerDamageRange(launch, orc.save)).toEqual({ min: 10, max: 31 })
  })

  it('applies Goblin gold bonus and Wood Elf hunting XP bonus', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const goblin = assignRace(launch, base, 'RACE-0005')
    expect(goblin.ok).toBe(true)
    if (!goblin.ok) return
    expect(applyRaceGoldGain(launch, goblin.save, 100)).toBe(105)

    const woodElf = assignRace(launch, base, 'RACE-0002')
    expect(woodElf.ok).toBe(true)
    if (!woodElf.ok) return
    expect(applyRaceSkillXp(launch, woodElf.save, 'SKL-0005', 100)).toBe(105)
    expect(applyRaceSkillXp(launch, woodElf.save, 'SKL-0002', 100)).toBe(100)
  })

  it('lets Goblin players skip Goblin Camp forced hostility but keep the activity available', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    expect(forcedHostileActivity(launch, base, 'LOC-0003')?.['Activity ID']).toBe('ACT-0002')

    const goblin = assignRace(launch, base, 'RACE-0005')
    expect(goblin.ok).toBe(true)
    if (!goblin.ok) return
    expect(forcedHostileActivity(launch, goblin.save, 'LOC-0003')).toBeNull()
    // Other hostile locations still force (Citadel grounds training).
    const citadel = forcedHostileActivity(launch, goblin.save, 'LOC-0032')
    expect(citadel).not.toBeNull()
  })

  it('grants Human woodcutting XP bonus when completing a woodcutting action', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    const assigned = assignRace(launch, save, 'RACE-0001')
    expect(assigned.ok).toBe(true)
    if (!assigned.ok) return
    save = assigned.save

    const woodcut = launch.Actions.find(
      (row) =>
        row['Relevant Skill ID'] === 'SKL-0006' &&
        typeof row['XP Reward'] === 'number' &&
        row.Status !== 'Needs Data',
    )
    expect(woodcut).toBeTruthy()
    const completed = completeGatheringAction(launch, save, woodcut!, () => 0)
    const baseXp = Number(woodcut!['XP Reward'] ?? 0)
    expect(completed.result.xpGained).toBe(Math.floor(baseXp * 1.05))
  })
})
