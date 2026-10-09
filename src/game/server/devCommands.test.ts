import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { applyDevCommand, parseDevCommandLine } from './devCommands'
import { getSkillProgress } from '../activity/xp'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)
const { launch: db } = prepareDatabase(rawDatabase)
const START_MS = Date.parse('2026-01-01T00:00:00.000Z')

describe('developer commands', () => {
  it('parses a slash line', () => {
    expect(parseDevCommandLine('/give copper ore 5')).toEqual({
      command: 'give',
      tokens: ['copper', 'ore', '5'],
    })
  })

  it('gives an item by display name', () => {
    const save = createNewSave(db, START_MS)
    const result = applyDevCommand(db, save, 'give', ['potato', '3'], START_MS)
    expect(result.ok).toBe(true)
    expect(result.message).toMatch(/Potato/)
    expect(result.save.inventory.some((stack) => stack.itemId === 'ITEM-0025' && stack.quantity >= 3)).toBe(
      true,
    )
  })

  it('sets a skill level', () => {
    const save = createNewSave(db, START_MS)
    const result = applyDevCommand(db, save, 'setlevel', ['might', '20'], START_MS)
    expect(result.ok).toBe(true)
    expect(getSkillProgress(result.save, 'SKL-0001').level).toBe(20)
  })

  it('requires confirm for resetskills', () => {
    const save = createNewSave(db, START_MS)
    const refused = applyDevCommand(db, save, 'resetskills', [], START_MS)
    expect(refused.ok).toBe(false)
    const ok = applyDevCommand(db, save, 'resetskills', ['confirm'], START_MS)
    expect(ok.ok).toBe(true)
  })
})
