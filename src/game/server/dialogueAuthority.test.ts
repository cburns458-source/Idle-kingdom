import { describe, expect, it } from 'vitest'
import { DIALOGUE_PATCH, patchedDatabase } from '../../parity/scenarios/dialogue'
import { addItemToInventory } from '../activity/rewards'
import { prepareDatabase } from '../data/loadDatabase'
import { getQuestProgress } from '../quests/quests'
import { createNewSave } from '../save/saveStore'
import type { PlayerSave } from '../save/types'
import { applyGameCommand, type GameCommandResult } from './authority'
import { applyDevCommand } from './devCommands'
import { bagCount } from '../dialogue/stepProgress'

const rawDatabase = patchedDatabase(DIALOGUE_PATCH)
const { launch: db } = prepareDatabase(rawDatabase)
const START_MS = Date.parse('2026-01-01T00:00:00.000Z')
const POTATO = 'ITEM-0058'
const PERCH = 'ITEM-0059'

function freshSave(): PlayerSave {
  return { ...createNewSave(db, START_MS), currentLocationId: 'LOC-0002' }
}

function withItem(save: PlayerSave, itemId: string, quantity: number): PlayerSave {
  return addItemToInventory(
    { ...save, inventory: save.inventory.filter((stack) => stack.itemId !== itemId) },
    itemId,
    quantity,
  )
}

function command(save: PlayerSave, name: string, args: Record<string, unknown> = {}): GameCommandResult {
  return applyGameCommand(rawDatabase, { command: name, args, save, nowMs: START_MS, random: () => 0 })
}

function king(save: PlayerSave, choiceId: string): GameCommandResult {
  return command(save, 'dialogue_choose', { dialogueId: 'DLG-9001', nodeId: 'DNODE-9001', choiceId })
}

function saveOf(result: GameCommandResult): PlayerSave {
  if (!result.ok) throw new Error(result.reason)
  return result.save
}

/**
 * The `player_saves` compare-and-swap in `supabase/functions/game/index.ts`:
 * a write lands only when the version it read is still current.
 */
class CasRow {
  payload: PlayerSave
  version = 1

  constructor(payload: PlayerSave) {
    this.payload = payload
  }

  read(): { payload: PlayerSave; version: number } {
    return { payload: JSON.parse(JSON.stringify(this.payload)), version: this.version }
  }

  write(expectedVersion: number, payload: PlayerSave): boolean {
    if (expectedVersion !== this.version) return false
    this.payload = payload
    this.version += 1
    return true
  }
}

/** One hosted request: read, apply, CAS write, and retry on the fresh row after a conflict. */
function hostedRequest(
  row: CasRow,
  read: { payload: PlayerSave; version: number },
  choiceId: string,
): { ok: boolean; retried: boolean; reason?: string } {
  let current = read
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const result = king(current.payload, choiceId)
    if (!result.ok) return { ok: false, retried: attempt > 0, reason: result.reason }
    if (row.write(current.version, result.save)) return { ok: true, retried: attempt > 0 }
    current = row.read()
  }
  return { ok: false, retried: true, reason: 'gave up' }
}

function startedFeast(): PlayerSave {
  return saveOf(king(freshSave(), 'DCH-9001'))
}

describe('dialogue commands on the server', () => {
  it('two hand-ins on the same version never double count (group 4)', () => {
    const row = new CasRow(withItem(startedFeast(), POTATO, 6))
    const first = row.read()
    const second = row.read()

    expect(hostedRequest(row, first, 'DCH-9006')).toEqual({ ok: true, retried: false })
    const loser = hostedRequest(row, second, 'DCH-9006')
    expect(loser.ok).toBe(false)
    expect(loser.retried).toBe(true)
    expect(loser.reason).toBe('You have nothing they still need.')

    const counters = getQuestProgress(row.payload, 'QST-9001').counters ?? {}
    expect(counters[`handIn:QSTP-9002:${POTATO}`]).toBe(6)
    expect(bagCount(row.payload, POTATO)).toBe(0)
    expect(row.version).toBe(2)
  })

  it('a concurrent over-delivery takes only what is still needed once (group 4)', () => {
    const row = new CasRow(withItem(withItem(startedFeast(), POTATO, 15), PERCH, 10))
    const first = row.read()
    const second = row.read()

    expect(hostedRequest(row, first, 'DCH-9006').ok).toBe(true)
    const loser = hostedRequest(row, second, 'DCH-9006')
    expect(loser).toMatchObject({ ok: false, retried: true, reason: 'That step is not current.' })

    const counters = getQuestProgress(row.payload, 'QST-9001').counters ?? {}
    expect(counters[`handIn:QSTP-9002:${POTATO}`]).toBe(10)
    expect(counters[`handIn:QSTP-9002:${PERCH}`]).toBe(10)
    expect(counters['step:QSTP-9002']).toBe(1)
    expect(bagCount(row.payload, POTATO)).toBe(5)
    expect(bagCount(row.payload, PERCH)).toBe(0)
  })

  it('rejects the normal quest_abandon (group 9)', () => {
    const result = command(startedFeast(), 'quest_abandon', { questId: 'QST-9001' })
    expect(result).toEqual({ ok: false, reason: 'Quests cannot be abandoned.' })
  })

  it('cheat abandon deletes held items and resets only that quest’s gifts (group 9)', () => {
    let save = withItem(startedFeast(), POTATO, 6)
    save = saveOf(king(save, 'DCH-9002'))
    save = { ...save, dialogueFlags: ['gift:QST-9001:feast', 'gift:QST-9002:spud', 'met-fennel'] }

    expect(applyDevCommand(db, save, 'abandonquest', ['QST-9001'], START_MS).ok).toBe(false)
    const abandoned = applyDevCommand(db, save, 'abandonquest', ['qst-9001', 'confirm'], START_MS)
    expect(abandoned.ok).toBe(true)
    expect(abandoned.message).toBe('Abandoned Test Feast. 6 handed-in items deleted.')
    expect(abandoned.save.quests.some((row) => row.questId === 'QST-9001')).toBe(false)
    expect(bagCount(abandoned.save, POTATO)).toBe(0)
    expect(abandoned.save.dialogueFlags).toEqual(['gift:QST-9002:spud', 'met-fennel'])

    const again = applyDevCommand(db, abandoned.save, 'abandonquest', ['QST-9001', 'confirm'], START_MS)
    expect(again).toMatchObject({ ok: false, reason: 'That quest is not active.' })
  })

  it('dialogue_view returns the view and leaves the save alone', () => {
    const save = withItem(startedFeast(), POTATO, 3)
    const baseline = command(save, 'set_meta')
    const viewed = command(save, 'dialogue_view', { dialogueId: 'DLG-9001' })
    expect(viewed.ok).toBe(true)
    if (!viewed.ok || !baseline.ok) return
    expect(viewed.save).toEqual(baseline.save)
    expect(viewed.view?.nodeId).toBe('DNODE-9001')
    expect(viewed.view?.stepProgress[0]?.items[0]).toEqual({
      itemId: POTATO,
      have: 3,
      handedIn: 0,
      need: 10,
      mode: 'handIn',
    })
    const node = command(save, 'dialogue_view', { dialogueId: 'DLG-9001', nodeId: 'DNODE-9001' })
    expect(node.ok && node.view?.choices.map((choice) => choice.choiceId)).toEqual([
      'DCH-9001',
      'DCH-9002',
      'DCH-9003',
      'DCH-9005',
      'DCH-9006',
    ])
  })
})
