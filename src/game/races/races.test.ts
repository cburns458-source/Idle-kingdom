import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { completeGatheringAction } from '../activity/engine'
import { resolveActionRewards } from '../activity/rewards'
import { playerDamageRange, playerMaxHp } from '../combat/stats'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { canAccessShop } from '../shops/shops'
import { forcedHostileActivity } from '../world/hostility'
import { assignRace } from './assignRace'
import {
  applyRaceGoldGain,
  dwarvenMiningStoreRequiredLevel,
  raceSkillDropChanceBonusPercent,
  raceStartingItems,
  races,
} from './races'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

const SHARED_STARTER_ITEMS = [
  'ITEM-0102',
  'ITEM-0101',
  'ITEM-0103',
  'ITEM-0124',
  'ITEM-0001',
  'ITEM-0058',
]

describe('playable races', () => {
  it('loads seven Launch races with shared starting kits', () => {
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
      expect(kit.length).toBe(7)
      const itemIds = kit.map((row) => row['Item ID'])
      for (const itemId of SHARED_STARTER_ITEMS) {
        expect(itemIds).toContain(itemId)
      }
      if (race['Race ID'] === 'RACE-0005') {
        expect(itemIds).toContain('ITEM-0225')
        expect(itemIds).not.toContain('ITEM-0145')
      } else {
        expect(itemIds).toContain('ITEM-0145')
        expect(itemIds).not.toContain('ITEM-0225')
      }
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
    expect(first.save.gold).toBe(25)

    const changed = assignRace(launch, first.save, 'RACE-0001') // Human (test change)
    expect(changed.ok).toBe(true)
    if (!changed.ok) return
    expect(changed.grantedStarterKit).toBe(false)
    expect(changed.save.inventory.find((stack) => stack.itemId === 'ITEM-0102')?.quantity).toBe(1)
    expect(changed.save.raceId).toBe('RACE-0001')
  })

  it('grants the same shared starter kit and gold for every race', () => {
    const { launch } = prepareDatabase(rawDatabase)
    for (const raceId of [
      'RACE-0001',
      'RACE-0002',
      'RACE-0003',
      'RACE-0004',
      'RACE-0005',
      'RACE-0006',
      'RACE-0007',
    ]) {
      const assigned = assignRace(launch, createNewSave(launch), raceId)
      expect(assigned.ok).toBe(true)
      if (!assigned.ok) continue
      expect(assigned.save.gold).toBe(25)
      expect(assigned.save.inventory.find((s) => s.itemId === 'ITEM-0058')?.quantity).toBe(5)
      for (const itemId of ['ITEM-0102', 'ITEM-0101', 'ITEM-0103', 'ITEM-0124']) {
        expect(assigned.save.inventory.find((s) => s.itemId === itemId)?.quantity).toBe(1)
      }
      if (raceId === 'RACE-0005') {
        expect(assigned.save.inventory.find((s) => s.itemId === 'ITEM-0225')?.quantity).toBe(1)
      } else {
        expect(assigned.save.inventory.find((s) => s.itemId === 'ITEM-0145')?.quantity).toBe(1)
      }
    }
  })

  it('applies High Elf +20% max HP without Orc combat damage bonus', () => {
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
    expect(playerDamageRange(launch, orc.save)).toEqual({ min: 10, max: 30 })
  })

  it('applies Goblin gold bonus and Wood Elf hunting drop chance bonus', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const goblin = assignRace(launch, base, 'RACE-0005')
    expect(goblin.ok).toBe(true)
    if (!goblin.ok) return
    expect(applyRaceGoldGain(launch, goblin.save, 100)).toBe(105)

    const woodElf = assignRace(launch, base, 'RACE-0002')
    expect(woodElf.ok).toBe(true)
    if (!woodElf.ok) return
    expect(raceSkillDropChanceBonusPercent(launch, woodElf.save, 'SKL-0005')).toBe(5)
    expect(raceSkillDropChanceBonusPercent(launch, woodElf.save, 'SKL-0002')).toBe(0)
  })

  it('lets Goblin players skip Goblin Camp forced hostility but keep the activity available', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    expect(forcedHostileActivity(launch, base, 'LOC-0003')?.['Activity ID']).toBe('ACT-0002')

    const goblin = assignRace(launch, base, 'RACE-0005')
    expect(goblin.ok).toBe(true)
    if (!goblin.ok) return
    expect(forcedHostileActivity(launch, goblin.save, 'LOC-0003')).toBeNull()
    const docks = forcedHostileActivity(launch, goblin.save, 'LOC-0004')
    expect(docks).not.toBeNull()
  })

  it('opens Dwarven Mining Store at Mining 35 for Dwarves and 40 for others', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const shop = launch.Shops.find((row) => row['Shop ID'] === 'SHP-0002')!
    const mining35 = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0012',
      raceId: 'RACE-0006',
      skills: createNewSave(launch).skills.map((skill) =>
        skill.skillId === 'SKL-0002' ? { ...skill, level: 35, xp: 50_000 } : skill,
      ),
    }
    expect(dwarvenMiningStoreRequiredLevel(mining35)).toBe(35)
    expect(canAccessShop(launch, mining35, shop).ok).toBe(true)

    const human35 = { ...mining35, raceId: 'RACE-0001' }
    expect(dwarvenMiningStoreRequiredLevel(human35)).toBe(40)
    expect(canAccessShop(launch, human35, shop).ok).toBe(false)

    const human40 = {
      ...human35,
      skills: human35.skills.map((skill) =>
        skill.skillId === 'SKL-0002' ? { ...skill, level: 40, xp: 100_000 } : skill,
      ),
    }
    expect(canAccessShop(launch, human40, shop).ok).toBe(true)
  })

  it('applies Human woodcutting drop chance when rolling rewards', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    const assigned = assignRace(launch, save, 'RACE-0001')
    expect(assigned.ok).toBe(true)
    if (!assigned.ok) return
    save = assigned.save

    const woodcut = launch.Actions.find((row) => row['Action ID'] === 'ACN-0051')
    expect(woodcut).toBeTruthy()
    // Human +5% flat on 75% base → 80% effective drop chance.
    const dropped = resolveActionRewards(launch, save, woodcut!, () => 0.79)
    expect(dropped.loot.length).toBeGreaterThan(0)

    const missed = resolveActionRewards(launch, save, woodcut!, () => 0.8)
    expect(missed.loot).toHaveLength(0)
  })

  it('does not apply race XP bonuses when completing gathering actions', () => {
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
    expect(completed.result.xpGained).toBe(baseXp)
  })
})
