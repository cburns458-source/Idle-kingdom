import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { addItemToInventory } from '../activity/rewards'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { acceptQuest, completeQuest, getQuest } from './quests'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

describe('quests', () => {
  it('defines The Grand Feast delivery for the King', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const quest = getQuest(launch, 'QST-0001')
    expect(quest?.['Display Name']).toBe('The Grand Feast')
    expect(quest?.['Objective Target ID']).toBe('ITEM-0058')
    expect(quest?.['Required Quantity']).toBe(10)
    expect(quest?.['Reward XP Amount']).toBe(50_000)
    expect(quest?.['Reward Item ID']).toBe('ITEM-0026')
  })

  it('completes The Grand Feast once with potatoes for cooking XP and a Golden Spud', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = { ...save, inventory: [], currentLocationId: 'LOC-0016' }
    const accepted = acceptQuest(launch, save, 'QST-0001')
    expect(accepted.ok).toBe(true)
    if (!accepted.ok) return
    save = addItemToInventory(accepted.save, 'ITEM-0058', 10)

    const done = completeQuest(launch, save, 'QST-0001')
    expect(done.ok).toBe(true)
    if (!done.ok) return
    expect(done.save.inventory.find((stack) => stack.itemId === 'ITEM-0058')).toBeUndefined()
    expect(done.save.inventory.find((stack) => stack.itemId === 'ITEM-0026')?.quantity).toBe(1)
    expect(done.save.skills.find((skill) => skill.skillId === 'SKL-0007')?.xp).toBe(50_000)
    expect(done.save.quests.find((quest) => quest.questId === 'QST-0001')?.status).toBe(
      'completed',
    )

    const again = acceptQuest(launch, done.save, 'QST-0001')
    expect(again.ok).toBe(false)
  })
})
