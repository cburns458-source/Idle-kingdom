import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { addItemToInventory } from '../activity/rewards'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { acceptQuest, completeQuest } from './quests'
import { locationsForMapView } from '../world/travel'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'public/data/game-database.json'), 'utf8'),
)

describe('quest multi-deliver and unlocks', () => {
  it('completes Help the aspiring apothecary with items, gold, and location unlock', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0023',
      gold: 1_500,
    }
    save = addItemToInventory(save, 'ITEM-0038', 5)
    save = addItemToInventory(save, 'ITEM-0031', 5)

    const accepted = acceptQuest(launch, save, 'QST-0002')
    expect(accepted.ok).toBe(true)
    if (!accepted.ok) return
    save = accepted.save

    const locked = locationsForMapView(launch, 'MAP-0006', save).map((row) => row['Location ID'])
    expect(locked).not.toContain('LOC-0026')

    const completed = completeQuest(launch, save, 'QST-0002')
    expect(completed.ok).toBe(true)
    if (!completed.ok) return
    expect(completed.save.gold).toBe(500)
    expect(completed.save.unlockedLocationIds).toContain('LOC-0026')
    expect(completed.rewards.some((reward) => /Alchemy XP/i.test(reward.label))).toBe(true)
    expect(completed.rewards.some((reward) => /Apothecary/i.test(reward.label))).toBe(true)

    const unlocked = locationsForMapView(launch, 'MAP-0006', completed.save).map(
      (row) => row['Location ID'],
    )
    expect(unlocked).toContain('LOC-0026')
  })
})
