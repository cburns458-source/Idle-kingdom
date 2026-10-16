import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { beginActivitySave, generateNextAction } from '../activity/engine'
import { addItemToInventory } from '../activity/rewards'
import { prepareDatabase } from '../data/loadDatabase'
import { applyQuestAutoStartOnSeed } from '../quests/progress'
import { getQuestProgress } from '../quests/quests'
import { createNewSave } from '../save/saveStore'
import type { InventoryStack } from '../save/types'
import { commitGuildHallFromPlayerSaves } from '../guild/commit'
import {
  emptyGuildHallState,
  GUILD_HALL_GOLD_CAP_REFUSAL,
  GUILD_HALL_GOLD_OVERPAY_REFUSAL,
  normalizeGuildHallState,
} from '../guild/economy'
import { GUILD_HALL_GOLD_CAP } from '../guild/hall'
import { GUILD_BANK_LEVEL_TAKE_REFUSAL } from '../guild/permissions'
import {
  applyGameCommand,
  CATCHING_UP_REASON,
  isItemTradeable,
  runPhase2Sync,
  UNTRADEABLE_ITEM_REFUSAL,
} from './authority'

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

  it('quest_autostart_seed starts Green Thumb only once Getting Started is done, and nothing else', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const seeded = addItemToInventory(
      { ...createNewSave(launch, START_MS), currentLocationId: 'LOC-0001' },
      'ITEM-0324',
      1,
    )
    const run = (save: typeof seeded) =>
      applyGameCommand(rawDatabase, { command: 'quest_autostart_seed', save, nowMs: START_MS, random: () => 0 })

    const early = run(seeded)
    expect(early.ok).toBe(true)
    if (!early.ok) return
    expect(getQuestProgress(early.save, 'QST-0011').status).toBe('inactive')
    expect(early.save.quests).toEqual(seeded.quests)

    const ready = { ...seeded, quests: [{ questId: 'QST-0006', status: 'completed' as const, progress: 1 }] }
    const started = run(ready)
    expect(started.ok).toBe(true)
    if (!started.ok) return
    expect(getQuestProgress(started.save, 'QST-0011').status).toBe('active')
    expect(started.save.quests).toEqual(applyQuestAutoStartOnSeed(launch, ready).quests)
    expect(started.save.inventory).toEqual(ready.inventory)
    expect(started.save.gold).toBe(ready.gold)

    const again = run(started.save)
    expect(again.ok).toBe(true)
    if (!again.ok) return
    expect(again.save.quests).toEqual(started.save.quests)
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

  it('refuses to donate an untradeable item to the guild storehouse', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const hall = normalizeGuildHallState({
      debtRemaining: 0,
      debtPaidOff: true,
      debtPaidBy: {},
      storehouse: [],
      completedTiers: [],
    })
    const save = {
      ...createNewSave(launch, START_MS),
      inventory: [
        { itemId: 'ITEM-0406', quantity: 1 },
        { itemId: 'ITEM-0015', quantity: 10 },
      ],
    }
    const donate = (inventoryIndex: number, itemId: string) =>
      applyGameCommand(rawDatabase, {
        command: 'guild_donate_hall_item',
        args: { inventoryIndex, itemId, quantity: 1 },
        save,
        nowMs: START_MS,
        random: () => 0,
        hall,
        userId: 'u1',
        guildRole: 'member',
      })

    const machete = donate(0, 'ITEM-0406')
    expect(machete).toEqual({ ok: false, reason: UNTRADEABLE_ITEM_REFUSAL })
    expect(UNTRADEABLE_ITEM_REFUSAL).toBe("That stays with you; it can't be traded.")

    const cedar = donate(1, 'ITEM-0015')
    expect(cedar.ok).toBe(true)
    if (cedar.ok) expect(cedar.hall?.storehouse).toEqual([{ itemId: 'ITEM-0015', quantity: 1 }])
  })

  it('chips gold into one running total and refuses a short purse, overpay, or a full cap', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const hall = normalizeGuildHallState({
      goldContributed: 999_900,
      goldContributedBy: {},
      storehouse: [],
      completedTiers: [],
    })
    const save = { ...createNewSave(launch, START_MS), gold: 500 }
    const short = applyGameCommand(rawDatabase, {
      command: 'guild_chip_in_hall_gold',
      args: { amount: 600 },
      save,
      nowMs: START_MS,
      random: () => 0,
      hall,
      userId: 'u1',
      guildRole: 'member',
    })
    expect(short.ok).toBe(false)
    if (!short.ok) expect(short.reason).toBe('Not enough gold.')

    const overpay = applyGameCommand(rawDatabase, {
      command: 'guild_chip_in_hall_gold',
      args: { amount: 200 },
      save,
      nowMs: START_MS,
      random: () => 0,
      hall,
      userId: 'u1',
      guildRole: 'member',
    })
    expect(overpay).toEqual({ ok: false, reason: GUILD_HALL_GOLD_OVERPAY_REFUSAL })
    expect(save.gold).toBe(500)

    const first = applyGameCommand(rawDatabase, {
      command: 'guild_chip_in_hall_gold',
      args: { amount: 100 },
      save,
      nowMs: START_MS,
      random: () => 0,
      hall,
      userId: 'u1',
      guildRole: 'member',
    })
    expect(first.ok).toBe(true)
    if (!first.ok) return
    expect(first.goldChipped).toBe(100)
    expect(first.save.gold).toBe(400)
    expect(first.goldChipped).toBe(save.gold - first.save.gold)
    expect(first.hall?.goldContributed).toBe(1_000_000)
    expect(first.achievementsUnlocked).toEqual(
      expect.arrayContaining(['gach_gold_100k', 'gach_gold_500k']),
    )
    expect(first.achievementProgress?.find((row) => row.id === 'gach_gold_500k')?.unlocked).toBe(true)

    const second = applyGameCommand(rawDatabase, {
      command: 'guild_chip_in_hall_gold',
      args: { amount: 50 },
      save: first.save,
      nowMs: START_MS,
      random: () => 0,
      hall: first.hall,
      userId: 'u1',
      guildRole: 'member',
    })
    expect(second).toEqual({ ok: false, reason: GUILD_HALL_GOLD_CAP_REFUSAL })
    expect(first.save.gold).toBe(400)
  })

  it('refuses a hall gold chip-in when the guild role is missing', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const refused = applyGameCommand(rawDatabase, {
      command: 'guild_chip_in_hall_gold',
      args: { amount: 10 },
      save: { ...createNewSave(launch, START_MS), gold: 50 },
      nowMs: START_MS,
      random: () => 0,
      hall: emptyGuildHallState(),
      userId: 'u1',
    })
    expect(refused).toEqual({ ok: false, reason: 'Recruits cannot chip in gold.' })
  })

  it('refuses a hall gold chip-in when the guild role is empty', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const refused = applyGameCommand(rawDatabase, {
      command: 'guild_chip_in_hall_gold',
      args: { amount: 10 },
      save: { ...createNewSave(launch, START_MS), gold: 50 },
      nowMs: START_MS,
      random: () => 0,
      hall: emptyGuildHallState(),
      userId: 'u1',
      guildRole: '',
    })
    expect(refused).toEqual({ ok: false, reason: 'Recruits cannot chip in gold.' })
  })

  it('ignores a forged hall payload that claims the gold cap without deducting gold', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = { ...createNewSave(launch, START_MS), gold: 500 }
    const honest = applyGameCommand(rawDatabase, {
      command: 'guild_chip_in_hall_gold',
      args: { amount: 40 },
      save,
      nowMs: START_MS,
      random: () => 0,
      hall: emptyGuildHallState(),
      userId: 'u1',
      guildRole: 'member',
    })
    expect(honest.ok).toBe(true)
    if (!honest.ok) return
    expect(honest.goldChipped).toBe(40)
    expect(honest.save.gold).toBe(460)

    const forged = commitGuildHallFromPlayerSaves({
      previousGold: save.gold,
      nextGold: save.gold,
      previousInventory: save.inventory,
      nextInventory: save.inventory,
      hall: emptyGuildHallState(),
      userId: 'u1',
      proposed: {
        goldContributed: GUILD_HALL_GOLD_CAP,
        completedTiers: ['build_the_hall', 'hall_bank'],
        storehouse: honest.hall?.storehouse,
      },
    })
    expect(forged.ok).toBe(true)
    if (!forged.ok) return
    expect(forged.goldTaken).toBe(0)
    expect(forged.hall.goldContributed).toBe(0)
    expect(forged.hall.completedTiers).toEqual([])
  })

  it('refuses to deposit an untradeable item in the guild bank', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const hall = normalizeGuildHallState({
      goldContributed: 10_000,
      goldContributedBy: {},
      storehouse: [],
      completedTiers: ['build_the_hall', 'hall_bank'],
    })
    const save = {
      ...createNewSave(launch, START_MS),
      inventory: [
        { itemId: 'ITEM-0406', quantity: 1 },
        { itemId: 'ITEM-0015', quantity: 4 },
      ],
    }
    const machete = applyGameCommand(rawDatabase, {
      command: 'guild_bank_deposit',
      args: { inventoryIndex: 0, itemId: 'ITEM-0406', quantity: 1 },
      save,
      nowMs: START_MS,
      random: () => 0,
      hall,
      userId: 'u1',
      guildRole: 'member',
      totalLevel: 50,
      nextId: () => 'gb-bound',
    })
    expect(machete).toEqual({ ok: false, reason: UNTRADEABLE_ITEM_REFUSAL })

    const cedar = applyGameCommand(rawDatabase, {
      command: 'guild_bank_deposit',
      args: { inventoryIndex: 1, itemId: 'ITEM-0015', quantity: 4 },
      save,
      nowMs: START_MS,
      random: () => 0,
      hall,
      userId: 'u1',
      guildRole: 'member',
      totalLevel: 50,
      nextId: () => 'gb-1',
    })
    expect(cedar.ok).toBe(true)
    if (!cedar.ok) return
    expect(cedar.bank?.items).toEqual([
      { id: 'gb-1', itemId: 'ITEM-0015', quantity: 4, section: 'main' },
    ])
  })

  it('lets a low-level member deposit in the guild bank but not withdraw', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const hall = normalizeGuildHallState({
      goldContributed: 10_000,
      goldContributedBy: {},
      storehouse: [],
      completedTiers: ['build_the_hall', 'hall_bank'],
    })
    const save = {
      ...createNewSave(launch, START_MS),
      inventory: [{ itemId: 'ITEM-0015', quantity: 4 }],
    }
    const deposited = applyGameCommand(rawDatabase, {
      command: 'guild_bank_deposit',
      args: { inventoryIndex: 0, itemId: 'ITEM-0015', quantity: 4 },
      save,
      nowMs: START_MS,
      random: () => 0,
      hall,
      userId: 'u1',
      guildRole: 'member',
      totalLevel: 50,
      nextId: () => 'gb-1',
    })
    expect(deposited.ok).toBe(true)
    if (!deposited.ok) return
    expect(deposited.bank?.items).toEqual([
      { id: 'gb-1', itemId: 'ITEM-0015', quantity: 4, section: 'main' },
    ])

    const withdrawn = applyGameCommand(rawDatabase, {
      command: 'guild_bank_withdraw',
      args: { itemId: 'ITEM-0015', quantity: 1 },
      save: deposited.save,
      nowMs: START_MS,
      random: () => 0,
      hall,
      guildBank: deposited.bank,
      userId: 'u1',
      guildRole: 'member',
      totalLevel: 50,
    })
    expect(withdrawn.ok).toBe(false)

    const takenAtLevel = applyGameCommand(rawDatabase, {
      command: 'guild_bank_withdraw',
      args: { itemId: 'ITEM-0015', quantity: 1 },
      save: deposited.save,
      nowMs: START_MS,
      random: () => 0,
      hall,
      guildBank: deposited.bank,
      userId: 'u1',
      guildRole: 'officer',
      totalLevel: 200,
    })
    expect(takenAtLevel.ok).toBe(true)
  })

  it('moves a stack to Up for grabs so any member can take it once', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const hall = normalizeGuildHallState({
      goldContributed: 10_000,
      goldContributedBy: {},
      storehouse: [],
      completedTiers: ['build_the_hall', 'hall_bank'],
    })
    const save = createNewSave(launch, START_MS)
    const bank = {
      items: [{ id: 'gb-1', itemId: 'ITEM-0015', quantity: 2, section: 'main' as const }],
    }
    const moved = applyGameCommand(rawDatabase, {
      command: 'guild_bank_move_up_for_grabs',
      args: { itemId: 'ITEM-0015', quantity: 2 },
      save,
      nowMs: START_MS,
      random: () => 0,
      hall,
      guildBank: bank,
      userId: 'u1',
      guildRole: 'leader',
      nextId: () => 'gb-2',
    })
    expect(moved.ok).toBe(true)
    if (!moved.ok) return
    const tooLow = applyGameCommand(rawDatabase, {
      command: 'guild_bank_take_up_for_grabs',
      args: { itemId: 'ITEM-0015', quantity: 2 },
      save: moved.save,
      nowMs: START_MS,
      random: () => 0,
      hall,
      guildBank: moved.bank,
      userId: 'u2',
      guildRole: 'recruit',
      totalLevel: 199,
    })
    expect(tooLow.ok).toBe(false)
    if (!tooLow.ok) expect(tooLow.reason).toBe(GUILD_BANK_LEVEL_TAKE_REFUSAL)

    const first = applyGameCommand(rawDatabase, {
      command: 'guild_bank_take_up_for_grabs',
      args: { itemId: 'ITEM-0015', quantity: 2 },
      save: moved.save,
      nowMs: START_MS,
      random: () => 0,
      hall,
      guildBank: moved.bank,
      userId: 'u2',
      guildRole: 'recruit',
      totalLevel: 200,
    })
    expect(first.ok).toBe(true)
    if (!first.ok) return
    const second = applyGameCommand(rawDatabase, {
      command: 'guild_bank_take_up_for_grabs',
      args: { itemId: 'ITEM-0015', quantity: 2 },
      save: first.save,
      nowMs: START_MS,
      random: () => 0,
      hall,
      guildBank: first.bank,
      userId: 'u3',
      guildRole: 'member',
      totalLevel: 200,
    })
    expect(second.ok).toBe(false)
  })

  it('a member under total level 200 is refused on Up for grabs Take', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const hall = normalizeGuildHallState({
      goldContributed: 10_000,
      goldContributedBy: {},
      storehouse: [],
      completedTiers: ['build_the_hall', 'hall_bank'],
    })
    const save = createNewSave(launch, START_MS)
    const bank = {
      items: [{ id: 'gb-1', itemId: 'ITEM-0015', quantity: 1, section: 'up_for_grabs' as const }],
    }
    const refused = applyGameCommand(rawDatabase, {
      command: 'guild_bank_take_up_for_grabs',
      args: { itemId: 'ITEM-0015', quantity: 1 },
      save,
      nowMs: START_MS,
      random: () => 0,
      hall,
      guildBank: bank,
      userId: 'u2',
      guildRole: 'member',
      totalLevel: 50,
    })
    expect(refused.ok).toBe(false)
    if (refused.ok) return
    expect(refused.reason).toBe('Reach total level 200 to take from Up for grabs.')
    expect(refused.reason).toBe(GUILD_BANK_LEVEL_TAKE_REFUSAL)
  })

  it('two Up for grabs takes of the same item at once: the second commit is 409 Hall changed', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const hall = normalizeGuildHallState({
      goldContributed: 10_000,
      goldContributedBy: {},
      storehouse: [],
      completedTiers: ['build_the_hall', 'hall_bank'],
    })
    const bank = {
      items: [{ id: 'gb-1', itemId: 'ITEM-0015', quantity: 2, section: 'up_for_grabs' as const }],
    }
    const take = (userId: string) =>
      applyGameCommand(rawDatabase, {
        command: 'guild_bank_take_up_for_grabs',
        args: { itemId: 'ITEM-0015', quantity: 2 },
        save: createNewSave(launch, START_MS),
        nowMs: START_MS,
        random: () => 0,
        hall,
        guildBank: bank,
        userId,
        guildRole: 'member',
        totalLevel: 200,
      })

    const first = take('u1')
    const raced = take('u2')
    expect(first.ok).toBe(true)
    expect(raced.ok).toBe(true)

    const expectedRevision = 0
    const afterFirstCommit = expectedRevision + 1
    const hallChanged = (expectedRevision ?? 0) !== (afterFirstCommit ?? 0)
    expect(hallChanged).toBe(true)

    const gameSource = readFileSync(resolve(process.cwd(), 'supabase/functions/game/index.ts'), 'utf8')
    expect(gameSource).toContain("error.message.includes('Hall changed')")
    expect(gameSource).toMatch(/conflict \? 409/)

    const sqlSource = readFileSync(
      resolve(process.cwd(), 'supabase/migrations/20261016150000_guild_commit_hall_caught_up_save.sql'),
      'utf8',
    )
    expect(sqlSource).toContain("Hall changed. Sync and retry.")
  })

  it('refuses bank withdraw and move to Up for grabs when the rank has no permission', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const hall = normalizeGuildHallState({
      goldContributed: 10_000,
      goldContributedBy: {},
      storehouse: [],
      completedTiers: ['build_the_hall', 'hall_bank'],
    })
    const save = createNewSave(launch, START_MS)
    const bank = {
      items: [{ id: 'gb-1', itemId: 'ITEM-0015', quantity: 2, section: 'main' as const }],
    }
    const withdrawn = applyGameCommand(rawDatabase, {
      command: 'guild_bank_withdraw',
      args: { itemId: 'ITEM-0015', quantity: 1 },
      save,
      nowMs: START_MS,
      random: () => 0,
      hall,
      guildBank: bank,
      userId: 'u1',
      guildRole: 'member',
      totalLevel: 200,
    })
    expect(withdrawn).toEqual({ ok: false, reason: 'You cannot withdraw from the guild bank.' })

    const veteran = applyGameCommand(rawDatabase, {
      command: 'guild_bank_withdraw',
      args: { itemId: 'ITEM-0015', quantity: 1 },
      save,
      nowMs: START_MS,
      random: () => 0,
      hall,
      guildBank: bank,
      userId: 'u1',
      guildRole: 'veteran',
      totalLevel: 200,
    })
    expect(veteran).toEqual({ ok: false, reason: 'You cannot withdraw from the guild bank.' })

    const moved = applyGameCommand(rawDatabase, {
      command: 'guild_bank_move_up_for_grabs',
      args: { itemId: 'ITEM-0015', quantity: 2 },
      save,
      nowMs: START_MS,
      random: () => 0,
      hall,
      guildBank: bank,
      userId: 'u1',
      guildRole: 'member',
      nextId: () => 'gb-2',
    })
    expect(moved).toEqual({ ok: false, reason: 'You cannot move items to Up for grabs.' })
  })

  it('reads the Tradeable column, with missing meaning true', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(isItemTradeable(launch, 'ITEM-0406')).toBe(false)
    expect(isItemTradeable(launch, 'ITEM-0313')).toBe(false)
    expect(isItemTradeable(launch, 'ITEM-0026')).toBe(true)
    expect(isItemTradeable(launch, 'ITEM-9999')).toBe(true)
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

  it('does not treat catch-up ore, food, arrows, or gold as a hall donation', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let hosted = {
      ...createNewSave(launch, START_MS),
      currentLocationId: 'LOC-0001',
      gold: 100,
      inventory: [
        { itemId: 'ITEM-0003', quantity: 10 },
        { itemId: 'ITEM-0058', quantity: 5 },
        { itemId: 'ITEM-ARROWS', quantity: 8 },
        { itemId: 'ITEM-0015', quantity: 3 },
      ],
    }
    hosted = beginActivitySave(hosted, 'ACT-0021', new Date(START_MS).toISOString())
    const generated = generateNextAction(launch, hosted, 'ACT-0021', () => 0.1, START_MS)
    hosted = {
      ...generated!.save,
      unattendedProgressAt: new Date(START_MS).toISOString(),
      gold: 100,
      inventory: [
        { itemId: 'ITEM-0003', quantity: 10 },
        { itemId: 'ITEM-0058', quantity: 5 },
        { itemId: 'ITEM-ARROWS', quantity: 8 },
        { itemId: 'ITEM-0015', quantity: 3 },
      ],
    }

    const later = START_MS + 30_000
    const caughtUp = applyGameCommand(rawDatabase, {
      command: 'set_meta',
      args: {},
      save: hosted,
      nowMs: later,
      random: () => 0.1,
    })
    expect(caughtUp.ok).toBe(true)
    if (!caughtUp.ok) return
    expect(caughtUp.saveBeforeCommand).toBeDefined()

    const cedarIndex = caughtUp.save.inventory.findIndex((stack) => stack.itemId === 'ITEM-0015')
    expect(cedarIndex).toBeGreaterThanOrEqual(0)
    const donated = applyGameCommand(rawDatabase, {
      command: 'guild_donate_hall_item',
      args: { inventoryIndex: cedarIndex, itemId: 'ITEM-0015', quantity: 1 },
      save: hosted,
      nowMs: later,
      random: () => 0.1,
      hall: emptyGuildHallState(),
      userId: 'u1',
      guildRole: 'member',
    })
    expect(donated.ok).toBe(true)
    if (!donated.ok) return
    expect(donated.saveBeforeCommand?.gold).toBe(caughtUp.save.gold)
    expect(donated.saveBeforeCommand?.inventory).toEqual(caughtUp.save.inventory)
    expect(donated.hall?.storehouse).toEqual([{ itemId: 'ITEM-0015', quantity: 1 }])

    const fromCaughtUp = commitGuildHallFromPlayerSaves({
      previousGold: donated.saveBeforeCommand!.gold,
      nextGold: donated.save.gold,
      previousInventory: donated.saveBeforeCommand!.inventory,
      nextInventory: donated.save.inventory,
      hall: emptyGuildHallState(),
      userId: 'u1',
    })
    expect(fromCaughtUp.ok).toBe(true)
    if (!fromCaughtUp.ok) return
    expect(fromCaughtUp.goldTaken).toBe(0)
    expect(fromCaughtUp.hall.storehouse).toEqual([{ itemId: 'ITEM-0015', quantity: 1 }])

    const chipped = applyGameCommand(rawDatabase, {
      command: 'guild_chip_in_hall_gold',
      args: { amount: 10 },
      save: hosted,
      nowMs: later,
      random: () => 0.1,
      hall: emptyGuildHallState(),
      userId: 'u1',
      guildRole: 'member',
    })
    expect(chipped.ok).toBe(true)
    if (!chipped.ok) return
    expect(chipped.goldChipped).toBe(10)
    expect(chipped.save.gold).toBe(chipped.saveBeforeCommand!.gold - 10)

    const rightGold = commitGuildHallFromPlayerSaves({
      previousGold: chipped.saveBeforeCommand!.gold,
      nextGold: chipped.save.gold,
      previousInventory: chipped.saveBeforeCommand!.inventory,
      nextInventory: chipped.save.inventory,
      hall: emptyGuildHallState(),
      userId: 'u1',
    })
    expect(rightGold.ok).toBe(true)
    if (!rightGold.ok) return
    expect(rightGold.goldTaken).toBe(10)

    const naive = commitGuildHallFromPlayerSaves({
      previousGold: hosted.gold,
      nextGold: chipped.save.gold,
      previousInventory: hosted.inventory,
      nextInventory: chipped.save.inventory,
      hall: emptyGuildHallState(),
      userId: 'u1',
    })
    expect(naive.ok).toBe(true)
    if (!naive.ok) return
    const naiveIds = new Set(naive.hall.storehouse.map((stack) => stack.itemId))
    if (hosted.gold !== chipped.saveBeforeCommand!.gold) {
      expect(naive.goldTaken).not.toBe(10)
    }
    const catchUpConsumedOre =
      (hosted.inventory.find((stack) => stack.itemId === 'ITEM-0003')?.quantity ?? 0) >
      (chipped.saveBeforeCommand!.inventory.find((stack) => stack.itemId === 'ITEM-0003')?.quantity ?? 0)
    if (catchUpConsumedOre) expect(naiveIds.has('ITEM-0003')).toBe(true)
  })
})
