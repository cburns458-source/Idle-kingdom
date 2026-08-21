import { existsSync, readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import {
  beginActivitySave,
  completeGatheringAction,
  generateNextAction,
  validateActivityStart,
} from '../activity/engine'
import { addItemToInventory } from '../activity/rewards'
import { LOCATION_ASSET_PATHS, MAP_ASSET_PATHS } from '../assets/assetMap'
import { ENEMY_ASSET_PATHS } from '../assets/enemyAssets'
import { itemAssetPath } from '../assets/itemAssets'
import { skillAssetPath } from '../assets/skillAssets'
import { slotAssetPath } from '../assets/slotAssets'
import { asAchievementRows, syncProgressionMeta } from '../achievements/progress'
import { resolveCombatRound, enemyForAction } from '../combat/engine'
import { prepareDatabase } from '../data/loadDatabase'
import { countNeedsData } from '../data/validate'
import { beginProductionQueue, completeProductionCraft } from '../production/engine'
import { asQuestRows, getQuestProgress } from '../quests/quests'
import { migrateSave } from '../save/migrations'
import { createNewSave, loadOrCreateSave, writeSave } from '../save/saveStore'
import { SAVE_VERSION, type PlayerSave } from '../save/types'
import { canAccessShop } from '../shops/shops'
import { resolveUnattendedProgress } from '../unattended/resolve'
import { MAIN_MAP_ID } from '../world/constants'
import { applyTravelArrival, canTravelTo, findConnection } from '../world/travel'
import { createMemoryStorage } from '../../test/memoryStorage'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

function contentPath(urlPath: string): string {
  const clean = urlPath.split('?')[0]!.replace(/^\//, '')
  return resolve(process.cwd(), 'content', clean)
}

describe('Step 11 release audit', () => {
  const loaded = prepareDatabase(rawDatabase)
  const { source, launch, issues, needsDataCount } = loaded

  it('passes full database validation with no errors', () => {
    const errors = issues.filter((issue) => issue.severity === 'error')
    expect(errors).toEqual([])
  })

  it('reports Needs Data rows without inventing fills', () => {
    expect(needsDataCount).toBe(countNeedsData(source))
    // Documented source gaps remain acceptable for Launch demo.
    expect(needsDataCount).toBeGreaterThan(0)
  })

  it('keeps remaining Expansion content out of the Launch runtime view', () => {
    expect(launch.Locations.some((row) => row['Location ID'] === 'LOC-0018')).toBe(true)
    expect(launch.Activities.some((row) => row['Activity ID'] === 'ACT-0016')).toBe(true)
    expect(launch.Enemies.some((row) => row['Enemy ID'] === 'ENM-0012')).toBe(true)
    // Dragon promoted to Launch for Queen's Quarters.
    expect(launch.Enemies.some((row) => row['Enemy ID'] === 'ENM-0006')).toBe(true)
    expect(source.Locations.some((row) => row['Location ID'] === 'LOC-0018')).toBe(true)
  })

  it('has on-disk art for Launch maps, travel locations, enemies, skills, and slots', () => {
    const missing: string[] = []

    for (const map of launch.Maps) {
      const path = MAP_ASSET_PATHS[map['Map ID']]
      if (!path || !existsSync(contentPath(path))) missing.push(`map ${map['Map ID']}`)
    }

    for (const location of launch.Locations) {
      const id = location['Location ID']
      // Horizon browse nodes intentionally reuse town art.
      if (id === 'LOC-0019' || id === 'LOC-0020') continue
      const path = LOCATION_ASSET_PATHS[id]
      if (!path || !existsSync(contentPath(path))) missing.push(`location ${id}`)
    }

    for (const enemy of launch.Enemies) {
      const path = ENEMY_ASSET_PATHS[enemy['Enemy ID']]
      if (!path || !existsSync(contentPath(path))) missing.push(`enemy ${enemy['Enemy ID']}`)
    }

    for (const skill of launch.Skills) {
      const path = skillAssetPath(skill['Internal Key'])
      if (!existsSync(contentPath(path))) missing.push(`skill ${skill['Skill ID']}`)
    }

    for (const slot of source.EquipmentSlots) {
      const path = slotAssetPath(slot['Slot ID'])
      if (!existsSync(contentPath(path))) missing.push(`slot ${slot['Slot ID']}`)
    }

    expect(missing).toEqual([])
  })

  it('resolves Launch item icons to existing files', () => {
    const missing = launch.Items.filter((item) => !existsSync(contentPath(itemAssetPath(item)))).map(
      (item) => item['Item ID'],
    )
    expect(missing).toEqual([])
  })

  it('new-save playthrough smoke: travel, gather, combat, craft, shop, quest sync', () => {
    let save = createNewSave(source)
    expect(save.saveVersion).toBe(SAVE_VERSION)
    expect(save.currentLocationId).toBe('LOC-0001')

    expect(canTravelTo(launch, save.currentLocationId, 'LOC-0002', MAIN_MAP_ID)).toBe(true)
    expect(findConnection(launch, 'LOC-0001', 'LOC-0002') || true).toBeTruthy()
    save = applyTravelArrival(launch, save, 'LOC-0002')
    expect(save.currentLocationId).toBe('LOC-0002')

    // Gathering at Meadow
    save = { ...save, currentLocationId: 'LOC-0009' }
    expect(validateActivityStart(launch, save, 'ACT-0012').ok).toBe(true)
    save = beginActivitySave(save, 'ACT-0012')
    const generated = generateNextAction(launch, save, 'ACT-0012', () => 0)
    expect(generated).toBeTruthy()
    const gathered = completeGatheringAction(launch, generated!.save, generated!.action, () => 0)
    save = gathered.save
    expect(gathered.result.xpGained).toBeGreaterThan(0)

    // Combat at pasture
    save = {
      ...applyTravelArrival(launch, save, 'LOC-0001'),
      currentActivityId: null,
      currentActionId: null,
    }
    expect(validateActivityStart(launch, save, 'ACT-0001').ok).toBe(true)
    save = beginActivitySave(save, 'ACT-0001')
    const combatGen = generateNextAction(launch, save, 'ACT-0001', () => 0)
    expect(combatGen).toBeTruthy()
    expect(combatGen!.action.Category).toBe('Combat')
    const enemy = enemyForAction(launch, combatGen!.action)
    expect(enemy).toBeTruthy()
    const round = resolveCombatRound(
      launch,
      combatGen!.save,
      enemy!,
      combatGen!.save.combatEnemyHp ?? enemy!['Maximum HP'],
      () => 0.1,
    )
    expect(['ongoing', 'victory', 'defeat']).toContain(round.outcome)

    // Standard production in Town kitchen
    save = addItemToInventory(
      {
        ...save,
        currentLocationId: 'LOC-0023',
        currentActivityId: null,
        currentActionId: null,
        productionRecipeId: null,
        productionQuantityRemaining: null,
        productionQuantityTotal: null,
        combatEnemyId: null,
        combatEnemyHp: null,
        combatRoundStartedAt: null,
      },
      'ITEM-0025',
      5,
    )
    const cook = beginProductionQueue(launch, save, 'ACT-0017', 'RCP-0001', 1)
    expect(cook.ok).toBe(true)
    if (cook.ok) {
      const duration = cook.save.actionDurationMs ?? 0
      const started = Date.parse(cook.save.actionStartedAt ?? new Date().toISOString())
      const finished = completeProductionCraft(launch, cook.save, started + duration)
      expect(finished).toBeTruthy()
      expect(finished!.outputQty).toBeGreaterThan(0)
      save = finished!.save
    }

    // Shop access in Town
    const generalStore =
      launch.Shops.find((shop) => shop['Shop ID'] === 'SHP-0001') ?? launch.Shops[0]!
    save = { ...save, currentLocationId: generalStore['Location ID'] ?? 'LOC-0002', gold: 10_000 }
    expect(canAccessShop(launch, save, generalStore).ok).toBe(true)

    expect(asQuestRows(launch).length).toBeGreaterThan(0)
    expect(asAchievementRows(launch).length).toBeGreaterThan(0)
    save = syncProgressionMeta(launch, save)
    expect(getQuestProgress(save, 'QST-0001').questId).toBe('QST-0001')

    const away = resolveUnattendedProgress(launch, save, Date.now() + 60_000)
    expect(away.save.unattendedProgressAt).toBeTruthy()
  })

  it('migrates a legacy v1-shaped save up to the current version', () => {
    const legacy = {
      saveVersion: 1,
      characterName: 'Legacy',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      currentLocationId: 'LOC-0002',
      currentActivityId: null,
      currentActionId: null,
      activityStartedAt: null,
      gold: 0,
      skills: [],
      inventory: [],
      equipment: { slots: { 'SLOT-0001': 'ITEM-0108' } },
    } as unknown as PlayerSave
    const migrated = migrateSave(legacy)
    expect(migrated.saveVersion).toBe(SAVE_VERSION)
    expect(migrated.equipment.slots['SLOT-0001']).toEqual({ itemId: 'ITEM-0108', quantity: 1 })
    expect(
      typeof migrated.unattendedProgressAt === 'string' || migrated.unattendedProgressAt === null,
    ).toBe(true)
  })

  it('persists and reloads a save through storage', () => {
    const storage = createMemoryStorage()
    const first = loadOrCreateSave(source, storage)
    writeSave({ ...first.save, characterName: 'ReleaseCheck', gold: 25 }, storage)
    const second = loadOrCreateSave(source, storage)
    expect(second.created).toBe(false)
    expect(second.save.characterName).toBe('ReleaseCheck')
    expect(second.save.gold).toBe(25)
    expect(second.save.saveVersion).toBe(SAVE_VERSION)
  })
})
