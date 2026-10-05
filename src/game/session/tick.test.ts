import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { beginActivitySave, generateNextAction } from '../activity/engine'
import { addItemToInventory } from '../activity/rewards'
import { prepareDatabase } from '../data/loadDatabase'
import { beginProductionQueue } from '../production/engine'
import { createNewSave } from '../save/saveStore'
import type { PlayerSave } from '../save/types'
import { advanceSession } from './tick'
import { actionProgressAt } from './progress'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

const { launch: db } = prepareDatabase(rawDatabase)
const START_MS = Date.parse('2026-01-01T00:00:00.000Z')
const START_ISO = new Date(START_MS).toISOString()

/** Always picks the first eligible pool entry, so runs are reproducible. */
const firstOfPool = () => 0

function newSave(overrides: Partial<PlayerSave> = {}): PlayerSave {
  return { ...createNewSave(db, START_MS), ...overrides }
}

function gathering(): PlayerSave {
  const begun = beginActivitySave(
    newSave({ currentLocationId: 'LOC-0009' }),
    'ACT-0012',
    START_ISO,
  )
  const generated = generateNextAction(db, begun, 'ACT-0012', firstOfPool, START_MS)
  expect(generated).toBeTruthy()
  return generated!.save
}

describe('session tick', () => {
  it('does nothing when no activity is running', () => {
    const save = newSave()
    const result = advanceSession(db, save, START_MS + 3_600_000, firstOfPool)
    expect(result.changed).toBe(false)
    expect(result.save).toBe(save)
    expect(result.events).toEqual([])
  })

  it('leaves an action alone until it is due', () => {
    const save = gathering()
    const result = advanceSession(db, save, START_MS + 1_000, firstOfPool)
    expect(result.changed).toBe(false)
    expect(result.save).toBe(save)
  })

  it('pays out a due action and rolls the next one', () => {
    const save = gathering()
    const dueMs = START_MS + save.actionDurationMs!
    const result = advanceSession(db, save, dueMs, firstOfPool)

    expect(result.changed).toBe(true)
    expect(result.events.map((event) => event.kind)).toContain('rewards')
    expect(result.save.currentActivityId).toBe('ACT-0012')
    expect(result.save.actionStartedAt).toBe(new Date(dueMs).toISOString())
  })

  it('stops an activity whose requirements no longer hold', () => {
    // Standing somewhere the meadow activity does not exist, so the payout lands
    // but rolling the next action finds the activity unstartable.
    const save = { ...gathering(), currentLocationId: 'LOC-0002' }
    const result = advanceSession(db, save, START_MS + save.actionDurationMs!, firstOfPool)

    expect(result.save.currentActivityId).toBeNull()
    expect(result.events.map((event) => event.kind)).toEqual(['rewards', 'activity-stopped'])
  })

  it('resolves both combat swings at 6s and does not pause for eat', () => {
    const armed = newSave({
      currentLocationId: 'LOC-0003',
      currentHp: 100_000,
      maxHp: 100_000,
    })
    const begun = beginActivitySave(armed, 'ACT-0002', START_ISO)
    const generated = generateNextAction(db, begun, 'ACT-0002', firstOfPool, START_MS)
    const fighting = generated!.save
    expect(fighting.combatEnemyId).toBeTruthy()
    expect(fighting.combatEatUntil).toBeTruthy()

    const tooEarly = advanceSession(db, fighting, START_MS + 2_999, firstOfPool)
    expect(tooEarly.changed).toBe(false)

    const midRound = advanceSession(db, fighting, START_MS + 5_999, firstOfPool)
    expect(midRound.save.combatEatUntil).toBeNull()
    expect(midRound.events.some((event) => event.kind === 'combat-round')).toBe(false)

    const clash = advanceSession(db, midRound.save, START_MS + 6_000, firstOfPool)
    expect(clash.save.combatEnemyHp!).toBeLessThan(fighting.combatEnemyHp!)
    const round = clash.events.find((event) => event.kind === 'combat-round')
    expect(round).toBeTruthy()
    if (round?.kind === 'combat-round') {
      expect(round.outcome === 'victory' || round.enemyHit != null).toBe(true)
      expect(round.bossInkActive).toBe(false)
    }
    expect(clash.save.combatRoundStartedAt).toBe(new Date(START_MS + 6_000).toISOString())
    expect(clash.save.combatEatUntil).toBe(new Date(START_MS + 9_000).toISOString())
  })

  it('auto-eats halfway through the next round and never adds eat time', () => {
    const armed = newSave({
      currentLocationId: 'LOC-0003',
      currentHp: 500,
      maxHp: 1000,
      equipment: {
        ...newSave().equipment,
        slots: {
          ...newSave().equipment.slots,
          'SLOT-0011': { itemId: 'ITEM-0058', quantity: 3 },
        },
      },
    })
    const begun = beginActivitySave(armed, 'ACT-0002', START_ISO)
    const generated = generateNextAction(db, begun, 'ACT-0002', firstOfPool, START_MS)
    const fighting = generated!.save
    expect(fighting.combatEnemyId).toBeTruthy()
    expect(fighting.equipment.slots['SLOT-0011']?.quantity).toBe(3)

    const firstEat = advanceSession(db, fighting, START_MS + 3_000, firstOfPool)
    expect(firstEat.save.equipment.slots['SLOT-0011']?.quantity).toBe(2)
    expect(firstEat.events.map((event) => event.kind)).toContain('food-healed')
    expect(firstEat.save.combatEatUntil).toBeNull()

    const clash = advanceSession(db, firstEat.save, START_MS + 6_000, firstOfPool)
    const round = clash.events.find(
      (event) => event.kind === 'combat-round' && event.outcome === 'ongoing',
    )
    expect(round).toBeTruthy()
    expect(clash.save.equipment.slots['SLOT-0011']?.quantity).toBe(2)
    expect(clash.events.map((event) => event.kind)).not.toContain('food-healed')
    expect(clash.save.combatEatUntil).toBe(new Date(START_MS + 9_000).toISOString())

    const afterEat = advanceSession(db, clash.save, START_MS + 9_000, firstOfPool)
    expect(afterEat.save.equipment.slots['SLOT-0011']?.quantity).toBe(1)
    expect(afterEat.events.map((event) => event.kind)).toContain('food-healed')
    expect(afterEat.save.combatEatUntil).toBeNull()
    expect(afterEat.save.combatRoundStartedAt).toBe(clash.save.combatRoundStartedAt)

    const killSetup = {
      ...afterEat.save,
      combatEnemyHp: 1,
      currentHp: 400,
      combatPlayerSwingApplied: false,
      combatPendingRound: null,
    }
    const kill = advanceSession(
      db,
      killSetup,
      Date.parse(killSetup.combatRoundStartedAt!) + 6_000,
      () => 0,
    )
    const killRound = kill.events.find(
      (event) => event.kind === 'combat-round' && event.outcome === 'victory',
    )
    expect(killRound).toBeTruthy()
    if (killRound?.kind === 'combat-round') {
      expect(killRound.enemyHit).toBeNull()
    }
    expect(kill.events.map((event) => event.kind)).toContain('enemy-defeated')
    expect(kill.events.map((event) => event.kind)).not.toContain('food-healed')
    expect(kill.save.combatEnemyId).toBeTruthy()
    expect(kill.save.combatRoundStartedAt).toBeTruthy()
    expect(kill.save.combatEatUntil).toBeTruthy()
  })

  it('holds everything until a death pause elapses, then recovers', () => {
    const paused: PlayerSave = {
      ...gathering(),
      deathPauseUntil: new Date(START_MS + 60_000).toISOString(),
    }

    const during = advanceSession(db, paused, START_MS + 30_000, firstOfPool)
    expect(during.changed).toBe(false)
    expect(during.save.deathPauseUntil).toBe(paused.deathPauseUntil)

    const after = advanceSession(db, paused, START_MS + 61_000, firstOfPool)
    expect(after.save.deathPauseUntil).toBeNull()
    expect(after.save.currentHp).toBe(Math.floor(after.save.maxHp * 0.5))
    expect(after.events.map((event) => event.kind)).toContain('recovered')
  })

  it('completes a craft and reports the item that came out', () => {
    const stocked = addItemToInventory(
      newSave({ currentLocationId: 'LOC-0023' }),
      'ITEM-0025',
      10,
    )
    const queued = beginProductionQueue(db, stocked, 'ACT-0017', 'RCP-0001', 2, START_MS)
    expect(queued.ok).toBe(true)
    const save = (queued as { ok: true; save: PlayerSave }).save
    const dueMs = START_MS + save.actionDurationMs!

    const result = advanceSession(db, save, dueMs, firstOfPool)
    const craft = result.events.find((event) => event.kind === 'craft-completed')
    expect(craft).toMatchObject({ itemId: 'ITEM-0058' })
    expect(result.save.productionQuantityRemaining).toBe(1)
  })

  it('emits inventory-full and leaves the queue when the bag cannot hold the output', () => {
    const stocked = addItemToInventory(
      newSave({ currentLocationId: 'LOC-0023' }),
      'ITEM-0025',
      10,
    )
    const queued = beginProductionQueue(db, stocked, 'ACT-0017', 'RCP-0001', 2, START_MS)
    expect(queued.ok).toBe(true)
    const save = {
      ...(queued as { ok: true; save: PlayerSave }).save,
      inventory: Array.from({ length: 180 }, (_, index) => ({
        itemId: `FILL-${index}`,
        quantity: 1,
      })),
    }
    const dueMs = START_MS + save.actionDurationMs!
    const result = advanceSession(db, save, dueMs, firstOfPool)
    expect(result.events.map((event) => event.kind)).toContain('inventory-full')
    expect(result.save.productionQuantityRemaining).toBe(2)
  })

  it('applies a legacy queued activity change and reports the save as moved', () => {
    const save: PlayerSave = {
      ...newSave({ currentLocationId: 'LOC-0009' }),
      activityTransition: {
        kind: 'starting',
        activityId: 'ACT-0012',
        followUpActivityId: null,
        productionRecipeId: null,
        productionQuantity: null,
        startedAt: START_ISO,
        durationMs: 5_000,
      },
    }

    const result = advanceSession(db, save, START_MS, firstOfPool)
    expect(result.changed).toBe(true)
    expect(result.save.activityTransition).toBeNull()
    expect(result.save.currentActivityId).toBe('ACT-0012')
  })
})

describe('action progress', () => {
  it('runs from 0 to 1 across the action and clamps past its end', () => {
    const save = gathering()
    const durationMs = save.actionDurationMs!
    expect(actionProgressAt(save, START_MS)).toBe(0)
    expect(actionProgressAt(save, START_MS + durationMs / 2)).toBeCloseTo(0.5)
    expect(actionProgressAt(save, START_MS + durationMs * 2)).toBe(1)
  })

  it('is zero without an action, and in combat, where the panel times rounds', () => {
    expect(actionProgressAt(newSave(), START_MS)).toBe(0)
    expect(
      actionProgressAt({ ...gathering(), combatEnemyId: 'ENM-0001' }, START_MS + 60_000),
    ).toBe(0)
  })
})
