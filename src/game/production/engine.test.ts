import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { addItemToInventory } from '../activity/rewards'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import {
  beginProductionQueue,
  cancelProductionActivity,
  completeProductionCraft,
  resolveProductionProgress,
} from './engine'
import { canKnowRecipe, getRecipe, isCompleteRecipe, recipesForActivity } from './recipes'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('standard production', () => {
  it('skips Needs Data recipes such as Cloth Wrap', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const cloth = getRecipe(launch, 'RCP-0058')
    expect(cloth).toBeDefined()
    expect(isCompleteRecipe(cloth!)).toBe(false)
  })

  it('lists level-1 kitchen recipes and consumes materials for a queue', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0025', 5)

    const recipes = recipesForActivity(launch, save, 'ACT-0017')
    expect(recipes.some((recipe) => recipe['Recipe ID'] === 'RCP-0001')).toBe(true)

    const queued = beginProductionQueue(launch, save, 'ACT-0017', 'RCP-0001', 3)
    expect(queued.ok).toBe(true)
    if (!queued.ok) return

    expect(queued.save.productionRecipeId).toBe('RCP-0001')
    expect(queued.save.productionQuantityTotal).toBe(3)
    expect(queued.save.productionQuantityRemaining).toBe(3)
    expect(queued.save.inventory.find((stack) => stack.itemId === 'ITEM-0025')?.quantity).toBe(2)
  })

  it('shares Town kitchen recipes with the Castle kitchen activity', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, currentLocationId: 'LOC-0015' }
    save = addItemToInventory(save, 'ITEM-0025', 2)

    const recipes = recipesForActivity(launch, save, 'ACT-0023')
    expect(recipes.some((recipe) => recipe['Recipe ID'] === 'RCP-0001')).toBe(true)

    const queued = beginProductionQueue(launch, save, 'ACT-0023', 'RCP-0001', 1)
    expect(queued.ok).toBe(true)
    if (!queued.ok) return
    expect(queued.save.productionRecipeId).toBe('RCP-0001')
  })

  it('rejects queues larger than materials or the 24h cap', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0025', 2)

    const missing = beginProductionQueue(launch, save, 'ACT-0017', 'RCP-0001', 5)
    expect(missing.ok).toBe(false)

    save = addItemToInventory(save, 'ITEM-0025', 10_000)
    const overCap = beginProductionQueue(launch, save, 'ACT-0017', 'RCP-0001', 10_000)
    expect(overCap.ok).toBe(false)
  })

  it('builds a gathering-style reward summary for each completed craft', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0025', 1)
    const queued = beginProductionQueue(
      launch,
      save,
      'ACT-0017',
      'RCP-0001',
      1,
      Date.parse('2026-01-01T00:00:00.000Z'),
    )
    expect(queued.ok).toBe(true)
    if (!queued.ok) return

    const finished = completeProductionCraft(
      launch,
      queued.save,
      Date.parse('2026-01-01T00:00:20.000Z'),
    )
    expect(finished).not.toBeNull()
    if (!finished) return
    expect(finished.reward.loot).toEqual([
      { itemId: 'ITEM-0058', quantity: 1, displayName: expect.any(String) },
    ])
    expect(finished.reward.xpRewards).toHaveLength(1)
    expect(finished.reward.xpRewards[0]?.skillId).toBe('SKL-0007')
    expect(finished.reward.xpRewards[0]?.xp).toBe(500)
    expect(finished.reward.goldGained).toBe(0)
  })

  it('completes crafts offline and grants output + XP', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, inventory: [] }
    save = addItemToInventory(save, 'ITEM-0025', 2)
    const queued = beginProductionQueue(
      launch,
      save,
      'ACT-0017',
      'RCP-0001',
      2,
      Date.parse('2026-01-01T00:00:00.000Z'),
    )
    expect(queued.ok).toBe(true)
    if (!queued.ok) return

    const resolved = resolveProductionProgress(
      launch,
      queued.save,
      Date.parse('2026-01-01T00:00:45.000Z'),
    )
    expect(resolved.craftsCompleted).toBe(2)
    expect(resolved.save.productionRecipeId).toBeNull()
    expect(resolved.save.inventory.find((stack) => stack.itemId === 'ITEM-0058')?.quantity).toBe(2)
    const cooking = resolved.save.skills.find((skill) => skill.skillId === 'SKL-0007')
    expect(cooking?.xp).toBe(1_000)
    expect(resolved.messages).toEqual([
      expect.stringMatching(/^Crafted 2 Baked Potato \(\+\d+ XP\)$/),
    ])
  })

  it('refunds remaining materials when cancelled', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0003', 6)
    const queued = beginProductionQueue(launch, save, 'ACT-0018', 'RCP-0014', 3)
    expect(queued.ok).toBe(true)
    if (!queued.ok) return

    const cancelled = cancelProductionActivity(launch, queued.save)
    expect(cancelled.productionRecipeId).toBeNull()
    expect(cancelled.inventory.find((stack) => stack.itemId === 'ITEM-0003')?.quantity).toBe(6)
  })

  it('hard-gates alchemy until proficiency level', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = createNewSave(launch)
    const luck = getRecipe(launch, 'RCP-0053')!
    expect(canKnowRecipe(save, launch, luck)).toBe(false)
    expect(recipesForActivity(launch, save, 'ACT-0020')).toHaveLength(0)
  })
})
