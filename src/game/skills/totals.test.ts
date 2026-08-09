import { describe, expect, it } from 'vitest'
import type { PlayerSave } from '../save/types'
import { totalLevel, totalSkillXp } from './totals'

function sampleSave(skills: Array<{ skillId: string; level: number; xp: number }>): PlayerSave {
  return {
    saveVersion: 2,
    createdAt: '',
    updatedAt: '',
    skills,
    inventory: [],
    equipment: { slots: {} },
    gold: 0,
    quests: [],
    achievements: [],
    statistics: { values: {} },
    unlockedNpcIds: [],
    settings: { soundEnabled: true },
    characterName: 'Tester',
    currentLocationId: 'LOC-0002',
    currentActivityId: null,
    activityStartedAt: null,
    currentActionId: null,
    actionStartedAt: null,
    actionDurationMs: null,
    combatEnemyId: null,
    combatEnemyHp: null,
    combatRoundStartedAt: null,
    deathPauseUntil: null,
    productionRecipeId: null,
    productionQuantityTotal: null,
    productionQuantityRemaining: null,
    unattendedProgressAt: null,
    currentHp: 1000,
    maxHp: 1000,
  }
}

describe('skill totals', () => {
  it('sums levels and xp', () => {
    const save = sampleSave([
      { skillId: 'SKL-0001', level: 1, xp: 0 },
      { skillId: 'SKL-0004', level: 3, xp: 2500 },
      { skillId: 'SKL-0002', level: 2, xp: 800 },
    ])
    expect(totalLevel(save)).toBe(6)
    expect(totalSkillXp(save)).toBe(3300)
  })
})
