import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { activityVisibleForSave } from '../activity/requirements'
import { addItemToInventory } from '../activity/rewards'
import { prepareDatabase } from '../data/loadDatabase'
import { npcConversation } from '../npcs/conversation'
import { specialProductionStationsVisibleAt } from '../projects/projects'
import { isCosmeticUnlocked } from '../cosmetics/cosmetics'
import { createNewSave } from '../save/saveStore'
import { applyQuestInspectProgress, applyQuestTalkProgress, hasQuestFlag } from './progress'
import {
  acceptQuest,
  applyQuestBranchSkillXp,
  bribeQuestNpc,
  chooseQuestCombatRoute,
  completeQuest,
  donateForQuest,
  getQuestProgress,
} from './quests'
import { applyTravelArrival } from '../world/travel'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('quest tours', () => {
  it('reveals the feast request in stages before turn-in', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = { ...createNewSave(launch), currentLocationId: 'LOC-0016' }

    const accepted = acceptQuest(launch, save, 'QST-0001')
    expect(accepted.ok).toBe(true)
    if (!accepted.ok) return
    save = accepted.save

    expect(completeQuest(launch, save, 'QST-0001').ok).toBe(false)
    save = applyQuestTalkProgress(launch, save, 'NPC-0001')
    expect(completeQuest(launch, save, 'QST-0001').ok).toBe(false)

    save = addItemToInventory(save, 'ITEM-0058', 10)
    expect(completeQuest(launch, save, 'QST-0001').ok).toBe(false)
    save = addItemToInventory(save, 'ITEM-0059', 10)
    const completed = completeQuest(launch, save, 'QST-0001')
    expect(completed.ok).toBe(true)
    if (!completed.ok) return
    expect(completed.rewards.some((reward) => reward.label === '10,000 Cooking XP')).toBe(true)
    expect(completed.rewards.some((reward) => /Golden Spud/i.test(reward.label))).toBe(true)
  })

  it("reveals Rose's shopping list after she is heard", () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = { ...createNewSave(launch), currentLocationId: 'LOC-0023', gold: 1500 }
    save = addItemToInventory(save, 'ITEM-0038', 5)
    save = addItemToInventory(save, 'ITEM-0031', 5)

    const accepted = acceptQuest(launch, save, 'QST-0002')
    expect(accepted.ok).toBe(true)
    if (!accepted.ok) return
    save = accepted.save
    expect(completeQuest(launch, save, 'QST-0002').ok).toBe(false)

    save = applyQuestTalkProgress(launch, save, 'NPC-0005')
    const completed = completeQuest(launch, save, 'QST-0002')
    expect(completed.ok).toBe(true)
    if (!completed.ok) return
    expect(completed.save.unlockedLocationIds).toContain('LOC-0026')
    expect(completed.save.gold).toBe(500)
  })

  it('charges 25 gold, recovers the purse by bribe, and grants the hood plus skill XP', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const beggar = launch.NPCs.find((row) => row['NPC ID'] === 'NPC-0011')!
    expect(beggar['Location ID']).toBe('LOC-0034')

    let save = { ...createNewSave(launch), currentLocationId: 'LOC-0034', gold: 300 }
    const pitched = npcConversation(launch, save, beggar)
    expect(pitched.greeting).toEqual(
      expect.objectContaining({ kind: 'quest_pitch', questId: 'QST-0003' }),
    )

    expect(acceptQuest(launch, save, 'QST-0003').ok).toBe(false)
    const donated = donateForQuest(launch, save, 'QST-0003')
    expect(donated.ok).toBe(true)
    if (!donated.ok) return
    save = donated.save
    expect(save.gold).toBe(275)
    expect(getQuestProgress(save, 'QST-0003').status).toBe('inactive')
    const accepted = acceptQuest(launch, save, 'QST-0003')
    expect(accepted.ok).toBe(true)
    if (!accepted.ok) return
    save = accepted.save
    expect(save.gold).toBe(275)

    save = { ...save, currentLocationId: 'LOC-0024' }
    save = applyQuestTalkProgress(launch, save, 'NPC-0007')
    save = { ...save, currentLocationId: 'LOC-0017' }
    save = applyQuestTalkProgress(launch, save, 'NPC-0012')
    const bribed = bribeQuestNpc(launch, save, 'QST-0003')
    expect(bribed.ok).toBe(true)
    if (!bribed.ok) return
    save = bribed.save
    expect(save.gold).toBe(75)
    expect(save.inventory.find((stack) => stack.itemId === 'ITEM-0299')?.quantity).toBe(1)
    expect(activityVisibleForSave(launch, save, 'ACT-0034')).toBe(false)

    save = { ...save, currentLocationId: 'LOC-0034' }
    const completed = completeQuest(launch, save, 'QST-0003')
    expect(completed.ok).toBe(true)
    if (!completed.ok) return
    expect(completed.pendingSkillXp).toBe(2500)
    expect(completed.save.gold).toBe(575)
    expect(isCosmeticUnlocked(completed.save, 'COS-0002')).toBe(true)
    const mining = applyQuestBranchSkillXp(launch, completed.save, 'SKL-0002', 2500)
    expect(mining.ok).toBe(true)
    if (!mining.ok) return
    expect(mining.save.skills.find((skill) => skill.skillId === 'SKL-0002')?.xp).toBeGreaterThan(0)
  })

  it('opens Pressure the Guards only on the combat route, then grants Combat XP', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = { ...createNewSave(launch), currentLocationId: 'LOC-0034', gold: 25 }
    const donated = donateForQuest(launch, save, 'QST-0003')
    expect(donated.ok).toBe(true)
    if (!donated.ok) return
    save = donated.save
    const accepted = acceptQuest(launch, save, 'QST-0003')
    expect(accepted.ok).toBe(true)
    if (!accepted.ok) return
    save = accepted.save
    expect(activityVisibleForSave(launch, save, 'ACT-0034')).toBe(false)

    save = { ...save, currentLocationId: 'LOC-0017' }
    save = applyQuestTalkProgress(launch, save, 'NPC-0007')
    save = applyQuestTalkProgress(launch, save, 'NPC-0012')
    const combat = chooseQuestCombatRoute(save, 'QST-0003')
    expect(combat.ok).toBe(true)
    if (!combat.ok) return
    save = combat.save
    expect(hasQuestFlag(save, 'QST-0003', 'choice:combat')).toBe(true)
    expect(activityVisibleForSave(launch, save, 'ACT-0034')).toBe(true)

    save = addItemToInventory(save, 'ITEM-0299', 1)
    expect(activityVisibleForSave(launch, save, 'ACT-0034')).toBe(false)
    save = { ...save, currentLocationId: 'LOC-0034' }
    const completed = completeQuest(launch, save, 'QST-0003')
    expect(completed.ok).toBe(true)
    if (!completed.ok) return
    expect(completed.pendingSkillXp).toBe(0)
    expect(completed.rewards.some((reward) => /Combat XP/i.test(reward.label))).toBe(true)
  })

  it('auto-starts Visiting the Citadel on arriving at the plaza and pays 1000 gold', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = createNewSave(launch)
    save = applyTravelArrival(launch, save, 'LOC-0028', Date.parse('2026-01-01T00:00:00.000Z'))
    expect(getQuestProgress(save, 'QST-0004').status).toBe('active')
    expect(launch.Quests.find((row) => row['Quest ID'] === 'QST-0004')?.Notes).toMatch(
      /AutoStart:\s*LOC-0028/,
    )

    save = applyTravelArrival(launch, save, 'LOC-0029', Date.parse('2026-01-01T00:00:01.000Z'))
    save = applyTravelArrival(launch, save, 'LOC-0030', Date.parse('2026-01-01T00:00:02.000Z'))
    save = applyTravelArrival(launch, save, 'LOC-0035', Date.parse('2026-01-01T00:00:03.000Z'))
    save = applyTravelArrival(launch, save, 'LOC-0033', Date.parse('2026-01-01T00:00:04.000Z'))
    save = applyQuestTalkProgress(launch, save, 'NPC-0013')
    save = applyQuestTalkProgress(launch, save, 'NPC-0006')
    save = applyQuestInspectProgress(launch, save, 'bazaar')
    save = applyQuestInspectProgress(launch, save, 'bounties')
    save = applyQuestInspectProgress(launch, save, 'processing')
    save = { ...save, currentLocationId: 'LOC-0028' }
    const completed = completeQuest(launch, save, 'QST-0004')
    expect(completed.ok).toBe(true)
    if (!completed.ok) return
    expect(completed.save.gold).toBe(save.gold + 1000)
  })

  it('locks Delve and Mages quarters until Wizard Studies is accepted', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = { ...createNewSave(launch), currentLocationId: 'LOC-0007' }
    expect(activityVisibleForSave(launch, save, 'ACT-0008')).toBe(false)
    expect(
      specialProductionStationsVisibleAt(launch, save, 'LOC-0007').some(
        (station) => station.facility['Facility ID'] === 'FAC-0008',
      ),
    ).toBe(false)

    const accepted = acceptQuest(launch, save, 'QST-0005')
    expect(accepted.ok).toBe(true)
    if (!accepted.ok) return
    save = accepted.save
    expect(activityVisibleForSave(launch, save, 'ACT-0008')).toBe(true)
    expect(
      specialProductionStationsVisibleAt(launch, save, 'LOC-0007').some(
        (station) => station.facility['Facility ID'] === 'FAC-0008',
      ),
    ).toBe(true)

    save = applyQuestTalkProgress(launch, save, 'NPC-0004')
    save = addItemToInventory(save, 'ITEM-0011', 10)
    const completed = completeQuest(launch, save, 'QST-0005')
    expect(completed.ok).toBe(true)
    if (!completed.ok) return
    expect(completed.rewards.some((reward) => /Arcana XP/i.test(reward.label))).toBe(true)
    expect(completed.save.unlockedNpcIds).toContain('NPC-0004')
    expect(activityVisibleForSave(launch, completed.save, 'ACT-0008')).toBe(true)
  })
})
