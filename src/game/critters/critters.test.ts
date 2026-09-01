import { describe, expect, it } from 'vitest'
import { createNewSave } from '../save/saveStore'
import { prepareDatabase } from '../data/loadDatabase'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import {
  applyActivityTimeTowardCritters,
  collectCritter,
  CRITTER_HOUR_MS,
  activeSpawnAtLocation,
  spawnCritterAtLocation,
} from './critters'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('critters', () => {
  it('rolls once per activity hour and can spawn at Farm', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    let rolls = 0
    const result = applyActivityTimeTowardCritters(
      save,
      'LOC-0001',
      CRITTER_HOUR_MS * 5,
      Date.now(),
      () => {
        rolls += 1
        return rolls === 3 ? 0 : 0.99
      },
    )
    expect(result.hoursRolled).toBe(5)
    expect(result.spawned?.displayName).toBe('Fly')
    expect(activeSpawnAtLocation(result.save, 'LOC-0001')?.critterId).toBe('CRT-0001')
  })

  it('does not stack a second spawn while one is active', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    const first = applyActivityTimeTowardCritters(
      save,
      'LOC-0001',
      CRITTER_HOUR_MS,
      Date.now(),
      () => 0,
    )
    expect(first.spawned).toBeTruthy()
    save = first.save
    const second = applyActivityTimeTowardCritters(
      save,
      'LOC-0001',
      CRITTER_HOUR_MS * 10,
      Date.now(),
      () => 0,
    )
    expect(second.spawned).toBeNull()
    expect(save.activeCritterSpawns).toHaveLength(1)
  })

  it('collects and increments counters', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = applyActivityTimeTowardCritters(save, 'LOC-0001', CRITTER_HOUR_MS, Date.now(), () => 0)
      .save
    const first = collectCritter(save, 'LOC-0001')
    expect(first.ok).toBe(true)
    if (!first.ok) return
    expect(first.count).toBe(1)
    expect(first.save.cosmetics.unlocked).toContain('COS-0004')
    save = applyActivityTimeTowardCritters(
      first.save,
      'LOC-0001',
      CRITTER_HOUR_MS,
      Date.now(),
      () => 0,
    ).save
    const unlockedAfterFirst = first.save.cosmetics.unlocked.length
    const second = collectCritter(save, 'LOC-0001')
    expect(second.ok).toBe(true)
    if (!second.ok) return
    expect(second.count).toBe(2)
    // Second collect does not re-grant; unlock list stays the same size.
    expect(second.save.cosmetics.unlocked).toEqual(first.save.cosmetics.unlocked)
    expect(second.save.cosmetics.unlocked.length).toBe(unlockedAfterFirst)
  })

  it('unlocks COS-0004 on first Fly collect only', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    expect(save.cosmetics.unlocked).not.toContain('COS-0004')
    const spawned = spawnCritterAtLocation(save, 'LOC-0001')
    expect(spawned.ok).toBe(true)
    if (!spawned.ok) return
    const first = collectCritter(spawned.save, 'LOC-0001')
    expect(first.ok).toBe(true)
    if (!first.ok) return
    expect(first.save.cosmetics.unlocked).toContain('COS-0004')

    const again = spawnCritterAtLocation(first.save, 'LOC-0001')
    expect(again.ok).toBe(true)
    if (!again.ok) return
    const second = collectCritter(again.save, 'LOC-0001')
    expect(second.ok).toBe(true)
    if (!second.ok) return
    const flyPetGrants = second.save.cosmetics.unlocked.filter((id) => id === 'COS-0004')
    expect(flyPetGrants).toHaveLength(1)
  })

  it('force-spawns only when a habitat Critter is available and none is waiting', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    const nowhere = spawnCritterAtLocation(save, 'LOC-0009')
    expect(nowhere.ok).toBe(false)

    const first = spawnCritterAtLocation(save, 'LOC-0001')
    expect(first.ok).toBe(true)
    if (!first.ok) return
    expect(first.critter.displayName).toBe('Fly')
    save = first.save

    const blocked = spawnCritterAtLocation(save, 'LOC-0001')
    expect(blocked.ok).toBe(false)
  })
})
