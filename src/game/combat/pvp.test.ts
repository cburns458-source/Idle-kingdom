import { describe, expect, it } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { prepareDatabase } from '../data/loadDatabase'
import { mulberry32 } from '../rng/mulberry32'
import { createNewSave } from '../save/saveStore'
import { simulatePvpFight } from './pvp'
import { playerMaxHp } from './stats'

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
})
