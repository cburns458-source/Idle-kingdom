import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { addItemToInventory } from '../activity/rewards'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { completeQuest } from '../quests/quests'
import type { PlayerSave } from '../save/types'
import { npcConversation, learnMentorProjects, takeMerchantTip } from './conversation'

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
      /^Last I heard, Quill was at the (Meadow|Old Ent Grove|Gathering Outskirts|Mountains)\.$/,
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
    const save = saveAt('LOC-0006')
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
      /^The Master Dwarf is at the (Mountains|Deep Mines) today\.$/,
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
    expect(conversation.quests[0]!.talkLine).toContain('cooked crawfish')
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

  it('lets the Citadel guide welcome visitors without listing every hall', () => {
    const save = {
      ...saveAt('LOC-0028'),
      quests: [{ questId: 'QST-0004', status: 'active' as const, progress: 0 }],
    }
    const guide = npcConversation(launch, save, npc('NPC-0013'))
    expect(guide.greeting).toBeNull()
    expect(guide.quests[0]!.canTalk).toBe(true)
    expect(guide.quests[0]!.talkLine).toMatch(/other halls/)
    expect(guide.quests[0]!.talkLine).not.toMatch(/Guild Hall/)
    expect(guide.quests[0]!.talkLine).not.toMatch(/Bounty Board/)
    expect(guide.quests[0]!.ready).toBe(false)

    const marketTooSoon = npcConversation(
      launch,
      { ...save, currentLocationId: 'LOC-0029' },
      npc('NPC-0006'),
    )
    expect(marketTooSoon.quests).toEqual([])

    const heard = {
      ...save,
      currentLocationId: 'LOC-0029',
      quests: [
        {
          questId: 'QST-0004',
          status: 'active' as const,
          progress: 1,
          counters: { 'talk:NPC-0013': 1 },
        },
      ],
    }
    const market = npcConversation(launch, heard, npc('NPC-0006'))
    expect(market.quests[0]!.canTalk).toBe(true)
    expect(market.quests[0]!.talkLine).toMatch(/no obligation to buy/)

    const guideAgain = npcConversation(launch, { ...heard, currentLocationId: 'LOC-0028' }, npc('NPC-0013'))
    expect(guideAgain.quests[0]!.progressLines.map((line) => line.label)).toEqual([
      'Talk to Market Master',
      'Visit Grand Bazaar',
      'Visit Processing District',
      'Visit Citadel Bank',
      'Visit Guild Hall',
      'Inspect the Grand Bazaar',
      'Inspect the Bounty Board',
      'Use a Processing District station',
    ])
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
    expect(archmage.quests[0]!.idlePrompt).toBe('What else do you need?')
  })

  it('lets Helge thank the player after Going Deeper', () => {
    const save = {
      ...saveAt('LOC-0011'),
      quests: [{ questId: 'QST-0008', status: 'completed' as const, progress: 1, counters: {} }],
    }
    const helge = npcConversation(launch, save, npc('NPC-0015'))
    expect(helge.quests[0]!.completedNote).toMatch(/rebuild our empire/)
  })
})
