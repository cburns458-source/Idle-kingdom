import { describe, expect, it } from 'vitest'
import { destroyInventoryIndexes } from './destroy'
import type { PlayerSave } from '../save/types'

function saveWithInventory(itemIds: string[]): PlayerSave {
  return {
    saveVersion: 9,
    createdAt: 't',
    updatedAt: 't',
    characterName: 'Test',
    skills: [],
    inventory: itemIds.map((itemId) => ({ itemId, quantity: 1 })),
    equipment: { slots: {} },
    gold: 0,
    quests: [],
    achievements: [],
    statistics: { values: {} },
    unlockedNpcIds: [],
    settings: { soundEnabled: true },
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
    maxHp: 100,
    currentHp: 100,
    unattendedProgressAt: null,
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
