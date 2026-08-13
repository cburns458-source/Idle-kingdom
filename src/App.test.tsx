import { act, render, screen } from '@testing-library/react'
import { readFileSync } from 'node:fs'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from './App'
import { beginActivitySave } from './game/activity/engine'
import { prepareDatabase, type LoadedDatabase } from './game/data/loadDatabase'
import { createNewSave } from './game/save/saveStore'
import { SAVE_STORAGE_KEY, type PlayerSave } from './game/save/types'

/**
 * The tick loop, driven through the real component tree.
 *
 * The rules and the session have their own tests; what only this level can catch
 * is the wiring around them going quiet — a frame loop that stops rescheduling,
 * a save that never makes it back into state, rewards that never reach the DOM.
 * So the loop here is driven a frame at a time with the clock held still between
 * frames, and every assertion is about what the player would see.
 */

const START_MS = Date.parse('2026-06-01T00:00:00.000Z')

/** Gather meadow supplies, whose actions are the shortest in the content. */
const MEADOW_LOCATION_ID = 'LOC-0009'
const MEADOW_ACTIVITY_ID = 'ACT-0012'

const rawDatabase: unknown = JSON.parse(
  readFileSync('content/data/game-database.json', 'utf8'),
)

let frameCallbacks: FrameRequestCallback[] = []

/** Runs the frames waiting on the clock, after moving it forward by [ms]. */
async function advance(ms: number) {
  vi.setSystemTime(Date.now() + ms)
  const pending = frameCallbacks
  frameCallbacks = []
  await act(async () => {
    for (const callback of pending) callback(ms)
  })
}

function storedSave(): PlayerSave {
  const raw = localStorage.getItem(SAVE_STORAGE_KEY)
  if (!raw) throw new Error('No save was written')
  return JSON.parse(raw) as PlayerSave
}

function rewardRowCount(): number {
  return document.querySelectorAll('.action-reward-row').length
}

function seedGatheringSave(db: LoadedDatabase) {
  const created = createNewSave(db.launch, START_MS)
  const named: PlayerSave = {
    ...created,
    characterName: 'Tester',
    raceId: db.launch.Races[0]['Race ID'],
    currentLocationId: MEADOW_LOCATION_ID,
  }
  localStorage.setItem(
    SAVE_STORAGE_KEY,
    JSON.stringify(beginActivitySave(named, MEADOW_ACTIVITY_ID, new Date(START_MS).toISOString())),
  )
}

describe('App tick loop', () => {
  beforeEach(async () => {
    vi.useFakeTimers()
    vi.setSystemTime(START_MS)
    localStorage.clear()
    frameCallbacks = []

    // The loop is stepped by hand instead of by a timer, so a frame only runs
    // at the moment the test says it does.
    vi.stubGlobal('requestAnimationFrame', (callback: FrameRequestCallback) => {
      frameCallbacks.push(callback)
      return frameCallbacks.length
    })
    vi.stubGlobal('cancelAnimationFrame', () => {})
    vi.stubGlobal('fetch', async () => ({ ok: true, json: async () => rawDatabase }))

    seedGatheringSave(prepareDatabase(rawDatabase))
  })

  afterEach(() => {
    vi.useRealTimers()
    vi.unstubAllGlobals()
  })

  it('runs a gathering activity, action after action', async () => {
    render(<App />)
    // Boot reads the database and the save before the first frame.
    await act(async () => {})
    expect(screen.getAllByText('Gather meadow supplies').length).toBeGreaterThan(0)

    // Boot's catch-up already rolled the first action, dated to now.
    const rolled = storedSave()
    expect(rolled.currentActionId).not.toBeNull()
    expect(rolled.actionDurationMs).toBeGreaterThan(0)
    expect(rewardRowCount()).toBe(0)

    // Halfway through, the action is still running.
    await advance(rolled.actionDurationMs! / 2)
    expect(storedSave().actionStartedAt).toBe(rolled.actionStartedAt)
    expect(rewardRowCount()).toBe(0)

    // Past the end, it pays out and the next action starts in the same frame.
    await advance(rolled.actionDurationMs! / 2 + 1)
    const first = storedSave()
    expect(rewardRowCount()).toBeGreaterThan(0)
    expect(first.actionStartedAt).not.toBe(rolled.actionStartedAt)
    expect(first.currentActionId).not.toBeNull()

    const xpAfterFirst = totalXp(first)
    expect(xpAfterFirst).toBeGreaterThan(0)

    // And again, so a stalled loop cannot pass by completing exactly once.
    await advance(first.actionDurationMs! + 1)
    const second = storedSave()
    expect(second.actionStartedAt).not.toBe(first.actionStartedAt)
    expect(totalXp(second)).toBeGreaterThan(xpAfterFirst)
    expect(rewardRowCount()).toBeGreaterThan(0)
  })

  it('keeps the progress bar in step with the running action', async () => {
    render(<App />)
    await act(async () => {})
    await advance(16)

    const duration = storedSave().actionDurationMs!
    await advance(duration / 4)
    expect(progressBarWidth()).toBeCloseTo(25, 0)

    await advance(duration / 2)
    expect(progressBarWidth()).toBeCloseTo(75, 0)
  })
})

function totalXp(save: PlayerSave): number {
  return save.skills.reduce((sum, skill) => sum + skill.xp, 0)
}

/** The action bar's fill, as a percentage. */
function progressBarWidth(): number {
  const bar = document.querySelector<HTMLElement>('.gather-progress-bar')
  if (!bar) throw new Error('No action progress bar is showing')
  return Number.parseFloat(bar.getAttribute('aria-valuenow') ?? '')
}
