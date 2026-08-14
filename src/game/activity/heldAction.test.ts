import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { applyCombatDefeat, applyCombatVictory } from '../combat/engine'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { completeGatheringAction, generateNextAction } from './engine'
import { withHeldAction } from './heldAction'
import { beginTravelActivityChange, requestActivityStart, requestActivityStop } from './transition'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('held pool actions', () => {
  it('keeps the rolled meadow action across stop and start', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = { ...createNewSave(launch), currentLocationId: 'LOC-0009' }

    const first = requestActivityStart(launch, save, 'ACT-0012', 0, () => 0)
    expect(first.ok).toBe(true)
    if (!first.ok) return
    save = first.save
    expect(save.currentActionId).toBe('ACN-0105')
    expect(save.heldActionByActivityId['ACT-0012']).toBe('ACN-0105')

    const stopped = requestActivityStop(launch, save, 1)
    expect(stopped.ok).toBe(true)
    if (!stopped.ok) return
    save = stopped.save
    expect(save.currentActivityId).toBeNull()
    expect(save.heldActionByActivityId['ACT-0012']).toBe('ACN-0105')

    const again = requestActivityStart(launch, save, 'ACT-0012', 2, () => 0.999)
    expect(again.ok).toBe(true)
    if (!again.ok) return
    expect(again.save.currentActionId).toBe('ACN-0105')
  })

  it('leaves the held meadow action in place after travel and another activity', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = { ...createNewSave(launch), currentLocationId: 'LOC-0009' }
    const started = requestActivityStart(launch, save, 'ACT-0012', 0, () => 0)
    expect(started.ok).toBe(true)
    if (!started.ok) return
    save = started.save

    save = beginTravelActivityChange(launch, save, 1)
    expect(save.currentActivityId).toBeNull()
    expect(save.heldActionByActivityId['ACT-0012']).toBe('ACN-0105')

    save = { ...save, currentLocationId: 'LOC-0001' }
    const farm = requestActivityStart(launch, save, 'ACT-0001', 2, () => 0)
    expect(farm.ok).toBe(true)
    if (!farm.ok) return
    save = farm.save
    expect(save.heldActionByActivityId['ACT-0012']).toBe('ACN-0105')

    const stopped = requestActivityStop(launch, save, 3)
    expect(stopped.ok).toBe(true)
    if (!stopped.ok) return
    save = { ...stopped.save, currentLocationId: 'LOC-0009' }
    const back = requestActivityStart(launch, save, 'ACT-0012', 4, () => 0.999)
    expect(back.ok).toBe(true)
    if (!back.ok) return
    expect(back.save.currentActionId).toBe('ACN-0105')
  })

  it('reuses a held action that is not in the activity pool', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = withHeldAction(
      { ...createNewSave(launch), currentLocationId: 'LOC-0009' },
      'ACT-0012',
      'ACN-0015',
    )
    const started = requestActivityStart(launch, save, 'ACT-0012', 0, () => 0)
    expect(started.ok).toBe(true)
    if (!started.ok) return
    expect(started.save.currentActionId).toBe('ACN-0015')
  })

  it('forgets a gathering action when it finishes so the next roll can change', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const started = requestActivityStart(
      launch,
      { ...createNewSave(launch), currentLocationId: 'LOC-0009' },
      'ACT-0012',
      0,
      () => 0,
    )
    expect(started.ok).toBe(true)
    if (!started.ok) return
    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0105')!
    const finished = completeGatheringAction(launch, started.save, action, () => 0)
    expect(finished.save.heldActionByActivityId['ACT-0012']).toBeUndefined()

    const next = generateNextAction(launch, finished.save, 'ACT-0012', () => 0.999, 10)
    expect(next?.action['Action ID']).not.toBe('ACN-0105')
    expect(next?.save.heldActionByActivityId['ACT-0012']).toBe(next?.action['Action ID'])
  })

  it('forgets a combat action on victory or defeat', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const started = requestActivityStart(
      launch,
      { ...createNewSave(launch), currentLocationId: 'LOC-0036' },
      'ACT-0035',
      0,
      () => 0,
    )
    expect(started.ok).toBe(true)
    if (!started.ok) return
    expect(started.save.heldActionByActivityId['ACT-0035']).toBe('ACN-0172')

    const action = launch.Actions.find((row) => row['Action ID'] === 'ACN-0172')!
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0020')!
    const won = applyCombatVictory(launch, started.save, action, enemy, () => 0, 1)
    expect(won.save.heldActionByActivityId['ACT-0035']).toBeUndefined()

    const lost = applyCombatDefeat(launch, started.save, 2)
    expect(lost.heldActionByActivityId['ACT-0035']).toBeUndefined()
  })
})
