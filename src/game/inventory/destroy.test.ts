import { describe, expect, it } from 'vitest'
import { destroyInventoryIndexes } from './destroy'
import type { PlayerSave } from '../save/types'

function saveWithInventory(itemIds: string[]): PlayerSave {
  return {
    saveVersion: 10,
    createdAt: 't',
    updatedAt: 't',
    characterName: 'Test',
    raceId: null,
    skills: [],
    inventory: itemIds.map((itemId) => ({ itemId, quantity: 1 })),
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
    claimedKingswoodsSling: false,
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
    maxHp: 100,
    currentHp: 100,
    unattendedProgressAt: null,
    playTimeMs: 0,
  }
}

describe('destroyInventoryIndexes', () => {
  it('removes selected bag stacks and leaves others', () => {
    const save = saveWithInventory(['ITEM-A', 'ITEM-B', 'ITEM-C'])
    const next = destroyInventoryIndexes(save, [0, 2])
    expect(next.inventory.map((stack) => stack.itemId)).toEqual(['ITEM-B'])
  })

  it('ignores invalid indexes and no-ops on empty selection', () => {
    const save = saveWithInventory(['ITEM-A'])
    expect(destroyInventoryIndexes(save, [])).toBe(save)
    expect(destroyInventoryIndexes(save, [-1, 3]).inventory).toHaveLength(1)
  })
})
