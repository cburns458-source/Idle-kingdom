import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { CRITTER_DEFS } from '../critters/critters'
import { prepareDatabase } from '../data/loadDatabase'
import { itemHasCapability } from '../equipment/loadout'
import { createNewSave } from '../save/saveStore'
import type { PlayerSave } from '../save/types'
import {
  CRITTER_COLLECTOR_ACHIEVEMENT_ID,
  asAchievementRows,
  hasEveryCritter,
  itemHasClassLabel,
  recordEnemyKill,
  recordGatheredDrops,
  recordItemsSoldAtLocation,
  recordProductionMilestones,
  recordProjectMilestones,
  syncProgressionMeta,
} from './progress'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

function unlocks(save: PlayerSave, achievementId: string, db = prepareDatabase(rawDatabase).launch) {
  return syncProgressionMeta(db, save).achievements.some(
    (row) => row.achievementId === achievementId && row.unlocked,
  )
}

function withSlots(save: PlayerSave, slots: Record<string, string>): PlayerSave {
  return {
    ...save,
    equipment: {
      slots: {
        ...save.equipment.slots,
        ...Object.fromEntries(
          Object.entries(slots).map(([slotId, itemId]) => [slotId, { itemId, quantity: 1 }]),
        ),
      },
    },
  }
}

describe('achievements and statistics', () => {
  it('lists the replacement deeds instead of skill-level milestones', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const rows = asAchievementRows(launch)
    expect(rows.map((row) => row['Display Name'])).toEqual([
      'Wizarding 101',
      'Iron man',
      'Beginner alchemist',
      'Just missing the hat',
      'Yumm',
      'Natural habitat',
      'That was harry',
      'Silver me timbers',
      'The Kings Crook',
      'Dwarven knowledge',
      'Dark nights',
      'Dragon!',
      'Critter collector',
    ])
    expect(rows.some((row) => row['Check Type'] === 'skill_all')).toBe(false)
    expect(rows.filter((row) => row.Difficulty === 'Easy')).toHaveLength(5)
    expect(rows.filter((row) => row.Difficulty === 'Medium')).toHaveLength(5)
    expect(rows.filter((row) => row.Difficulty === 'Hard')).toHaveLength(3)
  })

  it('holds Critter Collector only while the collection is complete', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)

    expect(hasEveryCritter(base)).toBe(false)
    expect(unlocks(base, CRITTER_COLLECTOR_ACHIEVEMENT_ID, launch)).toBe(false)

    const complete: PlayerSave = {
      ...base,
      critterCollections: CRITTER_DEFS.map((critter) => ({ critterId: critter.id, count: 1 })),
    }
    expect(hasEveryCritter(complete)).toBe(true)
    expect(unlocks(complete, CRITTER_COLLECTOR_ACHIEVEMENT_ID, launch)).toBe(true)

    const earned = syncProgressionMeta(launch, complete)
    const widened: PlayerSave = {
      ...earned,
      critterCollections: earned.critterCollections.slice(1),
    }
    expect(unlocks(widened, CRITTER_COLLECTOR_ACHIEVEMENT_ID, launch)).toBe(false)
    expect(unlocks(complete, CRITTER_COLLECTOR_ACHIEVEMENT_ID, launch)).toBe(true)
  })

  it('unlocks Wizarding 101 after one spell project', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    expect(unlocks(save, 'ACH-0028', launch)).toBe(false)
    save = recordProjectMilestones(launch, save, 'PRJ-0139', 1)
    expect(unlocks(save, 'ACH-0028', launch)).toBe(true)
  })

  it('unlocks Iron man and Dark nights from the current loadout', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    expect(unlocks(base, 'ACH-0029', launch)).toBe(false)

    const iron = withSlots(base, {
      'SLOT-0003': 'ITEM-0155',
      'SLOT-0004': 'ITEM-0156',
      'SLOT-0005': 'ITEM-0157',
      'SLOT-0006': 'ITEM-0158',
      'SLOT-0007': 'ITEM-0159',
      'SLOT-0002': 'ITEM-0147',
    })
    expect(unlocks(iron, 'ACH-0029', launch)).toBe(true)

    const tungstenNoShield = withSlots(base, {
      'SLOT-0003': 'ITEM-0267',
      'SLOT-0004': 'ITEM-0268',
      'SLOT-0005': 'ITEM-0269',
      'SLOT-0006': 'ITEM-0270',
      'SLOT-0007': 'ITEM-0271',
    })
    expect(unlocks(tungstenNoShield, 'ACH-0037', launch)).toBe(false)

    const tungsten = withSlots(tungstenNoShield, { 'SLOT-0002': 'ITEM-0266' })
    expect(unlocks(tungsten, 'ACH-0037', launch)).toBe(true)
  })

  it('unlocks Just missing the hat for a quiver plus any bow', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const quiverOnly = withSlots(base, { 'SLOT-0010': 'ITEM-0303' })
    expect(unlocks(quiverOnly, 'ACH-0031', launch)).toBe(false)

    const quiverAndSword = withSlots(quiverOnly, { 'SLOT-0001': 'ITEM-0128' })
    expect(unlocks(quiverAndSword, 'ACH-0031', launch)).toBe(false)

    const quiverAndBow = withSlots(quiverOnly, { 'SLOT-0001': 'ITEM-0135' })
    expect(itemHasCapability(launch, 'ITEM-0135', 'bow_combat_xp')).toBe(true)
    expect(unlocks(quiverAndBow, 'ACH-0031', launch)).toBe(true)
  })

  it('unlocks Yumm from eating a wild berry', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = {
      ...createNewSave(launch),
      statistics: { values: { 'consumed_ITEM-0028': 1 } },
    }
    expect(unlocks(save, 'ACH-0017', launch)).toBe(true)
  })

  it('requires location-specific crafts and smithing', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = recordProductionMilestones(
      launch,
      { ...save, currentLocationId: 'LOC-0023' },
      'ITEM-0073',
      1,
    )
    expect(unlocks(save, 'ACH-0030', launch)).toBe(false)

    save = recordProductionMilestones(
      launch,
      { ...save, currentLocationId: 'LOC-0026' },
      'ITEM-0073',
      1,
    )
    expect(unlocks(save, 'ACH-0030', launch)).toBe(true)

    save = recordProductionMilestones(
      launch,
      { ...save, currentLocationId: 'LOC-0023' },
      'ITEM-0069',
      1,
    )
    expect(unlocks(save, 'ACH-0035', launch)).toBe(false)
    save = recordProductionMilestones(
      launch,
      { ...save, currentLocationId: 'LOC-0015' },
      'ITEM-0069',
      1,
    )
    expect(unlocks(save, 'ACH-0035', launch)).toBe(true)

    save = recordProjectMilestones(
      launch,
      { ...save, currentLocationId: 'LOC-0025' },
      'PRJ-0011',
      1,
    )
    expect(unlocks(save, 'ACH-0036', launch)).toBe(false)
    save = recordProjectMilestones(
      launch,
      { ...save, currentLocationId: 'LOC-0038' },
      'PRJ-0011',
      1,
    )
    expect(unlocks(save, 'ACH-0036', launch)).toBe(true)
  })

  it('requires a successful salmon drop at the goblin camp with a goblin staff', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const missed = recordGatheredDrops(base, [], 'LOC-0003', 'ITEM-0122')
    expect(unlocks(missed, 'ACH-0032', launch)).toBe(false)

    const wrongTool = recordGatheredDrops(base, ['ITEM-0049'], 'LOC-0003', 'ITEM-0116')
    expect(unlocks(wrongTool, 'ACH-0032', launch)).toBe(false)

    const caught = recordGatheredDrops(base, ['ITEM-0049'], 'LOC-0003', 'ITEM-0122')
    expect(unlocks(caught, 'ACH-0032', launch)).toBe(true)
  })

  it('counts a boar kill by staff or wand label, not by item id', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(itemHasClassLabel(launch, 'ITEM-0304', 'staff')).toBe(true)
    expect(itemHasClassLabel(launch, 'ITEM-0307', 'wand')).toBe(true)
    expect(itemHasClassLabel(launch, 'ITEM-0122', 'staff')).toBe(false)

    const base = createNewSave(launch)
    const withSword = recordEnemyKill(
      launch,
      withSlots(base, { 'SLOT-0001': 'ITEM-0128' }),
      'ENM-0010',
    )
    expect(unlocks(withSword, 'ACH-0033', launch)).toBe(false)

    const withStaff = recordEnemyKill(
      launch,
      withSlots(base, { 'SLOT-0001': 'ITEM-0304' }),
      'ENM-0010',
    )
    expect(unlocks(withStaff, 'ACH-0033', launch)).toBe(true)

    const withWand = recordEnemyKill(
      launch,
      withSlots(base, { 'SLOT-0001': 'ITEM-0307' }),
      'ENM-0010',
    )
    expect(unlocks(withWand, 'ACH-0033', launch)).toBe(true)
  })

  it('unlocks Silver me timbers only at the general store', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const field = recordItemsSoldAtLocation(base, [{ itemId: 'ITEM-0288', quantity: 1 }], 'LOC-0009')
    expect(unlocks(field, 'ACH-0034', launch)).toBe(false)

    const store = recordItemsSoldAtLocation(base, [{ itemId: 'ITEM-0288', quantity: 1 }], 'LOC-0024')
    expect(unlocks(store, 'ACH-0034', launch)).toBe(true)
  })

  it('unlocks Dragon! from a dragon kill stat', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    expect(unlocks(recordEnemyKill(launch, base, 'ENM-0010'), 'ACH-0038', launch)).toBe(false)
    expect(unlocks(recordEnemyKill(launch, base, 'ENM-0006'), 'ACH-0038', launch)).toBe(true)
  })
})
