import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { npcConversation } from './conversation'
import { npcsAtLocation } from './knowledge'
import {
  MASTER_DWARF_ID,
  MASTER_DWARF_ROUTE,
  QUILL_ID,
  QUILL_ROUTE,
  masterDwarfLocationId,
  quillLocationId,
  roamingDayKey,
  roamingLocationFor,
} from './roaming'
import { createNewSave } from '../save/saveStore'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)
const { launch } = prepareDatabase(rawDatabase)

const DAY = Date.parse('2026-01-01T00:00:00.000Z')
const SAME_DAY_EVENING = Date.parse('2026-01-01T23:59:59.999Z')
const NEXT_DAY = Date.parse('2026-01-02T00:00:00.000Z')

describe('master dwarf roam', () => {
  it('shares one stop for the UTC day', () => {
    const morning = masterDwarfLocationId(DAY)
    expect(MASTER_DWARF_ROUTE).toContain(morning)
    expect(masterDwarfLocationId(SAME_DAY_EVENING)).toBe(morning)
    expect(roamingLocationFor(MASTER_DWARF_ID, MASTER_DWARF_ROUTE, DAY)).toBe(morning)
    expect(roamingDayKey(DAY)).toBe('2026-01-01')
    expect(roamingDayKey(SAME_DAY_EVENING)).toBe('2026-01-01')
    expect(roamingDayKey(NEXT_DAY)).toBe('2026-01-02')
  })

  it('rolls each UTC day independently and can stay put', () => {
    const stops = Array.from({ length: 400 }, (_, index) =>
      masterDwarfLocationId(DAY + index * 86_400_000),
    )
    expect(new Set(stops).size).toBe(MASTER_DWARF_ROUTE.length)
    expect(stops.some((stop, index) => index > 0 && stop === stops[index - 1])).toBe(true)
  })

  it('lists the dwarf only at today’s stop', () => {
    const today = masterDwarfLocationId(DAY)
    for (const locationId of MASTER_DWARF_ROUTE) {
      const ids = npcsAtLocation(launch, locationId, DAY).map((npc) => npc['NPC ID'])
      if (locationId === today) {
        expect(ids).toContain(MASTER_DWARF_ID)
      } else {
        expect(ids).not.toContain(MASTER_DWARF_ID)
      }
    }
  })

  it('lets the mining merchant name today’s stop', () => {
    const merchant = launch.NPCs.find((npc) => npc['NPC ID'] === 'NPC-0008')
    if (!merchant) throw new Error('missing NPC-0008')
    const save = createNewSave(launch)
    const conversation = npcConversation(launch, save, merchant, DAY)
    const place = launch.Locations.find(
      (row) => row['Location ID'] === masterDwarfLocationId(DAY),
    )?.['Display Name']
    expect(conversation.whereabouts).toEqual({
      label: 'Ask where the Master Dwarf is',
      line: `The Master Dwarf is at the ${place} today.`,
    })
  })

  it('shares one Quill stop for the UTC day', () => {
    const morning = quillLocationId(DAY)
    expect(QUILL_ROUTE).toContain(morning)
    expect(quillLocationId(SAME_DAY_EVENING)).toBe(morning)
    expect(roamingLocationFor(QUILL_ID, QUILL_ROUTE, DAY)).toBe(morning)
  })

  it('lists Quill only at today’s stop', () => {
    const today = quillLocationId(DAY)
    for (const locationId of QUILL_ROUTE) {
      const ids = npcsAtLocation(launch, locationId, DAY).map((npc) => npc['NPC ID'])
      if (locationId === today) {
        expect(ids).toContain(QUILL_ID)
      } else {
        expect(ids).not.toContain(QUILL_ID)
      }
    }
  })

  it('lets the general store merchant name Quill’s stop', () => {
    const merchant = launch.NPCs.find((npc) => npc['NPC ID'] === 'NPC-0007')
    if (!merchant) throw new Error('missing NPC-0007')
    const save = createNewSave(launch)
    const conversation = npcConversation(launch, save, merchant, DAY)
    const place = launch.Locations.find(
      (row) => row['Location ID'] === quillLocationId(DAY),
    )?.['Display Name']
    expect(conversation.whereabouts).toEqual({
      label: 'Ask about Quill',
      line: `Last I heard, Quill was at the ${place}.`,
    })
  })
})
