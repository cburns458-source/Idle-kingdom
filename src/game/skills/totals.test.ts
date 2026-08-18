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
    bank: [],
    equipment: { slots: {} },
    gold: 0,
    quests: [],
    achievements: [],
    statistics: { values: {} },
    unlockedNpcIds: [],
    unlockedRecipeIds: [],
    unlockedLocationIds: [],
    bountyHourKey: null,
    bountyProgress: {},
    bountyClaimedIds: [],
    rankedPvpDayKey: null,
    rankedPvpFightsToday: 0,
    rankedPvpWins: 0,
    rankedPvpLosses: 0,
    hasEverDied: false,
    favoriteActivityByLocationId: {},
    heldActionByActivityId: {},
    claimedMerchantTipIds: [],
    critterCollections: [],
    activeCritterSpawns: [],
    critterProgressMs: {},
    locationSearchClaims: {},
    cosmetics: { unlocked: [], equipped: {} },
    appearance: {
      skinTone: 'APR-0001',
      hairstyle: 'APR-0004',
      hairColor: 'APR-0007',
      expression: 'APR-0011',
      beard: 'APR-0014',
      genderPresentation: 'APR-0017',
    },
    hasSeenWardrobeIntro: false,
    settings: { soundEnabled: true, showActivityRewards: true, hudShowTotalXp: false },
    characterName: 'Tester',
    raceId: null,
    currentLocationId: 'LOC-0002',
    currentActivityId: null,
    activityStartedAt: null,
    currentActionId: null,
    actionStartedAt: null,
    actionDurationMs: null,
    combatEnemyId: null,
    combatEnemyHp: null,
    combatRoundStartedAt: null,
    activePotionEffect: null,
    deathPauseUntil: null,
    productionRecipeId: null,
    productionQuantityTotal: null,
    productionQuantityRemaining: null,
    activityTransition: null,
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
