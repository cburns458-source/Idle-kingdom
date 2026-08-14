import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { applyHostileTravelArrival } from '../world/hostility'
import {
  requestActivityStart,
  requestActivityStop,
  requestProductionStart,
} from './transition'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('immediate activity changes (no change cooldown)', () => {
  it('starts an activity immediately', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const now = Date.parse('2026-01-01T00:00:00.000Z')
    let save = { ...createNewSave(launch), currentLocationId: 'LOC-0009' }

    const requested = requestActivityStart(launch, save, 'ACT-0012', now)
    expect(requested.ok).toBe(true)
    if (!requested.ok) return
    save = requested.save

    expect(save.activityTransition).toBeNull()
    expect(save.currentActivityId).toBe('ACT-0012')
    expect(save.currentActionId).toBeTruthy()
  })

  it('stops an activity immediately', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const now = Date.parse('2026-01-01T00:00:00.000Z')
    let save = { ...createNewSave(launch), currentLocationId: 'LOC-0009' }

    const started = requestActivityStart(launch, save, 'ACT-0012', now)
    expect(started.ok).toBe(true)
    if (!started.ok) return
    save = started.save

    const stopping = requestActivityStop(launch, save, now + 10_000)
    expect(stopping.ok).toBe(true)
    if (!stopping.ok) return
    expect(stopping.save.currentActivityId).toBeNull()
    expect(stopping.save.activityTransition).toBeNull()
  })

  it('replaces an activity immediately', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const now = Date.parse('2026-01-01T00:00:00.000Z')
    let save = { ...createNewSave(launch), currentLocationId: 'LOC-0001' }

    const first = requestActivityStart(launch, save, 'ACT-0001', now)
    expect(first.ok).toBe(true)
    if (!first.ok) return
    save = first.save

    const replaced = requestActivityStart(launch, save, 'ACT-0021', now + 10_000)
    expect(replaced.ok).toBe(true)
    if (!replaced.ok) return
    expect(replaced.save.activityTransition).toBeNull()
    expect(replaced.save.currentActivityId).toBe('ACT-0021')
  })

  it('blocks start and stop during death pause and keeps the activity', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const now = Date.parse('2026-01-01T00:00:00.000Z')
    const pausedIdle = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0009',
      deathPauseUntil: new Date(now + 30_000).toISOString(),
    }
    expect(requestActivityStart(launch, pausedIdle, 'ACT-0012', now).ok).toBe(false)

    const started = requestActivityStart(
      launch,
      { ...createNewSave(launch), currentLocationId: 'LOC-0009' },
      'ACT-0012',
      now,
    )
    expect(started.ok).toBe(true)
    if (!started.ok) return

    const paused = {
      ...started.save,
      deathPauseUntil: new Date(now + 30_000).toISOString(),
    }
    const stop = requestActivityStop(launch, paused, now + 1_000)
    expect(stop.ok).toBe(false)
    expect(stop.ok === false ? paused.currentActivityId : null).toBe('ACT-0012')
  })

  it('travel while busy stops the activity immediately with no cooldown', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const now = Date.parse('2026-01-01T00:00:00.000Z')
    let save = { ...createNewSave(launch), currentLocationId: 'LOC-0009' }

    const started = requestActivityStart(launch, save, 'ACT-0012', now)
    expect(started.ok).toBe(true)
    if (!started.ok) return
    save = started.save

    const arrived = applyHostileTravelArrival(launch, save, 'LOC-0001', now + 8_000)
    expect(arrived.forcedActivityId).toBeNull()
    expect(arrived.save.currentLocationId).toBe('LOC-0001')
    expect(arrived.save.currentActivityId).toBeNull()
    expect(arrived.save.activityTransition).toBeNull()
  })

  it('blocks stop and other starts in a hostile area', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const now = Date.parse('2026-01-01T00:00:00.000Z')
    const arrived = applyHostileTravelArrival(launch, createNewSave(launch), 'LOC-0003', now)
    expect(arrived.forcedActivityId).toBe('ACT-0002')
    const save = arrived.save

    const stop = requestActivityStop(launch, save, now + 1_000)
    expect(stop.ok).toBe(false)
    if (!stop.ok) expect(stop.reason).toMatch(/Leave this area/i)
    expect(save.currentActivityId).toBe('ACT-0002')

    const other = requestActivityStart(launch, save, 'ACT-0012', now + 1_000)
    expect(other.ok).toBe(false)
    if (!other.ok) expect(other.reason).toMatch(/hostile area/i)
  })

  it('Start queue replaces a running activity immediately', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const now = Date.parse('2026-01-01T00:00:00.000Z')
    let save = { ...createNewSave(launch), currentLocationId: 'LOC-0009' }

    const started = requestActivityStart(launch, save, 'ACT-0012', now)
    expect(started.ok).toBe(true)
    if (!started.ok) return
    save = {
      ...started.save,
      currentLocationId: 'LOC-0023',
      inventory: [...started.save.inventory, { itemId: 'ITEM-0025', quantity: 4 }],
    }

    const queued = requestProductionStart(launch, save, 'ACT-0017', 'RCP-0001', 2, now + 10_000)
    expect(queued.ok).toBe(true)
    if (!queued.ok) return
    expect(queued.save.activityTransition).toBeNull()
    expect(queued.save.currentActivityId).toBe('ACT-0017')
    expect(queued.save.productionRecipeId).toBe('RCP-0001')
    expect(queued.save.productionQuantityRemaining).toBe(2)
  })
})
