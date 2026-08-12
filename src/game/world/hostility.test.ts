import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import {
  applyHostileTravelArrival,
  forcedHostileActivity,
  hostileForceMessage,
} from './hostility'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('hostile travel forcing', () => {
  it('forces Fight the Goblins when Combat Level is below 10', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    expect(forcedHostileActivity(launch, save, 'LOC-0003')?.['Activity ID']).toBe('ACT-0002')

    const arrived = applyHostileTravelArrival(launch, save, 'LOC-0003')
    expect(arrived.save.currentLocationId).toBe('LOC-0003')
    expect(arrived.forcedActivityId).toBe('ACT-0002')
    expect(arrived.save.currentActivityId).toBe('ACT-0002')
    expect(arrived.save.currentActionId).toBeTruthy()
    expect(hostileForceMessage(launch, arrived)).toMatch(/forced into Fight the Goblins/i)
  })

  it('does not force Goblin Camp combat at Combat Level 10+', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = {
      ...save,
      skills: save.skills.map((skill) =>
        skill.skillId === 'SKL-0001' ? { ...skill, level: 10, xp: 50_000 } : skill,
      ),
    }
    expect(forcedHostileActivity(launch, save, 'LOC-0003')).toBeNull()
    const arrived = applyHostileTravelArrival(launch, save, 'LOC-0003')
    expect(arrived.forcedActivityId).toBeNull()
    expect(arrived.save.currentActivityId).toBeNull()
  })

  it('does not force combat when traveling to a safe location', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const arrived = applyHostileTravelArrival(launch, save, 'LOC-0002')
    expect(arrived.forcedActivityId).toBeNull()
    expect(arrived.save.currentLocationId).toBe('LOC-0002')
  })

  it('stops a running activity immediately when arriving at a safe location', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const now = Date.parse('2026-01-01T00:00:00.000Z')
    const save = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0009',
      currentActivityId: 'ACT-0012',
      activityStartedAt: new Date(now).toISOString(),
    }
    const arrived = applyHostileTravelArrival(launch, save, 'LOC-0002', now)
    expect(arrived.forcedActivityId).toBeNull()
    expect(arrived.save.currentLocationId).toBe('LOC-0002')
    expect(arrived.save.currentActivityId).toBeNull()
    expect(arrived.save.activityTransition).toBeNull()
  })
})
