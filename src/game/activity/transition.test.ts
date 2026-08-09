import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import {
  requestActivityStart,
  requestActivityStop,
  resolveActivityTransitions,
  transitionRemainingMs,
} from './transition'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

describe('activity start/stop delay', () => {
  it('delays activity start by the configured 30 seconds', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const now = Date.parse('2026-01-01T00:00:00.000Z')
    let save = { ...createNewSave(launch), currentLocationId: 'LOC-0009' }

    const requested = requestActivityStart(launch, save, 'ACT-0012', now)
    expect(requested.ok).toBe(true)
    if (!requested.ok) return
    save = requested.save

    expect(save.currentActivityId).toBeNull()
    expect(save.activityTransition?.kind).toBe('starting')
    expect(save.activityTransition?.durationMs).toBe(30_000)
    expect(transitionRemainingMs(save, now + 10_000)).toBe(20_000)

    save = resolveActivityTransitions(launch, save, now + 29_999)
    expect(save.currentActivityId).toBeNull()
    expect(save.activityTransition?.kind).toBe('starting')

    save = resolveActivityTransitions(launch, save, now + 30_000)
    expect(save.activityTransition).toBeNull()
    expect(save.currentActivityId).toBe('ACT-0012')
  })

  it('delays activity stop while the activity keeps running', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const now = Date.parse('2026-01-01T00:00:00.000Z')
    let save = { ...createNewSave(launch), currentLocationId: 'LOC-0009' }

    const started = requestActivityStart(launch, save, 'ACT-0012', now)
    expect(started.ok).toBe(true)
    if (!started.ok) return
    save = resolveActivityTransitions(launch, started.save, now + 30_000)
    expect(save.currentActivityId).toBe('ACT-0012')

    const stopAt = now + 60_000
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

  it('replace chains a stop delay into a start delay', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const now = Date.parse('2026-01-01T00:00:00.000Z')
    let save = { ...createNewSave(launch), currentLocationId: 'LOC-0001' }

    const first = requestActivityStart(launch, save, 'ACT-0001', now)
    expect(first.ok).toBe(true)
    if (!first.ok) return
    save = resolveActivityTransitions(launch, first.save, now + 30_000)
    expect(save.currentActivityId).toBe('ACT-0001')

    const replaceAt = now + 60_000
    const replaced = requestActivityStart(launch, save, 'ACT-0021', replaceAt)
    expect(replaced.ok).toBe(true)
    if (!replaced.ok) return
    save = replaced.save
    expect(save.activityTransition?.kind).toBe('stopping')
    expect(save.activityTransition?.followUpActivityId).toBe('ACT-0021')

    save = resolveActivityTransitions(launch, save, replaceAt + 30_000)
    expect(save.currentActivityId).toBeNull()
    expect(save.activityTransition?.kind).toBe('starting')
    expect(save.activityTransition?.activityId).toBe('ACT-0021')

    save = resolveActivityTransitions(launch, save, replaceAt + 60_000)
    expect(save.activityTransition).toBeNull()
    expect(save.currentActivityId).toBe('ACT-0021')
  })
})
