import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { beginActivitySave, generateNextAction } from '../activity/engine'
import { addItemToInventory } from '../activity/rewards'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import type { InventoryStack } from '../save/types'
import { applyGameCommand, CATCHING_UP_REASON, runPhase2Sync } from './authority'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

const START_MS = Date.parse('2026-01-01T00:00:00.000Z')

describe('phase 2 authority', () => {
  it('creates a named character', () => {
    const created = applyGameCommand(rawDatabase, {
      command: 'create_character',
      args: { name: 'Vari', raceId: 'RACE-0001' },
      nowMs: START_MS,
      random: () => 0,
    })
    expect(created.ok).toBe(true)
    if (!created.ok) return
    expect(created.save.characterName).toBe('Vari')
    expect(created.save.raceId).toBe('RACE-0001')
  })

  it('advances an idle save without inventing gold', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = {
      ...createNewSave(launch, START_MS),
      unattendedProgressAt: new Date(START_MS).toISOString(),
    }
    const later = START_MS + 180_000
    const result = runPhase2Sync(rawDatabase, {
      save,
      nowMs: later,
      rngState: 1,
    })
    expect(result.save.gold).toBe(save.gold)
    expect(result.effectiveElapsedMs).toBeGreaterThan(0)
  })

  it('starts meadow gathering from a command', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = { ...createNewSave(launch, START_MS), currentLocationId: 'LOC-0009' }
    const started = applyGameCommand(rawDatabase, {
      command: 'start_activity',
      args: { activityId: 'ACT-0012' },
      save,
      nowMs: START_MS,
      random: () => 0,
    })
    expect(started.ok).toBe(true)
    if (!started.ok) return
    expect(started.save.currentActivityId).toBe('ACT-0012')
  })

  it('gathers then sells from the hosted copy after time passes', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = { ...createNewSave(launch, START_MS), currentLocationId: 'LOC-0001' }
    const started = applyGameCommand(rawDatabase, {
      command: 'start_activity',
      args: { activityId: 'ACT-0021' },
      save,
      nowMs: START_MS,
      random: () => 0.1,
    })
    expect(started.ok).toBe(true)
    if (!started.ok) return

    const later = START_MS + 30_000
    const caughtUp = applyGameCommand(rawDatabase, {
      command: 'set_meta',
      args: {},
      save: started.save,
      nowMs: later,
      random: () => 0.1,
    })
    expect(caughtUp.ok).toBe(true)
    if (!caughtUp.ok) return
    expect(caughtUp.save.inventory.length).toBeGreaterThan(0)

    const sold = applyGameCommand(rawDatabase, {
      command: 'sell_inventory',
      args: { indexes: caughtUp.save.inventory.map((_, index) => index) },
      save: caughtUp.save,
      nowMs: later,
      random: () => 0.1,
    })
    expect(sold.ok).toBe(true)
    if (!sold.ok) return
    expect(sold.save.gold).toBeGreaterThan(caughtUp.save.gold)
    expect(sold.save.inventory).toHaveLength(0)
  })

  it('keeps the hosted save on ranking and PvP publish commands', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = { ...createNewSave(launch, START_MS), gold: 12 }
    for (const command of ['submit_leaderboard', 'save_pvp_equipment'] as const) {
      const result = applyGameCommand(rawDatabase, {
        command,
        save,
        nowMs: START_MS,
        random: () => 0,
      })
      expect(result.ok).toBe(true)
      if (!result.ok) return
      expect(result.save.gold).toBe(12)
    }
  })

  it('refuses an unknown command', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const refused = applyGameCommand(rawDatabase, {
      command: 'not_a_command',
      save: createNewSave(launch, START_MS),
      nowMs: START_MS,
      random: () => 0,
    })
    expect(refused.ok).toBe(false)
  })

  it('charges the founding gold for guild_create and refuses a short purse', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = { ...createNewSave(launch, START_MS), gold: 30 }
    const paid = applyGameCommand(rawDatabase, {
      command: 'guild_create',
      args: { name: 'Iron League', tag: 'IRN' },
      save,
      nowMs: START_MS,
      random: () => 0,
    })
    expect(paid.ok).toBe(true)
    if (paid.ok) expect(paid.save.gold).toBe(5)

    const poor = applyGameCommand(rawDatabase, {
      command: 'guild_create',
      args: { name: 'Iron League', tag: 'IRN' },
      save: { ...save, gold: 24 },
      nowMs: START_MS,
      random: () => 0,
    })
    expect(poor.ok).toBe(false)
  })

  it('wears the named item when loot has shifted the bag', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = { ...createNewSave(launch, START_MS), inventory: [] as InventoryStack[] }
    save = addItemToInventory(save, 'ITEM-0102', 1)
    save = {
      ...save,
      inventory: [{ itemId: 'ITEM-0005', quantity: 3 }, ...save.inventory],
    }
    const equipped = applyGameCommand(rawDatabase, {
      command: 'set_loadout',
      args: {
        slots: [{ slotId: 'SLOT-0001', itemId: 'ITEM-0102', quantity: 1 }],
        activeEquipmentPresetIndex: 0,
      },
      save,
      nowMs: START_MS,
      random: () => 0,
    })
    expect(equipped.ok).toBe(true)
    if (!equipped.ok) return
    expect(equipped.save.equipment.slots['SLOT-0001']?.itemId).toBe('ITEM-0102')
    expect(equipped.save.inventory.find((stack) => stack.itemId === 'ITEM-0102')).toBeUndefined()
    expect(equipped.save.inventory.find((stack) => stack.itemId === 'ITEM-0005')?.quantity).toBe(3)
    expect(equipped.save.activeEquipmentPresetIndex).toBe(0)
  })

  it('refuses a loadout item the player does not have', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const refused = applyGameCommand(rawDatabase, {
      command: 'set_loadout',
      args: {
        slots: [{ slotId: 'SLOT-0001', itemId: 'ITEM-0102', quantity: 1 }],
      },
      save: { ...createNewSave(launch, START_MS), inventory: [] as InventoryStack[] },
      nowMs: START_MS,
      random: () => 0,
    })
    expect(refused.ok).toBe(false)
    if (refused.ok) return
    expect(refused.reason).toBe('Item is not in inventory.')
  })

  it('eats the named food when the bag index has drifted', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = { ...createNewSave(launch, START_MS), inventory: [] as InventoryStack[] }
    save = addItemToInventory(save, 'ITEM-0058', 2)
    save = {
      ...save,
      inventory: [{ itemId: 'ITEM-0005', quantity: 1 }, ...save.inventory],
    }
    const eaten = applyGameCommand(rawDatabase, {
      command: 'eat_food',
      args: { inventoryIndex: 0, itemId: 'ITEM-0058' },
      save,
      nowMs: START_MS,
      random: () => 0,
    })
    expect(eaten.ok).toBe(true)
    if (!eaten.ok) return
    expect(eaten.save.inventory.find((stack) => stack.itemId === 'ITEM-0005')?.quantity).toBe(1)
    expect(eaten.save.inventory.find((stack) => stack.itemId === 'ITEM-0058')?.quantity).toBe(1)
  })

  it('deposits the named stack when the bag index has drifted', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = { ...createNewSave(launch, START_MS), inventory: [] as InventoryStack[] }
    save = addItemToInventory(save, 'ITEM-0005', 4)
    save = {
      ...save,
      inventory: [{ itemId: 'ITEM-0058', quantity: 1 }, ...save.inventory],
    }
    const deposited = applyGameCommand(rawDatabase, {
      command: 'bank_deposit',
      args: { inventoryIndex: 0, quantity: 2, itemId: 'ITEM-0005' },
      save,
      nowMs: START_MS,
      random: () => 0,
    })
    expect(deposited.ok).toBe(true)
    if (!deposited.ok) return
    expect(deposited.save.bank?.find((stack) => stack.itemId === 'ITEM-0005')?.quantity).toBe(2)
    expect(deposited.save.inventory.find((stack) => stack.itemId === 'ITEM-0058')?.quantity).toBe(1)
    expect(deposited.save.inventory.find((stack) => stack.itemId === 'ITEM-0005')?.quantity).toBe(2)
  })

  describe('long absences', () => {
    function gatheringAway(hours: number) {
      const { launch } = prepareDatabase(rawDatabase)
      let save = { ...createNewSave(launch, START_MS), currentLocationId: 'LOC-0009' }
      save = beginActivitySave(save, 'ACT-0012', new Date(START_MS).toISOString())
      const generated = generateNextAction(launch, save, 'ACT-0012', () => 0, START_MS)
      return {
        save: { ...generated!.save, unattendedProgressAt: new Date(START_MS).toISOString() },
        nowMs: START_MS + hours * 3_600_000,
      }
    }

    it('returns a partial sync instead of running past the budget', () => {
      const { save, nowMs } = gatheringAway(13)
      const first = runPhase2Sync(rawDatabase, { save, nowMs, rngState: 1, budgetMs: 0 })
      expect(first.caughtUp).toBe(false)
      expect(Date.parse(first.save.unattendedProgressAt!)).toBeLessThan(nowMs)

      let current = first.save
      let rngState = first.rngState
      for (let calls = 0; calls < 200; calls += 1) {
        const next = runPhase2Sync(rawDatabase, {
          save: current,
          nowMs,
          rngState,
          budgetMs: 20,
          windowStartMs: START_MS,
        })
        current = next.save
        rngState = next.rngState
        if (next.caughtUp) break
      }
      expect(current.unattendedProgressAt).toBe(new Date(nowMs).toISOString())
    }, 60_000)

    it('holds a command until the hosted save has caught up', () => {
      const { save, nowMs } = gatheringAway(13)
      const held = applyGameCommand(rawDatabase, {
        command: 'stop_activity',
        save,
        nowMs,
        random: () => 0,
        budgetMs: 0,
        windowStartMs: START_MS,
      })
      expect(held.ok).toBe(false)
      if (held.ok || !('catchingUp' in held)) throw new Error('expected a catch-up refusal')
      expect(held.reason).toBe(CATCHING_UP_REASON)
      expect(held.save.currentActivityId).toBe('ACT-0012')
      expect(Date.parse(held.save.unattendedProgressAt!)).toBeLessThan(nowMs)
    })

    it('applies a command once the catch-up fits in the budget', () => {
      const { save } = gatheringAway(0)
      const stopped = applyGameCommand(rawDatabase, {
        command: 'stop_activity',
        save,
        nowMs: START_MS + 60_000,
        random: () => 0,
      })
      expect(stopped.ok).toBe(true)
      if (!stopped.ok) return
      expect(stopped.save.currentActivityId).toBeNull()
    })
  })
})
