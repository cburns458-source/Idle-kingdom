import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { activityVisibleForSave } from '../activity/requirements'
import { addItemToInventory } from '../activity/rewards'
import { raiseSkillToMinimumLevel } from '../activity/xp'
import { prepareDatabase } from '../data/loadDatabase'
import { chooseCombatForQuest, npcConversation, questTalkLine, talkWithQuestNpc } from '../npcs/conversation'
import { npcsAtLocationForSave } from '../npcs/knowledge'
import { specialProductionStationsVisibleAt } from '../projects/projects'
import { isCosmeticUnlocked } from '../cosmetics/cosmetics'
import { createNewSave } from '../save/saveStore'
import type { PlayerSave } from '../save/types'
import { inventoryCount } from '../production/recipes'
import {
  applyQuestActionProgress,
  applyQuestAutoStartOnSeed,
  applyQuestLocationProgressResult,
  applyQuestProcessProgress,
  applyQuestTalkProgress,
  applyQuestVisitProgress,
  FOREST_OFFERING_PLACED_MESSAGE,
  hasQuestFlag,
} from './progress'
import {
  acceptQuest,
  applyQuestAutoCompleteOnAction,
  applyQuestBranchSkillXp,
  bribeQuestNpc,
  chooseQuestCombatRoute,
  completeQuest,
  donateForQuest,
  getQuest,
  getQuestProgress,
  resetIntroFlags,
  resetQuestProgress,
} from './quests'
import { formatQuestProgressLine } from './objectives'
import { getCurrentStepId, questActionProgressForActivity, questStepJournal } from './steps'
import { questLog } from '../log/log'
import {
  CAVE_MAP_ID,
  FOREST_MAP_ID,
  MIRROR_LAKE_ID,
  OLD_ENT_GROVE_ID,
  SMALL_CLEARING_ID,
  STARLIGHT_GLADE_ID,
} from '../world/constants'
import { applyHostileTravelArrival } from '../world/hostility'
import { applyTravelArrival, applyTravelArrivalResult, canTravelTo, locationsForMapView } from '../world/travel'
import { hideFromQuestLog } from './miniquests'
import { canPlantBotanySeed, farmBotanyUnlocked, plantBotanySeed } from '../timers/locationTimers'
import { questVisitHintLocationId } from './hints'

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
    save = addItemToInventory(save, 'ITEM-0028', 5)
    save = addItemToInventory(save, 'ITEM-0042', 5)

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
    expect(completeQuest(launch, save, 'QST-0003').ok).toBe(false)

    save = applyQuestTalkProgress(launch, save, 'NPC-0011')
    expect(completeQuest(launch, save, 'QST-0003').ok).toBe(false)

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
    expect(completed.pendingSkillXp).toBe(25000)
    expect(completed.save.gold).toBe(575)
    expect(isCosmeticUnlocked(completed.save, 'COS-0002')).toBe(true)
    const mining = applyQuestBranchSkillXp(launch, completed.save, 'SKL-0002', 25000)
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

    save = applyQuestTalkProgress(launch, save, 'NPC-0011')
    save = { ...save, currentLocationId: 'LOC-0017' }
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
    expect(completed.rewards.some((reward) => /25,000 Might XP/i.test(reward.label))).toBe(true)
  })

  it('lets the general store merchant hint at the barracks without requiring it', () => {
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
    save = applyQuestTalkProgress(launch, save, 'NPC-0007')
    expect(hasQuestFlag(save, 'QST-0003', 'talk:NPC-0007')).toBe(false)

    save = applyQuestTalkProgress(launch, save, 'NPC-0011')
    save = { ...save, currentLocationId: 'LOC-0024' }
    save = applyQuestTalkProgress(launch, save, 'NPC-0007')
    expect(hasQuestFlag(save, 'QST-0003', 'talk:NPC-0007')).toBe(true)
    expect(completeQuest(launch, save, 'QST-0003').ok).toBe(false)

    save = { ...save, currentLocationId: 'LOC-0017' }
    save = applyQuestTalkProgress(launch, save, 'NPC-0012')
    save = addItemToInventory(save, 'ITEM-0299', 1)
    save = { ...save, currentLocationId: 'LOC-0034' }
    expect(completeQuest(launch, save, 'QST-0003').ok).toBe(true)
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
    save = applyTravelArrival(launch, save, 'LOC-0031', Date.parse('2026-01-01T00:00:04.000Z'))
    expect(getQuestProgress(save, 'QST-0004').status).toBe('active')
    expect(completeQuest(launch, save, 'QST-0004').ok).toBe(false)

    save = applyTravelArrival(launch, save, 'LOC-0032', Date.parse('2026-01-01T00:00:05.000Z'))
    expect(getQuestProgress(save, 'QST-0004').status).toBe('completed')
    expect(save.gold).toBe(createNewSave(launch).gold + 1000)
  })

  it('locks Harness essence until accept and Mages quarters until Wizard Studies is completed', () => {
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
    ).toBe(false)

    save = addItemToInventory(save, 'ITEM-0011', 10)
    expect(completeQuest(launch, save, 'QST-0005').ok).toBe(false)
    save = applyQuestTalkProgress(launch, save, 'NPC-0004')
    expect(hasQuestFlag(save, 'QST-0005', 'talk:NPC-0004')).toBe(false)
    expect(completeQuest(launch, save, 'QST-0005').ok).toBe(false)

    save = applyQuestTalkProgress(launch, save, 'NPC-0009')
    expect(completeQuest(launch, save, 'QST-0005').ok).toBe(false)
    save = applyQuestTalkProgress(launch, save, 'NPC-0004')
    const completed = completeQuest(launch, save, 'QST-0005')
    expect(completed.ok).toBe(true)
    if (!completed.ok) return
    expect(completed.rewards.some((reward) => /Arcana XP/i.test(reward.label))).toBe(true)
    expect(completed.rewards.some((reward) => reward.label === 'Unlocked Mages quarters')).toBe(
      true,
    )
    expect(completed.save.unlockedNpcIds).toContain('NPC-0004')
    expect(activityVisibleForSave(launch, completed.save, 'ACT-0008')).toBe(true)
    expect(
      specialProductionStationsVisibleAt(launch, completed.save, 'LOC-0007').some(
        (station) => station.facility['Facility ID'] === 'FAC-0008',
      ),
    ).toBe(true)
  })

  it('walks Getting Started from accept through Fennel looking at cooked potatoes', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const fennel = launch.NPCs.find((row) => row['NPC ID'] === 'NPC-0014')!
    expect(fennel['Location ID']).toBe('LOC-0001')

    let save = { ...createNewSave(launch), currentLocationId: 'LOC-0001' }
    const accepted = acceptQuest(launch, save, 'QST-0006')
    expect(accepted.ok).toBe(true)
    if (!accepted.ok) return
    save = accepted.save

    expect(npcConversation(launch, save, fennel).quests[0]?.canTalk).toBe(false)
    expect(npcConversation(launch, save, fennel).quests[0]?.canTurnIn).toBe(false)

    save = addItemToInventory(save, 'ITEM-0025', 5)
    expect(npcConversation(launch, save, fennel).quests[0]?.canTalk).toBe(true)
    expect(npcConversation(launch, save, fennel).quests[0]?.talkLine).toMatch(
      /you can cook them at the kitchen/i,
    )
    expect(npcConversation(launch, save, fennel).quests[0]?.talkLine).not.toMatch(
      /Open the world map/i,
    )
    save = applyQuestTalkProgress(launch, save, 'NPC-0014')
    expect(save.inventory.find((stack) => stack.itemId === 'ITEM-0025')?.quantity).toBe(5)

    save = applyQuestVisitProgress(launch, save, 'LOC-0023')
    save = applyQuestProcessProgress(launch, save, 'RCP-0001', 5)
    save = addItemToInventory(save, 'ITEM-0058', 5)
    save = { ...save, currentLocationId: 'LOC-0001' }
    expect(npcConversation(launch, save, fennel).quests[0]?.talkLine).toMatch(/sword and shield/i)

    const advice = talkWithQuestNpc(launch, save, 'NPC-0014')
    expect(advice.ok).toBe(true)
    if (!advice.ok) return
    expect(getQuestProgress(advice.save, 'QST-0006').status).toBe('active')
    expect(npcConversation(launch, advice.save, fennel).quests[0]?.talkLine).toMatch(
      /Good luck on your adventure/i,
    )

    const finished = talkWithQuestNpc(launch, advice.save, 'NPC-0014')
    expect(finished.ok).toBe(true)
    if (!finished.ok) return
    expect(getQuestProgress(finished.save, 'QST-0006').status).toBe('completed')
    expect(finished.save.unlockedBookIds).toContain('BOOK-0001')
    expect(finished.save.inventory.find((stack) => stack.itemId === 'ITEM-0058')?.quantity).toBe(5)
    expect(npcsAtLocationForSave(launch, finished.save, 'LOC-0001').map((npc) => npc['NPC ID'])).toEqual(['NPC-0014'])
  })

  it('walks Forged in Fire and Going Deeper, and keeps a player already in the shaft', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const merchant = launch.NPCs.find((row) => row['NPC ID'] === 'NPC-0008')!
    const helge = launch.NPCs.find((row) => row['NPC ID'] === 'NPC-0015')!
    expect(helge['Location ID']).toBe('LOC-0038')

    let save = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0012',
      skills: [
        { skillId: 'SKL-0008', level: 35, xp: 0 },
        { skillId: 'SKL-0011', level: 35, xp: 0 },
        { skillId: 'SKL-0002', level: 60, xp: 0 },
      ],
    }
    expect(npcConversation(launch, { ...save, skills: [] }, merchant).quests).toEqual([])

    const pitched = npcConversation(launch, save, merchant)
    expect(pitched.quests[0]?.questId).toBe('QST-0007')
    expect(pitched.quests[0]?.pitchLine).toMatch(/old forge/)
    expect(pitched.quests[0]?.canAccept).toBe(true)

    const accepted = acceptQuest(launch, save, 'QST-0007')
    expect(accepted.ok).toBe(true)
    if (!accepted.ok) return
    save = accepted.save
    expect(save.unlockedLocationIds).toContain('LOC-0038')
    expect(specialProductionStationsVisibleAt(launch, save, 'LOC-0038')).toEqual([])

    save = { ...save, currentLocationId: 'LOC-0038' }
    save = applyQuestVisitProgress(launch, save, 'LOC-0038')
    save = applyQuestTalkProgress(launch, save, 'NPC-0015')
    save = addItemToInventory(save, 'ITEM-0077', 20)
    save = addItemToInventory(save, 'ITEM-0006', 100)
    save = applyQuestTalkProgress(launch, save, 'NPC-0015')
    const forged = completeQuest(launch, save, 'QST-0007')
    expect(forged.ok).toBe(true)
    if (!forged.ok) return
    expect(forged.rewards.some((reward) => /Smithing XP/i.test(reward.label))).toBe(true)
    expect(forged.rewards.some((reward) => /Metallurgy XP/i.test(reward.label))).toBe(true)
    save = forged.save
    expect(save.inventory.find((stack) => stack.itemId === 'ITEM-0077')).toBeUndefined()
    expect(specialProductionStationsVisibleAt(launch, save, 'LOC-0038').length).toBeGreaterThan(0)

    const deeperPitch = npcConversation(launch, save, helge)
    expect(deeperPitch.quests.some((quest) => quest.questId === 'QST-0008' && quest.canAccept)).toBe(
      true,
    )
    const deeper = acceptQuest(launch, save, 'QST-0008')
    expect(deeper.ok).toBe(true)
    if (!deeper.ok) return
    save = deeper.save
    save = applyQuestTalkProgress(launch, save, 'NPC-0015')
    expect(activityVisibleForSave(launch, save, 'ACT-0044')).toBe(true)
    expect(
      locationsForMapView(launch, CAVE_MAP_ID, save).map((row) => row['Location ID']),
    ).not.toContain('LOC-0022')
    save = applyQuestVisitProgress(launch, save, 'LOC-0011')
    save = applyQuestActionProgress(launch, save, 'ACN-0177', 50)
    expect(activityVisibleForSave(launch, { ...createNewSave(launch) }, 'ACT-0044')).toBe(false)
    expect(
      locationsForMapView(launch, CAVE_MAP_ID, save).map((row) => row['Location ID']),
    ).toContain('LOC-0022')
    expect(canTravelTo(launch, 'LOC-0011', 'LOC-0022', CAVE_MAP_ID, save)).toBe(true)

    const arrived = applyTravelArrival(launch, save, 'LOC-0022')
    expect(getQuestProgress(arrived, 'QST-0008').status).toBe('completed')
    expect(arrived.unlockedLocationIds).toContain('LOC-0022')
    expect(arrived.inventory.find((stack) => stack.itemId === 'ITEM-0313')?.quantity).toBe(1)
    expect(activityVisibleForSave(launch, arrived, 'ACT-0044')).toBe(false)

    const stillInside = applyTravelArrival(
      launch,
      { ...createNewSave(launch), currentLocationId: 'LOC-0022' },
      'LOC-0022',
    )
    expect(stillInside.currentLocationId).toBe('LOC-0022')
    expect(
      locationsForMapView(launch, CAVE_MAP_ID, stillInside).map((row) => row['Location ID']),
    ).toContain('LOC-0022')
    const leftHidden = applyTravelArrival(launch, stillInside, 'LOC-0011')
    expect(leftHidden.currentLocationId).toBe('LOC-0011')
    expect(leftHidden.unlockedLocationIds ?? []).not.toContain('LOC-0022')
    expect(
      locationsForMapView(launch, CAVE_MAP_ID, leftHidden).map((row) => row['Location ID']),
    ).not.toContain('LOC-0022')
    expect(canTravelTo(launch, 'LOC-0011', 'LOC-0022', CAVE_MAP_ID, leftHidden)).toBe(false)
  })

  it('lists rubble counts on the Going Deeper journal and activity card', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = applyQuestTalkProgress(
      launch,
      {
        ...createNewSave(launch),
        currentLocationId: 'LOC-0011',
        quests: [{ questId: 'QST-0008', status: 'active' as const, progress: 0, counters: {} }],
      },
      'NPC-0015',
    )
    const quest = getQuest(launch, 'QST-0008')!
    const journal = questStepJournal(launch, save, quest).map((step) => step.label)
    expect(journal).toContain('Clear rubble in the Deep Mines')
    expect(journal).toContain('Clear a rubble pile 0 / 50')

    const card = questActionProgressForActivity(launch, save, 'ACT-0044')
    expect(card.map((line) => `${line.label} ${line.current} / ${line.required}`)).toEqual([
      'Clear a rubble pile 0 / 50',
    ])

    save = applyQuestActionProgress(launch, save, 'ACN-0177', 12)
    expect(
      questActionProgressForActivity(launch, save, 'ACT-0044').map((line) =>
        formatQuestProgressLine(line),
      ),
    ).toEqual(['Clear a rubble pile 12 / 50'])
    expect(questStepJournal(launch, save, quest).map((step) => step.label)).toContain(
      'Clear a rubble pile 12 / 50',
    )

    save = applyQuestActionProgress(launch, save, 'ACN-0177', 88)
    expect(
      questActionProgressForActivity(launch, save, 'ACT-0044').map((line) =>
        formatQuestProgressLine(line),
      ),
    ).toEqual(['Clear a rubble pile 50 / 50'])
    expect(questStepJournal(launch, save, quest).map((step) => step.label)).toContain(
      'Clear a rubble pile 50 / 50',
    )
  })

  it('hides the barracks journal line until the merchant talks, and lets recover skip asking around', () => {
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
    save = applyQuestTalkProgress(launch, save, 'NPC-0011')
    const quest = getQuest(launch, 'QST-0003')!
    expect(questStepJournal(launch, save, quest).map((step) => step.label).join('\n')).not.toMatch(
      /Barracks|guard/i,
    )

    save = applyQuestTalkProgress(launch, { ...save, currentLocationId: 'LOC-0024' }, 'NPC-0007')
    expect(questStepJournal(launch, save, quest).map((step) => step.label).join('\n')).toMatch(
      /guard/i,
    )

    const skipped = addItemToInventory(
      {
        ...createNewSave(launch),
        currentLocationId: 'LOC-0034',
        gold: 25,
        quests: [
          {
            questId: 'QST-0003',
            status: 'active' as const,
            progress: 1,
            counters: { 'talk:NPC-0011': 1 },
          },
        ],
      },
      'ITEM-0299',
      1,
    )
    const afterSkip = questStepJournal(launch, skipped, quest).map((step) => step.label)
    expect(afterSkip).toContain('Recover what was taken')
  })

  it('auto-starts Pressure the Guards at the barracks and on arrival', () => {
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
    save = applyQuestTalkProgress(launch, save, 'NPC-0011')
    save = { ...save, currentLocationId: 'LOC-0017' }
    const combat = chooseCombatForQuest(launch, save, 'QST-0003', Date.parse('2026-01-01T00:00:00.000Z'))
    expect(combat.ok).toBe(true)
    if (!combat.ok) return
    expect(combat.startedActivity).toBe(true)
    expect(combat.save.currentActivityId).toBe('ACT-0034')

    let elsewhere = { ...createNewSave(launch), currentLocationId: 'LOC-0034', gold: 25 }
    const donatedAway = donateForQuest(launch, elsewhere, 'QST-0003')
    expect(donatedAway.ok).toBe(true)
    if (!donatedAway.ok) return
    elsewhere = donatedAway.save
    const acceptedAway = acceptQuest(launch, elsewhere, 'QST-0003')
    expect(acceptedAway.ok).toBe(true)
    if (!acceptedAway.ok) return
    elsewhere = acceptedAway.save
    elsewhere = applyQuestTalkProgress(launch, elsewhere, 'NPC-0011')
    elsewhere = { ...elsewhere, currentLocationId: 'LOC-0002' }
    const flagged = chooseCombatForQuest(
      launch,
      elsewhere,
      'QST-0003',
      Date.parse('2026-01-01T00:00:00.000Z'),
    )
    expect(flagged.ok).toBe(true)
    if (!flagged.ok) return
    expect(flagged.startedActivity).toBe(false)
    const arrived = applyHostileTravelArrival(
      launch,
      flagged.save,
      'LOC-0017',
      Date.parse('2026-01-01T00:00:01.000Z'),
    )
    expect(arrived.save.currentActivityId).toBe('ACT-0034')
  })

  it('returns Going Deeper rewards when walking into the abandoned shaft', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = applyQuestTalkProgress(
      launch,
      {
        ...createNewSave(launch),
        currentLocationId: 'LOC-0011',
        quests: [{ questId: 'QST-0008', status: 'active' as const, progress: 0, counters: {} }],
      },
      'NPC-0015',
    )
    save = applyQuestVisitProgress(launch, save, 'LOC-0011')
    save = applyQuestActionProgress(launch, save, 'ACN-0177', 50)
    const arrival = applyTravelArrivalResult(launch, save, 'LOC-0022')
    expect(arrival.save.quests.find((row) => row.questId === 'QST-0008')?.status).toBe('completed')
    expect(arrival.questCompletions).toHaveLength(1)
    expect(arrival.questCompletions[0]!.questName).toBe('Going Deeper')
    expect(arrival.questCompletions[0]!.message).toMatch(/^Thank you/)
    expect(questTalkLine(launch, 'QST-0008', 'NPC-0015', arrival.save)).toMatch(/rebuild our empire/)
  })

  it('pulses Getting Started map hints until the step finishes', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const cook = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0023',
      inventory: [{ itemId: 'ITEM-0025', quantity: 5 }],
      quests: [
        {
          questId: 'QST-0006',
          status: 'active' as const,
          progress: 0,
          counters: { 'talk:NPC-0014': 1, 'talk:NPC-0014:QSTP-0014': 1, 'visit:LOC-0023': 1 },
        },
      ],
    }
    expect(questVisitHintLocationId(launch, cook)).toBe('LOC-0023')
    const bring = {
      ...cook,
      currentLocationId: 'LOC-0002',
      inventory: [
        { itemId: 'ITEM-0025', quantity: 5 },
        { itemId: 'ITEM-0058', quantity: 5 },
      ],
      quests: [
        {
          questId: 'QST-0006',
          status: 'active' as const,
          progress: 0,
          counters: {
            'talk:NPC-0014': 1,
            'talk:NPC-0014:QSTP-0014': 1,
            'visit:LOC-0023': 1,
            'process:RCP-0001': 5,
          },
        },
      ],
    }
    expect(questVisitHintLocationId(launch, bring)).toBe('LOC-0001')

    const citadel = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0028',
      quests: [{ questId: 'QST-0004', status: 'active' as const, progress: 0, counters: {} }],
    }
    expect(questVisitHintLocationId(launch, citadel)).toBeNull()
  })

  it('does not auto-start Through the Thicket; the Old Forester offers it by hand', () => {
    const { launch } = prepareDatabase(rawDatabase)
    expect(launch.NPCs.find((row) => row['NPC ID'] === 'NPC-0017')?.['Display Name']).toBe(
      'Old Forester',
    )
    const arrived = applyTravelArrival(launch, createNewSave(launch), 'LOC-0040')
    expect(getQuestProgress(arrived, 'QST-0010').status).toBe('inactive')
    expect(acceptQuest(launch, arrived, 'QST-0010').ok).toBe(false)

    let ready = raiseSkillToMinimumLevel(arrived, launch, 'SKL-0006', 40).save
    ready = raiseSkillToMinimumLevel(ready, launch, 'SKL-0014', 35).save
    const accepted = acceptQuest(launch, ready, 'QST-0010')
    expect(accepted.ok).toBe(true)
    if (!accepted.ok) return
    const quest = getQuest(launch, 'QST-0010')!
    expect(
      questLog(launch, accepted.save)
        .find((row) => row.questId === 'QST-0010')
        ?.steps.map((step) => step.label),
    ).toEqual(
      expect.arrayContaining(['Clear fifty vines on the Forest Path', 'Chop vines 0 / 50']),
    )
    expect(
      questActionProgressForActivity(launch, accepted.save, 'ACT-0048').map((line) =>
        formatQuestProgressLine(line),
      ),
    ).toEqual(['Chop vines 0 / 50'])
    expect(getCurrentStepId(launch, accepted.save, quest)).toBe('QSTP-0025')
  })

  it('opens each inner grove after ten vines and finishes Through the Thicket on the last talk', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save = raiseSkillToMinimumLevel(
      { ...createNewSave(launch), currentLocationId: 'LOC-0040' },
      launch,
      'SKL-0006',
      40,
    ).save
    save = raiseSkillToMinimumLevel(save, launch, 'SKL-0014', 35).save
    const accepted = acceptQuest(launch, save, 'QST-0010')
    expect(accepted.ok).toBe(true)
    if (!accepted.ok) return
    save = accepted.save
    const quest = getQuest(launch, 'QST-0010')!

    expect(activityVisibleForSave(launch, save, 'ACT-0077')).toBe(false)
    expect(activityVisibleForSave(launch, save, 'ACT-0080')).toBe(false)
    save = applyQuestActionProgress(launch, save, 'ACN-0179', 49)
    expect(save.unlockedLocationIds ?? []).not.toContain(SMALL_CLEARING_ID)
    expect(applyQuestAutoCompleteOnAction(launch, save).save.quests.find((row) => row.questId === 'QST-0010')?.status).toBe(
      'active',
    )
    save = applyQuestActionProgress(launch, save, 'ACN-0179', 1)
    expect(save.unlockedLocationIds).toEqual(expect.arrayContaining([SMALL_CLEARING_ID]))
    expect(getQuestProgress(save, 'QST-0010').status).toBe('active')
    expect(questActionProgressForActivity(launch, save, 'ACT-0048')).toEqual([])
    expect(getCurrentStepId(launch, save, quest)).toBe('QSTP-0026')

    const talkedBack = talkWithQuestNpc(launch, save, 'NPC-0017')
    expect(talkedBack.ok).toBe(true)
    if (!talkedBack.ok) return
    save = talkedBack.save
    expect(activityVisibleForSave(launch, save, 'ACT-0077')).toBe(true)
    save = applyQuestActionProgress(launch, save, 'ACN-0231', 10)
    expect(save.unlockedLocationIds).toEqual(expect.arrayContaining([STARLIGHT_GLADE_ID]))
    expect(activityVisibleForSave(launch, save, 'ACT-0077')).toBe(false)

    save = applyQuestActionProgress(launch, save, 'ACN-0232', 10)
    expect(save.unlockedLocationIds).toEqual(expect.arrayContaining([MIRROR_LAKE_ID]))
    save = applyQuestActionProgress(launch, save, 'ACN-0233', 10)
    expect(save.unlockedLocationIds).toEqual(expect.arrayContaining([OLD_ENT_GROVE_ID]))
    const afterVinesTalk = talkWithQuestNpc(launch, save, 'NPC-0017')
    expect(afterVinesTalk.ok).toBe(true)
    if (!afterVinesTalk.ok) return
    save = afterVinesTalk.save
    expect(activityVisibleForSave(launch, save, 'ACT-0080')).toBe(true)

    save = applyQuestProcessProgress(launch, save, 'RCP-0071', 4)
    expect(getCurrentStepId(launch, save, quest)).toBe('QSTP-0032')
    save = addItemToInventory(save, 'ITEM-0405', 4)
    expect(applyQuestLocationProgressResult(launch, save, SMALL_CLEARING_ID).message).toBe(
      FOREST_OFFERING_PLACED_MESSAGE,
    )
    const silent = applyQuestLocationProgressResult(
      launch,
      { ...save, inventory: [] },
      SMALL_CLEARING_ID,
    )
    expect(silent.message).toBeNull()
    expect(hasQuestFlag(silent.save, 'QST-0010', `visit:${SMALL_CLEARING_ID}`)).toBe(false)

    save = applyQuestLocationProgressResult(launch, save, SMALL_CLEARING_ID).save
    expect(inventoryCount(save, 'ITEM-0405')).toBe(3)
    save = applyQuestLocationProgressResult(launch, save, STARLIGHT_GLADE_ID).save
    save = applyQuestLocationProgressResult(launch, save, MIRROR_LAKE_ID).save
    save = applyQuestLocationProgressResult(launch, save, OLD_ENT_GROVE_ID).save
    expect(inventoryCount(save, 'ITEM-0405')).toBe(0)

    const finished = talkWithQuestNpc(launch, save, 'NPC-0017')
    expect(finished.ok).toBe(true)
    if (!finished.ok) return
    expect(getQuestProgress(finished.save, 'QST-0010').status).toBe('completed')
    expect(inventoryCount(finished.save, 'ITEM-0406')).toBe(1)
    expect(activityVisibleForSave(launch, finished.save, 'ACT-0080')).toBe(false)
    expect(
      locationsForMapView(launch, FOREST_MAP_ID, finished.save).map((row) => row['Location ID']),
    ).toEqual(
      expect.arrayContaining([
        SMALL_CLEARING_ID,
        STARLIGHT_GLADE_ID,
        MIRROR_LAKE_ID,
        OLD_ENT_GROVE_ID,
      ]),
    )
    expect(canTravelTo(launch, 'LOC-0040', OLD_ENT_GROVE_ID, FOREST_MAP_ID, finished.save)).toBe(true)

    const completer = {
      ...createNewSave(launch),
      quests: [{ questId: 'QST-0010', status: 'completed' as const, progress: 0 }],
    }
    expect(
      locationsForMapView(launch, FOREST_MAP_ID, completer).map((row) => row['Location ID']),
    ).toEqual(
      expect.arrayContaining([
        SMALL_CLEARING_ID,
        STARLIGHT_GLADE_ID,
        MIRROR_LAKE_ID,
        OLD_ENT_GROVE_ID,
      ]),
    )
    expect(acceptQuest(launch, { ...completer, currentLocationId: 'LOC-0040' }, 'QST-0010').ok).toBe(
      false,
    )
  })

  it('starts Green Thumb on a seed, unlocks the farm after Fennel, and finishes on plant', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const quest = getQuest(launch, 'QST-0011')!
    expect(quest['Display Name']).toBe('Green Thumb')
    expect(hideFromQuestLog(quest)).toBe(false)

    let save = {
      ...createNewSave(launch),
      currentLocationId: 'LOC-0001',
      inventory: [{ itemId: 'ITEM-0324', quantity: 1 }],
    }
    save = applyQuestAutoStartOnSeed(launch, save)
    expect(getQuestProgress(save, 'QST-0011').status).toBe('active')
    expect(questLog(launch, save).some((row) => row.questId === 'QST-0011')).toBe(true)
    expect(farmBotanyUnlocked(save)).toBe(false)
    expect(canPlantBotanySeed(launch, save, 'ITEM-0324').ok).toBe(false)

    const talked = talkWithQuestNpc(launch, save, 'NPC-0014')
    expect(talked.ok).toBe(true)
    if (!talked.ok) return
    save = talked.save
    expect(save.inventory.find((stack) => stack.itemId === 'ITEM-0324')?.quantity).toBe(2)
    expect(farmBotanyUnlocked(save)).toBe(true)
    expect(hasQuestFlag(save, 'QST-0011', 'talk:NPC-0014')).toBe(true)

    const planted = plantBotanySeed(launch, save, 'ITEM-0324', 0, 1)
    expect(planted.ok).toBe(true)
    if (!planted.ok) return
    expect(getQuestProgress(planted.save, 'QST-0011').status).toBe('completed')
    expect(planted.save.unlockedBookIds).toContain('BOOK-0002')

    const again = applyQuestAutoStartOnSeed(launch, {
      ...planted.save,
      inventory: [{ itemId: 'ITEM-0324', quantity: 3 }],
    })
    expect(getQuestProgress(again, 'QST-0011').status).toBe('completed')
  })

  it('resets selected quests and intro flags only', () => {
    const { launch } = prepareDatabase(rawDatabase)
    let save: PlayerSave = {
      ...createNewSave(launch),
      hasSeenFennelIntro: true,
      hasSeenWardrobeIntro: true,
      quests: [
        { questId: 'QST-0004', status: 'completed' as const, progress: 3 },
        { questId: 'QST-0006', status: 'active' as const, progress: 1 },
      ],
      miniquestCompletedAt: { 'QST-0003': '2026-01-01T00:00:00.000Z' },
    }
    save = resetQuestProgress(save, ['QST-0004'])
    expect(getQuestProgress(save, 'QST-0004').status).toBe('inactive')
    expect(getQuestProgress(save, 'QST-0006').status).toBe('active')
    expect(save.miniquestCompletedAt['QST-0003']).toBe('2026-01-01T00:00:00.000Z')

    save = resetQuestProgress(save, ['QST-0003'])
    expect(save.miniquestCompletedAt['QST-0003']).toBeUndefined()

    save = resetIntroFlags(save, { fennel: true })
    expect(save.hasSeenFennelIntro).toBe(false)
    expect(save.hasSeenWardrobeIntro).toBe(true)
  })
})
