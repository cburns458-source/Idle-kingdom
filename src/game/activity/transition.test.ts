import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import {
  requestActivityStart,
  requestActivityStop,
  requestCancelForProductionPicker,
  requestProductionStart,
  resolveActivityTransitions,
} from './transition'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

describe('activity stop delay (starts are immediate)', () => {
  it('starts an activity immediately with no start cooldown', () => {
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

  it('delays activity stop while the activity keeps running', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const now = Date.parse('2026-01-01T00:00:00.000Z')
    let save = { ...createNewSave(launch), currentLocationId: 'LOC-0009' }

    const started = requestActivityStart(launch, save, 'ACT-0012', now)
    expect(started.ok).toBe(true)
    if (!started.ok) return
    save = started.save
    expect(save.currentActivityId).toBe('ACT-0012')

    const stopAt = now + 10_000
    const stopping = requestActivityStop(launch, save, stopAt)
    expect(stopping.ok).toBe(true)
    if (!stopping.ok) return
    save = stopping.save
    expect(save.currentActivityId).toBe('ACT-0012')
    expect(save.activityTransition?.kind).toBe('stopping')

    save = resolveActivityTransitions(launch, save, stopAt + 30_000)
    expect(save.activityTransition).toBeNull()
    expect(save.currentActivityId).toBeNull()
  })

  it('after stop completes, starting a new activity has no second cooldown', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const now = Date.parse('2026-01-01T00:00:00.000Z')
    let save = { ...createNewSave(launch), currentLocationId: 'LOC-0009' }

    const started = requestActivityStart(launch, save, 'ACT-0012', now)
    expect(started.ok).toBe(true)
    if (!started.ok) return
    save = started.save

    const stopAt = now + 10_000
    const stopping = requestActivityStop(launch, save, stopAt)
    expect(stopping.ok).toBe(true)
    if (!stopping.ok) return
    save = resolveActivityTransitions(launch, stopping.save, stopAt + 30_000)
    expect(save.currentActivityId).toBeNull()
    expect(save.activityTransition).toBeNull()

    const nextStart = requestActivityStart(launch, save, 'ACT-0012', stopAt + 30_000)
    expect(nextStart.ok).toBe(true)
    if (!nextStart.ok) return
    expect(nextStart.save.activityTransition).toBeNull()
    expect(nextStart.save.currentActivityId).toBe('ACT-0012')
  })

  it('replace uses one stop delay then starts the new activity immediately', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const now = Date.parse('2026-01-01T00:00:00.000Z')
    let save = { ...createNewSave(launch), currentLocationId: 'LOC-0001' }

    const first = requestActivityStart(launch, save, 'ACT-0001', now)
    expect(first.ok).toBe(true)
    if (!first.ok) return
    save = first.save
    expect(save.currentActivityId).toBe('ACT-0001')

    const replaceAt = now + 10_000
    const replaced = requestActivityStart(launch, save, 'ACT-0021', replaceAt)
    expect(replaced.ok).toBe(true)
    if (!replaced.ok) return
    save = replaced.save
    expect(save.currentActivityId).toBe('ACT-0001')
    expect(save.activityTransition?.kind).toBe('stopping')
    expect(save.activityTransition?.followUpActivityId).toBe('ACT-0021')
    expect(save.activityTransition?.durationMs).toBe(30_000)

    save = resolveActivityTransitions(launch, save, replaceAt + 30_000)
    expect(save.activityTransition).toBeNull()
    expect(save.currentActivityId).toBe('ACT-0021')
  })

  it('cancels a running activity before opening a production picker', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const now = Date.parse('2026-01-01T00:00:00.000Z')
    let save = { ...createNewSave(launch), currentLocationId: 'LOC-0009' }

    const started = requestActivityStart(launch, save, 'ACT-0012', now)
    expect(started.ok).toBe(true)
    if (!started.ok) return
    save = started.save

    const cancelAt = now + 10_000
    save = { ...save, currentLocationId: 'LOC-0002' }
    const cancel = requestCancelForProductionPicker(launch, save, 'ACT-0017', cancelAt)
    expect(cancel.ok).toBe(true)
    if (!cancel.ok) return
    save = cancel.save
    expect(save.activityTransition?.kind).toBe('stopping')

    save = resolveActivityTransitions(launch, save, cancelAt + 30_000)
    expect(save.currentActivityId).toBeNull()
    expect(save.activityTransition).toBeNull()
  })

  it('cancels an existing production queue before starting a new recipe', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const now = Date.parse('2026-01-01T00:00:00.000Z')
    let save = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0002',
      currentActivityId: 'ACT-0017',
      activityStartedAt: new Date(now).toISOString(),
      productionRecipeId: 'RCP-0001',
      productionQuantityTotal: 1,
      productionQuantityRemaining: 1,
    }

    const requested = requestProductionStart(launch, save, 'ACT-0017', 'RCP-0001', 2, now)
    expect(requested.ok).toBe(true)
    if (!requested.ok) return
    save = requested.save
    expect(save.activityTransition?.kind).toBe('stopping')
    expect(save.activityTransition?.followUpActivityId).toBe('ACT-0017')
    expect(save.activityTransition?.productionRecipeId).toBe('RCP-0001')
    expect(save.activityTransition?.productionQuantity).toBe(2)
  })
})
