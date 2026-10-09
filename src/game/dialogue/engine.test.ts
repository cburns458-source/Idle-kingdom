import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { applyGameCommand } from '../server/authority'
import { chooseDialogue, dialoguesForNpc, startDialogue } from './engine'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)
const { launch: db } = prepareDatabase(rawDatabase)
const START_MS = Date.parse('2026-01-01T00:00:00.000Z')

describe('standalone dialogue engine', () => {
  it('starts and completes the citadel welcome dialogue with a grant', () => {
    let save = createNewSave(db, START_MS)
    const started = startDialogue(db, save, 'DLG-0001')
    expect(started.ok).toBe(true)
    expect(started.view?.choices).toHaveLength(2)

    const yes = chooseDialogue(db, save, 'DLG-0001', started.view!.nodeId, 'DCH-0001')
    expect(yes.ok).toBe(true)
    expect(yes.message).toMatch(/Potato/)
    save = yes.save

    const thanks = chooseDialogue(db, save, 'DLG-0001', yes.view!.nodeId, 'DCH-0003')
    expect(thanks.ok).toBe(true)
    expect(thanks.completed).toBe(true)
    expect(thanks.save.completedDialogueIds).toContain('DLG-0001')
    expect(dialoguesForNpc(db, thanks.save, 'NPC-0013')).not.toContain('DLG-0001')
  })

  it('applies dialogue_choose through the authority command', () => {
    const save = createNewSave(db, START_MS)
    const started = startDialogue(db, save, 'DLG-0001')
    const result = applyGameCommand(rawDatabase, {
      command: 'dialogue_choose',
      args: {
        dialogueId: 'DLG-0001',
        nodeId: started.view!.nodeId,
        choiceId: 'DCH-0002',
      },
      save,
      nowMs: START_MS,
      random: () => 0,
    })
    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(result.save.completedDialogueIds).toContain('DLG-0001')
  })
})
