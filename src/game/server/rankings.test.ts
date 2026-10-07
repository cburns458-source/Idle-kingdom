import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { equipStackToSlot, WEAPON_TOOL_SLOT_ID } from '../equipment/loadout'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import {
  overlayPublishedPvpSnapshot,
  pvpSnapshotRowForSave,
  rankingBoardRowsFor,
  rankingProfilePatch,
} from './rankings'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

const START_MS = Date.parse('2026-01-01T00:00:00.000Z')
const NOW_ISO = new Date(START_MS).toISOString()

describe('phase 3 rankings', () => {
  it('builds board rows and public gear from the hosted save', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = { ...createNewSave(launch, START_MS), gold: 40, characterName: 'Hero' }
    const rows = rankingBoardRowsFor(launch, save, 'usr_1', NOW_ISO)
    expect(rows.some((row) => row.board_key === 'gold' && row.value === 40)).toBe(true)
    expect(rows.every((row) => row.user_id === 'usr_1')).toBe(true)
    const patch = rankingProfilePatch(save)
    expect(Array.isArray(patch.equipment_json)).toBe(true)
    expect(patch.motto).toBeNull()
  })

  it('strips food from a published PvP loadout', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const save = equipStackToSlot(createNewSave(launch, START_MS), WEAPON_TOOL_SLOT_ID, 'ITEM-0128', 1)
    const row = pvpSnapshotRowForSave({
      userId: 'usr_1',
      username: 'Rival',
      save,
      nowIso: NOW_ISO,
    })
    expect(row.username).toBe('Rival')
    expect(row.payload.equipment.slots[WEAPON_TOOL_SLOT_ID]?.itemId).toBe('ITEM-0128')
  })

  it('overlays live combat stats onto an existing snapshot without swapping gear', () => {
    const { launch } = prepareDatabase(rawDatabase)
    const snapshot = equipStackToSlot(
      createNewSave(launch, START_MS),
      WEAPON_TOOL_SLOT_ID,
      'ITEM-0128',
      1,
    )
    const live = {
      ...createNewSave(launch, START_MS),
      raceId: 'RACE-0004',
      skills: snapshot.skills.map((skill) =>
        skill.skillId === 'SKL-0001' || skill.skillId === 'SKL-0016'
          ? { ...skill, level: 13 }
          : skill,
      ),
    }
    const merged = overlayPublishedPvpSnapshot(snapshot, live, START_MS)
    expect(merged?.raceId).toBe('RACE-0004')
    expect(merged?.equipment.slots[WEAPON_TOOL_SLOT_ID]?.itemId).toBe('ITEM-0128')
  })
})
