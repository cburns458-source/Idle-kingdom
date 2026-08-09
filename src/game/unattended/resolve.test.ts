import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { beginActivitySave, generateNextAction } from '../activity/engine'
import { prepareDatabase } from '../data/loadDatabase'
import { beginProductionQueue } from '../production/engine'
import { addItemToInventory } from '../activity/rewards'
import { createNewSave } from '../save/saveStore'
import { resolveUnattendedProgress, unattendedCapMs } from './resolve'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

describe('unattended progression', () => {
  it('reads the 24-hour unattended cap from config', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(unattendedCapMs(launch)).toBe(24 * 3_600_000)
  })

  it('completes multiple gathering actions during a short absence', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, currentLocationId: 'LOC-0009' }
    const startedAt = Date.parse('2026-01-01T00:00:00.000Z')
    save = beginActivitySave(save, 'ACT-0012', new Date(startedAt).toISOString())
    const generated = generateNextAction(launch, save, 'ACT-0012', () => 0, startedAt)
    expect(generated).toBeTruthy()
    save = {
      ...generated!.save,
      unattendedProgressAt: new Date(startedAt).toISOString(),
    }

    // Meadow gathering actions are ~20s; two minutes covers several completions.
    const now = startedAt + 120_000
    const resolved = resolveUnattendedProgress(launch, save, now, () => 0)
    expect(resolved.gatheringActions).toBeGreaterThanOrEqual(3)
    expect(resolved.save.unattendedProgressAt).toBe(new Date(now).toISOString())
  })

  it('caps catch-up at unattended_cap even for longer absences', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, currentLocationId: 'LOC-0009' }
    const startedAt = Date.parse('2026-01-01T00:00:00.000Z')
    save = beginActivitySave(save, 'ACT-0012', new Date(startedAt).toISOString())
    const generated = generateNextAction(launch, save, 'ACT-0012', () => 0, startedAt)
    save = {
      ...generated!.save,
      unattendedProgressAt: new Date(startedAt).toISOString(),
    }

    const now = startedAt + 48 * 3_600_000
    const resolved = resolveUnattendedProgress(launch, save, now, () => 0)
    expect(resolved.effectiveElapsedMs).toBe(24 * 3_600_000)
    // Cap window only — a 48h absence must not simulate the second day.
    const uncapped = resolveUnattendedProgress(
      launch,
      {
        ...generated!.save,
        unattendedProgressAt: new Date(startedAt).toISOString(),
      },
      startedAt + 24 * 3_600_000,
      () => 0,
    )
    expect(resolved.gatheringActions).toBe(uncapped.gatheringActions)
    expect(resolved.gatheringActions).toBeGreaterThan(0)
  })

  it('advances a production queue within the capped window', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0025', 20)
    const startedAt = Date.parse('2026-01-01T00:00:00.000Z')
    const begun = beginProductionQueue(launch, save, 'ACT-0017', 'RCP-0001', 3, startedAt)
    expect(begun.ok).toBe(true)
    if (!begun.ok) return
    save = {
      ...begun.save,
      unattendedProgressAt: new Date(startedAt).toISOString(),
    }

    const recipeDuration = begun.save.actionDurationMs!
    const now = startedAt + recipeDuration * 3 + 100
    const resolved = resolveUnattendedProgress(launch, save, now, () => 0)
    expect(resolved.craftsCompleted).toBe(3)
    expect(resolved.save.productionRecipeId).toBeNull()
    expect(resolved.save.inventory.some((stack) => stack.itemId === 'ITEM-0058')).toBe(true)
  })

  it('resolves combat rounds with the live combat engine while away', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    // Tend the Pasture has combat pool entries.
    save = { ...save, currentLocationId: 'LOC-0001', currentHp: 1000 }
    const startedAt = Date.parse('2026-01-01T00:00:00.000Z')
    save = beginActivitySave(save, 'ACT-0001', new Date(startedAt).toISOString())

    // Force a combat action: cow/bull.
    const combatAction = launch.Actions.find(
      (action) =>
        action.Category === 'Combat' &&
        action['Action ID'] &&
        launch.PoolEntries.some(
          (entry) =>
            entry['Pool ID'] === 'POOL-0001' && entry['Action ID'] === action['Action ID'],
        ),
    )
    expect(combatAction).toBeTruthy()
    const enemy = launch.Enemies.find((row) => row['Enemy ID'] === combatAction!['Target ID'])
    expect(enemy).toBeTruthy()

    save = {
      ...save,
      unattendedProgressAt: new Date(startedAt).toISOString(),
      currentActionId: combatAction!['Action ID'],
      actionStartedAt: new Date(startedAt).toISOString(),
      actionDurationMs: null,
      combatEnemyId: enemy!['Enemy ID'],
      combatEnemyHp: enemy!['Maximum HP'],
      combatRoundStartedAt: new Date(startedAt).toISOString(),
    }

    const roundMs = 4_000
    const now = startedAt + roundMs * 40
    const resolved = resolveUnattendedProgress(launch, save, now, () => 0.99)
    expect(resolved.combatVictories + resolved.combatDeaths).toBeGreaterThan(0)
    expect(resolved.save.statistics.values.monsters_killed ?? 0).toBeGreaterThanOrEqual(
      resolved.combatVictories,
    )
  })
})
