import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { addItemToInventory } from '../activity/rewards'
import { prepareDatabase } from '../data/loadDatabase'
import { npcsAtLocationForSave } from '../npcs/knowledge'
import { miniQuestLog } from '../quests/miniquests'
import { questLog } from '../log/log'
import { createNewSave } from '../save/saveStore'
import { totalLevel } from '../skills/totals'
import type { PlayerSave } from '../save/types'
import { assignRace } from './assignRace'
import {
  RACE_CHANGE_COSTS,
  RACE_CHANGE_MINIQUEST_ID,
  RACE_CHANGE_TOTAL_LEVEL,
  VESPER_ID,
  changeRaceAtNpc,
  raceChangeOffer,
} from './changeRace'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)
const { launch } = prepareDatabase(rawDatabase)
const WEEK_MS = 7 * 24 * 60 * 60 * 1000
const NOW = Date.parse('2026-08-31T00:00:00.000Z')

function withTotalLevel(save: PlayerSave, target: number): PlayerSave {
  const current = totalLevel(save)
  const bump = target - current
  if (bump <= 0) return save
  const [first, ...rest] = save.skills
  if (!first) return save
  return { ...save, skills: [{ ...first, level: first.level + bump }, ...rest] }
}

function seasoned(save: PlayerSave): PlayerSave {
  return withTotalLevel(
    { ...save, currentLocationId: 'LOC-0015' },
    RACE_CHANGE_TOTAL_LEVEL,
  )
}

function payFor(save: PlayerSave, raceId: string): PlayerSave {
  const cost = RACE_CHANGE_COSTS[raceId]!
  let next = { ...save, gold: save.gold + cost.gold }
  for (const item of cost.items) {
    next = addItemToInventory(next, item.itemId, item.quantity)
  }
  return next
}

describe('Vesper race change', () => {
  it('hides Vesper until total level 500', () => {
    const base = assignRace(launch, createNewSave(launch), 'RACE-0001')
    expect(base.ok).toBe(true)
    if (!base.ok) return
    const atHall = { ...base.save, currentLocationId: 'LOC-0015' }
    expect(npcsAtLocationForSave(launch, atHall, 'LOC-0015').map((npc) => npc['NPC ID'])).not.toContain(
      VESPER_ID,
    )
    expect(miniQuestLog(launch, atHall, NOW)).toEqual([])

    const ready = seasoned(atHall)
    expect(totalLevel(ready)).toBeGreaterThanOrEqual(RACE_CHANGE_TOTAL_LEVEL)
    expect(npcsAtLocationForSave(launch, ready, 'LOC-0015').map((npc) => npc['NPC ID'])).toContain(
      VESPER_ID,
    )
    expect(miniQuestLog(launch, ready, NOW).map((row) => row.questId)).toEqual([
      RACE_CHANGE_MINIQUEST_ID,
    ])
  })

  it('keeps the miniquest out of the quest journal', () => {
    expect(questLog(launch, createNewSave(launch)).some((row) => row.questId === RACE_CHANGE_MINIQUEST_ID)).toBe(
      false,
    )
  })

  it('uses mid-level costs without gems, grapes, or moonblossom', () => {
    expect(RACE_CHANGE_COSTS['RACE-0001']).toEqual({
      gold: 0,
      items: [
        { itemId: 'ITEM-0050', quantity: 40 },
        { itemId: 'ITEM-0018', quantity: 40 },
      ],
    })
    expect(RACE_CHANGE_COSTS['RACE-0006']?.items).toEqual(
      expect.arrayContaining([{ itemId: 'ITEM-0006', quantity: 20 }]),
    )
    const listed = Object.values(RACE_CHANGE_COSTS).flatMap((cost) => cost.items.map((item) => item.itemId))
    expect(listed).not.toContain('ITEM-0014')
    expect(listed).not.toContain('ITEM-0012')
    expect(listed).not.toContain('ITEM-0029')
    expect(listed).not.toContain('ITEM-0207')
    expect(listed).not.toContain('ITEM-0088')
    expect(listed).not.toContain('ITEM-0089')
    expect(listed).not.toContain('ITEM-0090')
  })

  it('changes race, spends the items, and starts a weekly cooldown', () => {
    const assigned = assignRace(launch, createNewSave(launch), 'RACE-0001')
    expect(assigned.ok).toBe(true)
    if (!assigned.ok) return
    const ready = payFor(seasoned(assigned.save), 'RACE-0006')
    const offer = raceChangeOffer(launch, ready, NOW)
    expect(offer.ready).toBe(true)
    expect(offer.warning.toLowerCase()).not.toMatch(/starter|kit|tool/)
    expect(offer.prompt.toLowerCase()).not.toMatch(/starter|kit|tool/)

    const changed = changeRaceAtNpc(launch, ready, 'RACE-0006', NOW)
    expect(changed.ok).toBe(true)
    if (!changed.ok) return
    expect(changed.save.raceId).toBe('RACE-0006')
    expect(changed.save.inventory.find((stack) => stack.itemId === 'ITEM-0006')?.quantity ?? 0).toBe(0)
    expect(changed.save.miniquestCompletedAt[RACE_CHANGE_MINIQUEST_ID]).toBe(new Date(NOW).toISOString())
    expect(changed.message.toLowerCase()).not.toMatch(/starter|kit|tool/)

    const again = changeRaceAtNpc(launch, payFor(changed.save, 'RACE-0002'), 'RACE-0002', NOW + 1000)
    expect(again.ok).toBe(false)
    if (again.ok) return
    expect(again.reason).toMatch(/Come back in 6 days/)

    const rows = miniQuestLog(launch, changed.save, NOW + 1000)
    expect(rows[0]?.repeatLabel).toMatch(/Repeat in/)
    expect(rows[0]?.repeatEveryLabel).toBe('Every 7 days')

    const later = changeRaceAtNpc(
      launch,
      payFor(changed.save, 'RACE-0002'),
      'RACE-0002',
      NOW + WEEK_MS,
    )
    expect(later.ok).toBe(true)
    if (!later.ok) return
    expect(later.save.raceId).toBe('RACE-0002')
  })

  it('does not re-grant a starter kit on a later change', () => {
    const first = assignRace(launch, createNewSave(launch), 'RACE-0001')
    expect(first.ok).toBe(true)
    if (!first.ok) return
    const ready = payFor(seasoned(first.save), 'RACE-0007')
    const beforeGold = ready.gold
    const changed = changeRaceAtNpc(launch, ready, 'RACE-0007', NOW)
    expect(changed.ok).toBe(true)
    if (!changed.ok) return
    expect(changed.save.gold).toBe(beforeGold)
    expect(changed.save.inventory.some((stack) => stack.itemId === 'ITEM-0100')).toBe(
      first.save.inventory.some((stack) => stack.itemId === 'ITEM-0100'),
    )
  })
})
