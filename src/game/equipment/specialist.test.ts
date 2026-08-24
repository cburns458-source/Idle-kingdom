import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { addItemToInventory } from '../activity/rewards'
import { gatheringXpReward } from '../activity/gathering'
import { prepareDatabase } from '../data/loadDatabase'
import { completeProductionCraft, beginProductionQueue } from '../production/engine'
import { completeSpecialProject } from '../projects/engine'
import { encodeEnchantTarget } from '../projects/enchantments'
import { createNewSave } from '../save/saveStore'
import {
  CHEF_HAT_ITEM_ID,
  QUIVER_ITEM_ID,
  WIZARD_HAT_ITEM_ID,
  wizardEssenceCost,
} from './specialist'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

function withHelmet(save: ReturnType<typeof createNewSave>, itemId: string) {
  return {
    ...save,
    equipment: {
      slots: { ...save.equipment.slots, 'SLOT-0003': { itemId, quantity: 1 } },
    },
  }
}

function withBack(save: ReturnType<typeof createNewSave>, itemId: string) {
  return {
    ...save,
    equipment: {
      slots: { ...save.equipment.slots, 'SLOT-0010': { itemId, quantity: 1 } },
    },
  }
}

describe('specialist hats and quiver', () => {
  it('doubles cooking output on a 1/100 chef-hat proc without extra XP', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = addItemToInventory(save, 'ITEM-0025', 2)
    save = withHelmet(save, CHEF_HAT_ITEM_ID)
    const queued = beginProductionQueue(launch, save, 'ACT-0017', 'RCP-0001', 1)
    expect(queued.ok).toBe(true)
    if (!queued.ok) return
    const missed = completeProductionCraft(launch, queued.save, Date.now(), () => 0.5)
    const hit = completeProductionCraft(launch, queued.save, Date.now(), () => 0)
    expect(missed?.outputQty).toBe(1)
    expect(hit?.outputQty).toBe(2)
    expect(missed?.xpGained).toBe(hit?.xpGained)
  })

  it('rounds wizard-hat essence cost up after a 1% discount', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = withHelmet(save, WIZARD_HAT_ITEM_ID)
    expect(wizardEssenceCost(100, save)).toBe(99)
    expect(wizardEssenceCost(200, save)).toBe(198)
    expect(wizardEssenceCost(3, createNewSave(launch))).toBe(3)

    save = {
      ...save,
      unlockedNpcIds: ['NPC-0004'],
      currentLocationId: 'LOC-0007',
      skills: save.skills.map((skill) =>
        skill.skillId === 'SKL-0013' ? { ...skill, level: 20, xp: 50_000 } : skill,
      ),
    }
    save = addItemToInventory(save, 'ITEM-0098', 1)
    save = addItemToInventory(save, 'ITEM-0011', 198)
    save = addItemToInventory(save, 'ITEM-0031', 10)
    save = addItemToInventory(save, 'ITEM-0119', 1)
    const invIndex = save.inventory.findIndex((stack) => stack.itemId === 'ITEM-0119')
    const result = completeSpecialProject(
      launch,
      save,
      'PRJ-0134',
      1,
      encodeEnchantTarget({ kind: 'inventory', index: invIndex }),
    )
    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(result.save.inventory.find((stack) => stack.itemId === 'ITEM-0011')).toBeUndefined()
  })

  it('adds 5% hunting XP while a quiver is equipped', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const action = launch.Actions.find((row) => row['Internal Key'] === 'hunt_elk')!
    const save = withBack(createNewSave(launch), QUIVER_ITEM_ID)
    const bare = gatheringXpReward(launch, createNewSave(launch), action)
    const worn = gatheringXpReward(launch, save, action)
    expect(worn).toBe(Math.floor(bare * 1.05))
  })
})
