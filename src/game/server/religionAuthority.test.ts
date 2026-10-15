import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { TITLE_COSMETIC_SLOT_ID, type PlayerSave } from '../save/types'
import { totalLevel } from '../skills/totals'
import { applyGameCommand } from './authority'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

const NOW_MS = Date.parse('2026-10-15T00:00:00.000Z')
const WEEK_MS = 7 * 24 * 60 * 60 * 1000
const TEMPLE = 'LOC-0036'
const REL_A = 'REL-0001'
const REL_B = 'REL-0002'
const TITLE_A = 'COS-0013'

function withTotalLevel(save: PlayerSave, target: number): PlayerSave {
  const bump = target - totalLevel(save)
  if (bump <= 0) return save
  const [first, ...rest] = save.skills
  return { ...save, skills: [{ ...first, level: first.level + bump }, ...rest] }
}

function templeSave(level: number, extra: Partial<PlayerSave> = {}): PlayerSave {
  const { launch } = prepareDatabase(rawDatabase)
  return {
    ...withTotalLevel(createNewSave(launch, NOW_MS), level),
    currentLocationId: TEMPLE,
    gold: 50_000,
    ...extra,
  }
}

describe('choose_religion authority', () => {
  it('refuses total level 99 on the server', () => {
    const result = applyGameCommand(rawDatabase, {
      command: 'choose_religion',
      args: { religionId: REL_A },
      save: templeSave(99),
      nowMs: NOW_MS,
      random: () => 0,
    })
    expect(result.ok).toBe(false)
    if (result.ok) return
    expect(result.reason).toMatch(/100/)
  })

  it('first pick is free and a same-faith retry never double-charges', () => {
    const first = applyGameCommand(rawDatabase, {
      command: 'choose_religion',
      args: { religionId: REL_A },
      save: templeSave(100),
      nowMs: NOW_MS,
      random: () => 0,
    })
    expect(first.ok).toBe(true)
    if (!first.ok) return
    expect(first.save.religionId).toBe(REL_A)
    expect(first.save.gold).toBe(50_000)
    expect(first.goldCost ?? 0).toBe(0)

    const retry = applyGameCommand(rawDatabase, {
      command: 'choose_religion',
      args: { religionId: REL_A },
      save: first.save,
      nowMs: NOW_MS + 5_000,
      random: () => 0,
    })
    expect(retry.ok).toBe(true)
    if (!retry.ok) return
    expect(retry.save.gold).toBe(first.save.gold)
    expect(retry.save.religionChangedAt).toBe(first.save.religionChangedAt)
    expect(retry.goldCost ?? 0).toBe(0)
  })

  it('enforces the 7-day server cooldown, then charges gold once', () => {
    const first = applyGameCommand(rawDatabase, {
      command: 'choose_religion',
      args: { religionId: REL_A },
      save: templeSave(100),
      nowMs: NOW_MS,
      random: () => 0,
    })
    expect(first.ok).toBe(true)
    if (!first.ok) return

    const blocked = applyGameCommand(rawDatabase, {
      command: 'choose_religion',
      args: { religionId: REL_B },
      save: first.save,
      nowMs: NOW_MS + WEEK_MS - 1,
      random: () => 0,
    })
    expect(blocked.ok).toBe(false)

    const changed = applyGameCommand(rawDatabase, {
      command: 'choose_religion',
      args: { religionId: REL_B },
      save: first.save,
      nowMs: NOW_MS + WEEK_MS,
      random: () => 0,
    })
    expect(changed.ok).toBe(true)
    if (!changed.ok) return
    expect(changed.save.religionId).toBe(REL_B)
    expect(changed.goldCost).toBe(1000)
    expect(changed.save.gold).toBe(first.save.gold - 1000)

    const retryChange = applyGameCommand(rawDatabase, {
      command: 'choose_religion',
      args: { religionId: REL_B },
      save: changed.save,
      nowMs: NOW_MS + WEEK_MS + 1,
      random: () => 0,
    })
    expect(retryChange.ok).toBe(true)
    if (!retryChange.ok) return
    expect(retryChange.save.gold).toBe(changed.save.gold)
  })

  it('charges later changes from the player total level on the server', () => {
    const first = applyGameCommand(rawDatabase, {
      command: 'choose_religion',
      args: { religionId: REL_A },
      save: templeSave(105),
      nowMs: NOW_MS,
      random: () => 0,
    })
    expect(first.ok).toBe(true)
    if (!first.ok) return
    expect(first.save.gold).toBe(50_000)

    const changed = applyGameCommand(rawDatabase, {
      command: 'choose_religion',
      args: { religionId: REL_B },
      save: first.save,
      nowMs: NOW_MS + WEEK_MS,
      random: () => 0,
    })
    expect(changed.ok).toBe(true)
    if (!changed.ok) return
    expect(changed.goldCost).toBe(1000)
    expect(changed.save.gold).toBe(first.save.gold - 1000)
  })

  it('refuses equipping a locked faith title via set_meta', () => {
    const first = applyGameCommand(rawDatabase, {
      command: 'choose_religion',
      args: { religionId: REL_A },
      save: templeSave(100),
      nowMs: NOW_MS,
      random: () => 0,
    })
    expect(first.ok).toBe(true)
    if (!first.ok) return

    const equipped = applyGameCommand(rawDatabase, {
      command: 'set_meta',
      args: {
        equippedCosmetics: {
          ...first.save.cosmetics.equipped,
          [TITLE_COSMETIC_SLOT_ID]: TITLE_A,
        },
      },
      save: first.save,
      nowMs: NOW_MS,
      random: () => 0,
    })
    expect(equipped.ok).toBe(true)

    const switched = applyGameCommand(rawDatabase, {
      command: 'choose_religion',
      args: { religionId: REL_B },
      save: first.save,
      nowMs: NOW_MS + WEEK_MS,
      random: () => 0,
    })
    expect(switched.ok).toBe(true)
    if (!switched.ok) return

    const locked = applyGameCommand(rawDatabase, {
      command: 'set_meta',
      args: {
        equippedCosmetics: {
          ...switched.save.cosmetics.equipped,
          [TITLE_COSMETIC_SLOT_ID]: TITLE_A,
        },
      },
      save: switched.save,
      nowMs: NOW_MS + WEEK_MS,
      random: () => 0,
    })
    expect(locked.ok).toBe(false)
    if (locked.ok) return
    expect(locked.reason).toMatch(/faith/i)
  })
})
