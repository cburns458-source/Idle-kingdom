import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { applyCombatVictory } from '../combat/engine'
import { completeGatheringAction } from '../activity/engine'
import { beginProductionQueue, completeProductionCraft } from '../production/engine'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { addItemsToInventory } from '../activity/rewards'
import { TOTAL_XP_TRACKER_ID } from '../save/types'
import { pauseTrackers, resetLootTracker, resumeTrackers, trackersPaused, xpPerHour } from './trackers'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('trackers', () => {
  const { launch } = prepareDatabase(rawDatabase)
  const action = (id: string) => launch.Actions.find((row) => row['Action ID'] === id)!
  const enemy = (id: string) => launch.Enemies.find((row) => row['Enemy ID'] === id)!

  it('opens separate loot sections for cow and bull', () => {
    const fresh = createNewSave(launch, 1000)
    const cow = applyCombatVictory(launch, fresh, action('ACN-0001'), enemy('ENM-0001'), () => 0, 2000)
    const both = applyCombatVictory(launch, cow.save, action('ACN-0002'), enemy('ENM-0002'), () => 0, 3000)
    expect(Object.keys(both.save.lootTrackers)).toEqual(
      expect.arrayContaining(['enemy:ENM-0001', 'enemy:ENM-0002']),
    )
  })

  it('resetting cows leaves the bull section', () => {
    const fresh = createNewSave(launch, 1000)
    const cow = applyCombatVictory(launch, fresh, action('ACN-0001'), enemy('ENM-0001'), () => 0, 2000)
    const both = applyCombatVictory(launch, cow.save, action('ACN-0002'), enemy('ENM-0002'), () => 0, 3000)
    const reset = resetLootTracker(both.save, 'enemy:ENM-0001')
    expect(reset.lootTrackers['enemy:ENM-0001']).toBeUndefined()
    expect(reset.lootTrackers['enemy:ENM-0002']).toBeDefined()
  })

  it('starts an action loot section when mining copper', () => {
    const fresh = createNewSave(launch, 1000)
    const completed = completeGatheringAction(launch, fresh, action('ACN-0018'), () => 0, 4000)
    expect(completed.save.lootTrackers['action:ACN-0018']).toBeDefined()
    expect(completed.save.xpTrackers['SKL-0002']).toBeDefined()
    expect(completed.save.xpTrackers[TOTAL_XP_TRACKER_ID]).toBeDefined()
  })

  it('does not track standard production outputs as loot', () => {
    let save = addItemsToInventory(createNewSave(launch, 1000), 'ITEM-0025', 10).save
    save = { ...save, currentLocationId: 'LOC-0023' }
    const queued = beginProductionQueue(launch, save, 'ACT-0017', 'RCP-0001', 1, 1000)
    expect(queued.ok).toBe(true)
    if (!queued.ok) return
    const finished = completeProductionCraft(launch, queued.save, 5000, () => 0)
    expect(finished).not.toBeNull()
    expect(Object.keys(finished!.save.lootTrackers)).toEqual([])
    expect(finished!.save.xpTrackers[TOTAL_XP_TRACKER_ID]).toBeDefined()
  })

  it('starts stopped, with xp/hr at 0 until Start', () => {
    const fresh = createNewSave(launch, 1000)
    expect(trackersPaused(fresh)).toBe(true)
    const mined = completeGatheringAction(launch, fresh, action('ACN-0018'), () => 0, 4000)
    expect(trackersPaused(mined.save)).toBe(true)
    expect(xpPerHour(mined.save.xpTrackers['SKL-0002']!, 10_000, mined.save)).toBe(0)
    const started = resumeTrackers(mined.save, 10_000)
    expect(trackersPaused(started)).toBe(false)
    expect(started.xpTrackers['SKL-0002']!.startedAtMs).toBe(10_000)
    const gained = started.xpTrackers['SKL-0002']!.xpGained
    expect(xpPerHour(started.xpTrackers['SKL-0002']!, 10_000 + 3_600_000, started)).toBe(gained)
  })

  it('computes xp/hr from elapsed time', () => {
    expect(xpPerHour({ skillId: 'SKL-0001', startedAtMs: 0, xpGained: 3600 }, 3_600_000)).toBe(3600)
  })

  it('freezes xp/hr while stopped and excludes paused time after start', () => {
    const runningSave = resumeTrackers(createNewSave(launch, 1000), 1000)
    const mined = completeGatheringAction(launch, runningSave, action('ACN-0018'), () => 0, 4000)
    const running = xpPerHour(mined.save.xpTrackers['SKL-0002']!, 10_000, mined.save)
    const paused = pauseTrackers(mined.save, 10_000)
    expect(trackersPaused(paused)).toBe(true)
    expect(xpPerHour(paused.xpTrackers['SKL-0002']!, 20_000, paused)).toBe(running)
    const resumed = resumeTrackers(paused, 20_000)
    expect(trackersPaused(resumed)).toBe(false)
    expect(xpPerHour(resumed.xpTrackers['SKL-0002']!, 20_000, resumed)).toBe(running)
  })
})
