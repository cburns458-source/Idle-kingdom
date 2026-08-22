import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { prepareDatabase } from '../data/loadDatabase'
import { mulberry32 } from '../rng/mulberry32'
import { createNewSave } from '../save/saveStore'
import { composePvpFighter, overlayPvpLiveStats, simulatePvpFight } from './pvp'
import { COMBAT_SKILL_ID, playerDamageRange, playerMaxHp } from './stats'
import { equipStackToSlot, WEAPON_TOOL_SLOT_ID } from '../equipment/loadout'
import type { PlayerSave } from '../save/types'

function withCombat(save: PlayerSave, level: number): PlayerSave {
  return {
    ...save,
    skills: save.skills.map((skill) =>
      skill.skillId === COMBAT_SKILL_ID ? { ...skill, level } : skill,
    ),
  }
}

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('pvp snapshot combat', () => {
  it('resolves a snapshot fight without changing the source saves', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const you = createNewSave(launch)
    const them = {
      ...createNewSave(launch),
      skills: createNewSave(launch).skills.map((skill) =>
        skill.skillId === 'SKL-0001' ? { ...skill, level: 18 } : skill,
      ),
    }
    const youHp = you.currentHp
    const themHp = them.currentHp
    const fight = simulatePvpFight(launch, you, them, mulberry32(20260813))
    expect(fight.rounds.length).toBeGreaterThan(0)
    expect(['win', 'loss']).toContain(fight.outcome)
    expect(fight.youMaxHp).toBe(playerMaxHp(launch, you))
    expect(you.currentHp).toBe(youHp)
    expect(them.currentHp).toBe(themHp)
    expect(fight.rounds.at(-1)?.outcome).toBe(fight.outcome)
  })

  it('composes snapshot gear with live combat and race', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const sword = { ...equipStackToSlot(base, WEAPON_TOOL_SLOT_ID, 'ITEM-0128', 1), raceId: 'RACE-0001' }
    const gathering = equipStackToSlot(
      { ...withCombat(base, 20), raceId: 'RACE-0003' },
      WEAPON_TOOL_SLOT_ID,
      'ITEM-0102',
      1,
    )
    const fighter = composePvpFighter(launch, gathering, sword)
    expect(fighter.equipment.slots[WEAPON_TOOL_SLOT_ID]?.itemId).toBe('ITEM-0128')
    expect(fighter.skills.find((skill) => skill.skillId === COMBAT_SKILL_ID)?.level).toBe(20)
    expect(fighter.raceId).toBe('RACE-0003')
    const stale = composePvpFighter(launch, sword, sword)
    expect(playerMaxHp(launch, fighter)).toBeGreaterThan(playerMaxHp(launch, stale))
    expect(playerDamageRange(launch, fighter).min).toBeGreaterThan(playerDamageRange(launch, gathering).min)
  })

  it('overlays live combat onto snapshot gear', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const base = createNewSave(launch)
    const snapshot = equipStackToSlot(base, WEAPON_TOOL_SLOT_ID, 'ITEM-0128', 1)
    const live = equipStackToSlot(
      { ...withCombat(base, 20), raceId: 'RACE-0004' },
      WEAPON_TOOL_SLOT_ID,
      'ITEM-0102',
      1,
    )
    const merged = overlayPvpLiveStats(snapshot, live)
    expect(merged.equipment.slots[WEAPON_TOOL_SLOT_ID]?.itemId).toBe('ITEM-0128')
    expect(merged.skills.find((skill) => skill.skillId === COMBAT_SKILL_ID)?.level).toBe(20)
    expect(merged.raceId).toBe('RACE-0004')
  })
})
