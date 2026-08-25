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
      /^Last I heard, Quill was at the (Meadow|Ancient Forest|Gathering Outskirts|Mountains)\.$/,
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
    expect(quest.goldRequired).toBe(1_000)

    let stocked = { ...save, gold: 1_500 }
    stocked = addItemToInventory(stocked, 'ITEM-0038', 5)
    stocked = addItemToInventory(stocked, 'ITEM-0031', 5)
    const accepted = npcConversation(launch, { ...stocked, quests: [
      { questId: 'QST-0002', status: 'active', progress: 0 },
    ] }, npc('NPC-0005'))
    expect(accepted.greeting).toBeNull()
    expect(accepted.quests[0]!.ready).toBe(true)
  })

  it('names the location a completed quest opened', () => {
    let save = { ...saveAt('LOC-0023'), gold: 1_500 }
    save = addItemToInventory(save, 'ITEM-0038', 5)
    save = addItemToInventory(save, 'ITEM-0031', 5)
    save = { ...save, quests: [{ questId: 'QST-0002', status: 'active', progress: 0 }] }
    const completed = completeQuest(launch, save, 'QST-0002')
    expect(completed.ok).toBe(true)
    if (!completed.ok) return

    const conversation = npcConversation(launch, completed.save, npc('NPC-0005'))
    expect(conversation.quests[0]!.status).toBe('completed')
    expect(conversation.quests[0]!.completedNote).toBe(
      "Completed — Rose's Apothecary is open on the Town Map.",
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
      /^The Master Dwarf is at the (Mountains|Deep Mines|Abandoned Mineshaft) today\.$/,
    )
  })

  it('leaves plain NPCs without a greeting or mentor block', () => {
    const conversation = npcConversation(launch, saveAt('LOC-0016'), npc('NPC-0001'))
    expect(conversation.greeting).toBeNull()
    expect(conversation.mentor).toBeNull()
    expect(conversation.quests.map((quest) => quest.acceptLabel)).toEqual(['Accept quest'])
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
    expect(shopkeeper.quests[0]!.pitchLine).toContain('mine below the tower')

    const archmage = npcConversation(
      launch,
      {
        ...saveAt('LOC-0007'),
        quests: [{ questId: 'QST-0005', status: 'active', progress: 0 }],
      },
      npc('NPC-0004'),
    )
    expect(archmage.quests[0]!.talkLine).toBe('Well done.')
    expect(archmage.quests[0]!.idlePrompt).toBe('What else do you need?')
  })
})
