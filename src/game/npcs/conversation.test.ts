import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { addItemToInventory } from '../activity/rewards'
import { prepareDatabase } from '../data/loadDatabase'
import type { GameDatabase, QuestDialogueRow } from '../data/types'
import { createNewSave } from '../save/saveStore'
import { completeQuest } from '../quests/quests'
import type { PlayerSave } from '../save/types'
import { applyQuestAutoStartOnSeed } from '../quests/progress'
import { chooseDialogue } from '../dialogue/engine'
import { npcConversation, learnMentorProjects, questSpokenLine, takeMerchantTip } from './conversation'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)
const { launch } = prepareDatabase(rawDatabase)

function npc(npcId: string) {
  const row = launch.NPCs.find((candidate) => candidate['NPC ID'] === npcId)
  if (!row) throw new Error(`missing ${npcId}`)
  return row
}

function saveAt(locationId: string): PlayerSave {
  return { ...createNewSave(launch), currentLocationId: locationId }
}

/** The shipped content minus one quest line, to show what that line alone adds. */
function withoutQuestLine(dialogueId: string): GameDatabase {
  return {
    ...launch,
    QuestDialogue: launch.QuestDialogue.filter((row) => row['Dialogue ID'] !== dialogueId),
  }
}

/** The Barracks Guard's shipped closing line for Lowly Beggar (QDL-0031). */
const GUARD_CLOSING_LINE_ID = 'QDL-0031'
const GUARD_CLOSING_LINE: QuestDialogueRow = {
  'Dialogue ID': GUARD_CLOSING_LINE_ID,
  'Quest ID': 'QST-0003',
  'NPC ID': 'NPC-0012',
  Line: 'Hmph.',
  Status: 'Confirmed',
  'Release Phase': 'Launch',
  Notes: 'When: completed',
}

describe('npc conversation', () => {
  it('lets the general store merchant name Quill’s stop instead of teaching artisanry', () => {
    const merchant = npc('NPC-0007')
    const save = saveAt('LOC-0024')
    const nowMs = Date.parse('2026-01-01T00:00:00.000Z')

    const conversation = npcConversation(launch, save, merchant, nowMs)
    expect(conversation.greeting).toEqual({
      kind: 'merchant',
      line: 'Keeps the General Store stocked.',
      detail: null,
    })
    expect(conversation.shopId).toBe('SHP-0001')
    expect(conversation.whereabouts?.label).toBe('Ask about Quill')
    expect(conversation.whereabouts?.line).toMatch(
      /^Last I heard, Quill was at the (Meadow|Gathering Outskirts|Kingswoods|Copper mine)\.$/,
    )
    expect(takeMerchantTip(launch, save, 'NPC-0007')).toBeNull()
  })

  it('lets Quill teach bows, quivers, and bow-hunting combat experience', () => {
    const save = saveAt('LOC-0009')
    const before = npcConversation(launch, save, npc('NPC-0002'))
    expect(before.mentor).toEqual({
      known: false,
      knownNote: 'You know how to make bows and quivers.',
      learnLabel: 'Ask about hunting',
      line: expect.stringContaining('combat experience'),
    })
    expect(before.mentor?.line).toContain('quiver')

    const learned = learnMentorProjects(launch, save, 'NPC-0002')
    expect(learned.ok).toBe(true)
    if (!learned.ok) return
    expect(learned.message).toBe('Quill shows you how to make bows and quivers.')
    expect(learned.save.unlockedNpcIds).toContain('NPC-0002')
    expect(npcConversation(launch, learned.save, npc('NPC-0002')).mentor?.known).toBe(true)
  })

  it('greets with the merchant’s own description when they have nothing to teach', () => {
    const conversation = npcConversation(launch, saveAt('LOC-0007'), npc('NPC-0009'))
    expect(conversation.greeting).toEqual({
      kind: 'merchant',
      line: 'Sells magical items and premium-priced Essence.',
      detail: null,
    })
  })

  it('pitches Rose’s quest before it is accepted, then drops the pitch', () => {
    const save = saveAt('LOC-0023')
    const conversation = npcConversation(launch, save, npc('NPC-0005'))
    expect(conversation.greeting).toEqual({
      kind: 'quest_pitch',
      questId: 'QST-0002',
      line: expect.stringContaining('alchemy shop'),
      acceptLabel: 'Start quest: Help the aspiring apothecary',
    })

    const quest = conversation.quests[0]!
    expect(quest.status).toBe('inactive')
    expect(quest.summary).toContain('out of the kitchens')

    let stocked = { ...save, gold: 1_500 }
    stocked = addItemToInventory(stocked, 'ITEM-0038', 5)
    stocked = addItemToInventory(stocked, 'ITEM-0031', 5)
    stocked = addItemToInventory(stocked, 'ITEM-0028', 5)
    stocked = addItemToInventory(stocked, 'ITEM-0042', 5)
    const accepted = npcConversation(launch, { ...stocked, quests: [
      { questId: 'QST-0002', status: 'active', progress: 0 },
    ] }, npc('NPC-0005'))
    expect(accepted.greeting).toBeNull()
    expect(accepted.quests[0]!.canTalk).toBe(true)
    expect(accepted.quests[0]!.talkLine).toContain('wild berries')
    expect(accepted.quests[0]!.ready).toBe(false)
  })

  it('names the location a completed quest opened', () => {
    let save = { ...saveAt('LOC-0023'), gold: 1_500 }
    save = addItemToInventory(save, 'ITEM-0038', 5)
    save = addItemToInventory(save, 'ITEM-0031', 5)
    save = addItemToInventory(save, 'ITEM-0028', 5)
    save = addItemToInventory(save, 'ITEM-0042', 5)
    save = {
      ...save,
      quests: [{ questId: 'QST-0002', status: 'active', progress: 0, counters: { 'talk:NPC-0005': 1 } }],
    }
    const completed = completeQuest(launch, save, 'QST-0002')
    expect(completed.ok).toBe(true)
    if (!completed.ok) return

    const conversation = npcConversation(launch, completed.save, npc('NPC-0005'))
    expect(conversation.quests[0]!.status).toBe('completed')
    expect(conversation.quests[0]!.completedNote).toBe(
      "Thank you — Rose's Apothecary is open on the Town Map.",
    )
  })

  it('describes a mentor’s projects by their skill', () => {
    const save = saveAt('LOC-0046')
    const before = npcConversation(launch, save, npc('NPC-0003'))
    expect(before.mentor).toEqual({
      known: false,
      knownNote: 'Smithing projects are unlocked.',
      learnLabel: 'Learn Smithing projects',
    })

    const learned = learnMentorProjects(launch, save, 'NPC-0003')
    expect(learned.ok).toBe(true)
    if (!learned.ok) return
    expect(learned.message).toBe('The Master Dwarf unlocks all Smithing projects.')
    expect(npcConversation(launch, learned.save, npc('NPC-0003')).mentor?.known).toBe(true)
  })

  it('lets the mining merchant say where the Master Dwarf is today', () => {
    const nowMs = Date.parse('2026-01-01T00:00:00.000Z')
    const conversation = npcConversation(launch, saveAt('LOC-0012'), npc('NPC-0008'), nowMs)
    expect(conversation.whereabouts?.label).toBe('Ask where the Master Dwarf is')
    expect(conversation.whereabouts?.line).toMatch(
      /^The Master Dwarf is at the (The Slopes|Badlands|Deep Mines) today\.$/,
    )
  })

  it("pitches the King's feast quest before it is accepted", () => {
    const conversation = npcConversation(launch, saveAt('LOC-0016'), npc('NPC-0001'))
    expect(conversation.greeting).toEqual({
      kind: 'quest_pitch',
      questId: 'QST-0001',
      line: 'My cooks have fled before the grand feast. If you know your way around a hearth, perhaps you can help.',
      acceptLabel: 'Start quest: The Grand Feast',
    })
    expect(conversation.mentor).toBeNull()
  })

  it('asks the King for details after the feast is accepted', () => {
    const save = {
      ...saveAt('LOC-0016'),
      quests: [{ questId: 'QST-0001', status: 'active' as const, progress: 0 }],
    }
    const conversation = npcConversation(launch, save, npc('NPC-0001'))
    expect(conversation.greeting).toBeNull()
    expect(conversation.quests[0]!.canTalk).toBe(true)
    expect(conversation.quests[0]!.talkLine).toContain('cooked perch')
    expect(conversation.quests[0]!.ready).toBe(false)
  })

  it('reads quest pitches and talk lines from the database', () => {
    const beggar = npcConversation(launch, saveAt('LOC-0034'), npc('NPC-0011'))
    expect(beggar.greeting).toEqual({
      kind: 'quest_pitch',
      questId: 'QST-0003',
      line: 'Please, traveler… someone took my coin purse in the night, I have nothing left.',
      acceptLabel: 'Donate 25 gold',
    })

    const shopkeeper = npcConversation(launch, saveAt('LOC-0007'), npc('NPC-0009'))
    expect(shopkeeper.quests[0]!.pitchLine).toMatch(/new apprentice/)
    expect(shopkeeper.quests[0]!.pitchLine).not.toMatch(/ten essence/)

    const guidePitch = npcConversation(launch, saveAt('LOC-0028'), npc('NPC-0013'))
    expect(guidePitch.greeting).toEqual({
      kind: 'quest_pitch',
      questId: 'QST-0004',
      line: 'Welcome to the Citadel. If you have a moment, I can help you find your feet.',
      acceptLabel: 'Start quest: Visiting the Citadel',
    })

    const archmage = npcConversation(
      launch,
      {
        ...saveAt('LOC-0007'),
        quests: [{ questId: 'QST-0005', status: 'active', progress: 0 }],
      },
      npc('NPC-0004'),
    )
    expect(archmage.quests).toEqual([])
  })

  it('hides the barracks choice until the beggar is heard', () => {
    const save = {
      ...saveAt('LOC-0034'),
      gold: 300,
      quests: [{ questId: 'QST-0003', status: 'active' as const, progress: 0 }],
    }
    const beggar = npcConversation(launch, save, npc('NPC-0011'))
    expect(beggar.greeting).toBeNull()
    expect(beggar.quests[0]!.name).toBe('Lowly Beggar')
    expect(beggar.quests[0]!.canTalk).toBe(true)
    expect(beggar.quests[0]!.talkLine).toMatch(/around town/)
    expect(beggar.quests[0]!.talkLine).not.toMatch(/barracks/)
    expect(beggar.quests[0]!.ready).toBe(false)

    const guardTooSoon = npcConversation(launch, { ...save, currentLocationId: 'LOC-0017' }, npc('NPC-0012'))
    expect(guardTooSoon.quests).toEqual([])
    const merchantTooSoon = npcConversation(launch, { ...save, currentLocationId: 'LOC-0024' }, npc('NPC-0007'))
    expect(merchantTooSoon.quests).toEqual([])

    const heard = {
      ...save,
      currentLocationId: 'LOC-0017',
      quests: [
        {
          questId: 'QST-0003',
          status: 'active' as const,
          progress: 1,
          counters: { 'talk:NPC-0011': 1 },
        },
      ],
    }
    const guard = npcConversation(launch, heard, npc('NPC-0012'))
    expect(guard.quests[0]!.canTalk).toBe(true)
    expect(guard.quests[0]!.canBribe).toBe(true)
    expect(guard.quests[0]!.canChooseCombat).toBe(true)
    expect(guard.quests[0]!.talkLine).not.toMatch(/purse/i)
    expect(guard.quests[0]!.talkLine).toMatch(/gossip/)

    const merchant = npcConversation(launch, { ...heard, currentLocationId: 'LOC-0024' }, npc('NPC-0007'))
    expect(merchant.quests[0]!.canTalk).toBe(true)
    expect(merchant.quests[0]!.talkLine).toMatch(/guards at the barracks/)

    const afterMerchant = {
      ...heard,
      quests: [
        {
          questId: 'QST-0003',
          status: 'active' as const,
          progress: 2,
          counters: { 'talk:NPC-0011': 1, 'talk:NPC-0007': 1 },
        },
      ],
    }
    const threatened = npcConversation(launch, afterMerchant, npc('NPC-0012'))
    expect(threatened.quests[0]!.canTalk).toBe(true)
    expect(threatened.quests[0]!.talkLine).toMatch(/someone talked/)
    expect(threatened.quests[0]!.talkLine).toMatch(/purse/i)
    expect(threatened.quests[0]!.canBribe).toBe(true)
    expect(threatened.quests[0]!.canChooseCombat).toBe(true)

    const afterGuard = {
      ...heard,
      quests: [
        {
          questId: 'QST-0003',
          status: 'active' as const,
          progress: 2,
          counters: { 'talk:NPC-0011': 1, 'talk:NPC-0012': 1 },
        },
      ],
    }
    const choice = npcConversation(launch, afterGuard, npc('NPC-0012'))
    expect(choice.quests[0]!.canTalk).toBe(false)
    expect(choice.quests[0]!.canBribe).toBe(true)
    expect(choice.quests[0]!.canChooseCombat).toBe(true)

    const afterBoth = {
      ...afterMerchant,
      quests: [
        {
          questId: 'QST-0003',
          status: 'active' as const,
          progress: 3,
          counters: { 'talk:NPC-0011': 1, 'talk:NPC-0007': 1, 'talk:NPC-0012': 1 },
        },
      ],
    }
    const warnedChoice = npcConversation(launch, afterBoth, npc('NPC-0012'))
    expect(warnedChoice.quests[0]!.canBribe).toBe(true)
    expect(warnedChoice.quests[0]!.canChooseCombat).toBe(true)
  })

  it('does not ask the Citadel guide or market master for talk or inspect work', () => {
    const save = {
      ...saveAt('LOC-0028'),
      quests: [{ questId: 'QST-0004', status: 'active' as const, progress: 0 }],
    }
    const guide = npcConversation(launch, save, npc('NPC-0013'))
    expect(guide.greeting).toBeNull()
    expect(guide.quests[0]!.canTalk).toBe(false)
    expect(guide.quests[0]!.canTurnIn).toBe(false)
    expect(guide.quests[0]!.progressLines.map((line) => line.label)).toEqual([
      'Visit Grand Bazaar',
      'Visit Processing District',
      'Visit Citadel Bank',
      'Visit Gathering Outskirts',
      'Visit Combat Training Grounds',
    ])

    const market = npcConversation(
      launch,
      { ...save, currentLocationId: 'LOC-0029' },
      npc('NPC-0006'),
    )
    expect(market.quests).toEqual([])
  })

  it('keeps the Archmage at Hmph until Wizard Studies is accepted', () => {
    const save = saveAt('LOC-0007')
    const before = npcConversation(launch, save, npc('NPC-0004'))
    expect(before.description).toBe('Hmph.')
    expect(before.mentor).toBeNull()
    expect(before.quests).toEqual([])
    expect(learnMentorProjects(launch, save, 'NPC-0004').ok).toBe(false)
  })

  it('reveals the Archmage essence request only after the shopkeeper is heard', () => {
    const save = {
      ...saveAt('LOC-0007'),
      quests: [{ questId: 'QST-0005', status: 'active' as const, progress: 0 }],
    }
    const shop = npcConversation(launch, save, npc('NPC-0009'))
    expect(shop.greeting?.kind).toBe('merchant')
    expect(shop.quests[0]!.canTalk).toBe(true)
    expect(shop.quests[0]!.talkLine).toMatch(/halls under the tower/)
    expect(shop.quests[0]!.talkLine).not.toMatch(/ten essence/)
    expect(shop.quests[0]!.ready).toBe(false)

    expect(npcConversation(launch, save, npc('NPC-0004')).quests).toEqual([])
    expect(npcConversation(launch, save, npc('NPC-0004')).mentor).toBeNull()

    const heard = {
      ...save,
      quests: [
        {
          questId: 'QST-0005',
          status: 'active' as const,
          progress: 1,
          counters: { 'talk:NPC-0009': 1 },
        },
      ],
    }
    const archmage = npcConversation(launch, heard, npc('NPC-0004'))
    expect(archmage.quests[0]!.canTalk).toBe(true)
    expect(archmage.quests[0]!.talkLine).toMatch(/ten essence/)
    expect(archmage.quests[0]!.ready).toBe(false)
    expect(archmage.quests[0]!.idlePrompt).toMatch(/ten essence/)
    expect(archmage.mentor).toBeNull()
  })

  it('keeps a bystander’s closing line on the panel once the quest is done', () => {
    const done = {
      ...saveAt('LOC-0017'),
      quests: [{ questId: 'QST-0003', status: 'completed' as const, progress: 3, counters: {} }],
    }
    // Without his closing line the finished quest leaves the guard's panel.
    expect(npcConversation(withoutQuestLine(GUARD_CLOSING_LINE_ID), done, npc('NPC-0012')).quests).toEqual([])

    // QDL-0031 ships that line, so the real content shows the block.
    expect(launch.QuestDialogue.find((row) => row['Dialogue ID'] === GUARD_CLOSING_LINE_ID)).toEqual(
      GUARD_CLOSING_LINE,
    )
    const guard = npcConversation(launch, done, npc('NPC-0012'))
    expect(guard.quests.map((quest) => quest.questId)).toEqual(['QST-0003'])
    const block = guard.quests[0]!
    expect(block.status).toBe('completed')
    expect(block.completedNote).toBe('Hmph.')
    expect(block.talkLine).toBe('Hmph.')
    expect(block.canTalk).toBe(false)
    expect(block.canTurnIn).toBe(false)
    expect(block.canBribe).toBe(false)
    expect(block.canChooseCombat).toBe(false)
    expect(block.canAccept).toBe(false)
    expect(block.canDonate).toBe(false)
    expect(guard.greeting).toBeNull()

    // The giver still closes the quest in their own words.
    const beggar = npcConversation(launch, { ...done, currentLocationId: 'LOC-0034' }, npc('NPC-0011'))
    expect(beggar.quests.map((quest) => quest.questId)).toEqual(['QST-0003'])
    expect(beggar.quests[0]!.status).toBe('completed')
    expect(beggar.quests[0]!.completedNote).not.toBe('Hmph.')
  })

  it('leaves a bystander’s closing line out until the quest is done', () => {
    expect(npcConversation(launch, saveAt('LOC-0017'), npc('NPC-0012')).quests).toEqual([])

    const heard = {
      ...saveAt('LOC-0017'),
      quests: [
        {
          questId: 'QST-0003',
          status: 'active' as const,
          progress: 1,
          counters: { 'talk:NPC-0011': 1 },
        },
      ],
    }
    const guard = npcConversation(launch, heard, npc('NPC-0012'))
    expect(guard.quests.map((quest) => quest.questId)).toEqual(['QST-0003'])
    expect(guard.quests[0]!.status).toBe('active')
    expect(guard.quests[0]!.talkLine).toMatch(/gossip/)
    expect(guard.quests[0]!.talkLine).not.toBe('Hmph.')
    expect(guard.quests[0]!.canBribe).toBe(true)
  })

  it('does not surface a finished quest to a bystander whose lines were all mid-quest', () => {
    const done = {
      ...saveAt('LOC-0024'),
      quests: [{ questId: 'QST-0003', status: 'completed' as const, progress: 3, counters: {} }],
    }
    // The General Store merchant spoke during Lowly Beggar but has no closing line.
    expect(npcConversation(launch, done, npc('NPC-0007')).quests).toEqual([])
  })

  it('lets Helge thank the player after Going Deeper', () => {
    const save = {
      ...saveAt('LOC-0011'),
      quests: [{ questId: 'QST-0008', status: 'completed' as const, progress: 1, counters: {} }],
    }
    const helge = npcConversation(launch, save, npc('NPC-0015'))
    expect(helge.quests[0]!.completedNote).toMatch(/rebuild our empire/)
  })

  it('does not fall back to the NPC description during a Green Thumb gap', () => {
    const fennel = npc('NPC-0014')
    let save: PlayerSave = {
      ...saveAt('LOC-0001'),
      inventory: [{ itemId: 'ITEM-0324', quantity: 1 }],
      quests: [{ questId: 'QST-0006', status: 'completed', progress: 1 }],
    }
    save = applyQuestAutoStartOnSeed(launch, save)
    const firstTalk = chooseDialogue(launch, save, 'DLG-0007', 'DNODE-0011', 'DCH-0014')
    expect(firstTalk.ok).toBe(true)
    if (!firstTalk.ok) return
    const block = npcConversation(launch, firstTalk.save, fennel).quests.find(
      (row) => row.questId === 'QST-0011',
    )!
    expect(block.talkLine).toBeNull()
    expect(questSpokenLine(block)).toBe('')
    expect(questSpokenLine(block)).not.toBe('A farmer who lives at the farm.')
    expect(fennel.Description).toBe('')
  })

  it('offers the tanner on hides in the bag', () => {
    const save = {
      ...saveAt('LOC-0025'),
      inventory: [{ itemId: 'ITEM-0378', quantity: 1 }],
    }
    const conversation = npcConversation(launch, save, npc('NPC-0018'))
    expect(conversation.name).toBe('Tanner')
    expect(conversation.tanner?.prompt).toBe('Which hides should I tan?')
    expect(conversation.tanner?.feeEach).toBe(2)
    expect(conversation.tanner?.hides).toEqual([
      { itemId: 'ITEM-0378', displayName: 'Cowhide', owned: 1, leatherEach: 3 },
    ])
    expect(npcConversation(launch, saveAt('LOC-0025'), npc('NPC-0018')).tanner?.hides).toEqual([])
  })
})
