import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { actionsForSkill } from '../skills/skillActions'
import { CodexIndex } from '../codex/codex'
import { MAIN_MAP_NODE_LAYOUT, FOREST_MAP_NODE_LAYOUT } from './mapLayout'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

const HIDDEN_ACTIONS = [
  'ACN-0183',
  'ACN-0201',
  'ACN-0203',
  'ACN-0207',
  'ACN-0209',
  'ACN-0210',
  'ACN-0212',
  'ACN-0213',
  'ACN-0217',
  'ACN-0137',
  'ACN-0214',
  'ACN-0218',
] as const

const HIDDEN_ITEMS = [
  'ITEM-0384',
  'ITEM-0387',
  'ITEM-0380',
  'ITEM-0381',
  'ITEM-0209',
  'ITEM-0382',
  'ITEM-0392',
  'ITEM-0393',
] as const

const HIDDEN_ENEMIES = ['ENM-0028', 'ENM-0032', 'ENM-0035', 'ENM-0036'] as const

describe('future-expansion content hidden from Launch', () => {
  const { launch, source } = prepareDatabase(rawDatabase)
  const codex = new CodexIndex(launch)

  it('moves unused actions, items, and enemies to Expansion', () => {
    for (const id of HIDDEN_ACTIONS) {
      expect(launch.Actions.find((row) => row['Action ID'] === id)).toBeUndefined()
      expect(source.Actions.find((row) => row['Action ID'] === id)?.['Release Phase']).toBe(
        'Expansion',
      )
    }
    for (const id of HIDDEN_ITEMS) {
      expect(launch.Items.find((row) => row['Item ID'] === id)).toBeUndefined()
      expect(source.Items.find((row) => row['Item ID'] === id)?.['Release Phase']).toBe('Expansion')
    }
    for (const id of HIDDEN_ENEMIES) {
      expect(launch.Enemies.find((row) => row['Enemy ID'] === id)).toBeUndefined()
      expect(source.Enemies.find((row) => row['Enemy ID'] === id)?.['Release Phase']).toBe(
        'Expansion',
      )
    }
    expect(launch.Enemies.find((row) => row['Enemy ID'] === 'ENM-0024')?.['Display Name']).toBe(
      'Squidling',
    )
  })

  it('keeps them out of Codex and skill menus', () => {
    for (const id of HIDDEN_ACTIONS) {
      expect(codex.action(id)).toBeUndefined()
    }
    for (const id of HIDDEN_ITEMS) {
      expect(codex.item(id)).toBeUndefined()
    }
    for (const id of HIDDEN_ENEMIES) {
      expect(codex.enemy(id)).toBeUndefined()
    }
    expect(codex.enemy('ENM-0024')?.displayName).toBe('Squidling')

    const wood = actionsForSkill(launch, 'SKL-0006').map((row) => row.id)
    expect(wood).not.toContain('ACN-0201')
    expect(wood).not.toContain('ACN-0203')
    const fish = actionsForSkill(launch, 'SKL-0003').map((row) => row.id)
    expect(fish).not.toContain('ACN-0217')
    const cook = actionsForSkill(launch, 'SKL-0007').map((row) => row.id)
    expect(cook).not.toContain('ACN-0218')
    expect(cook).not.toContain('ACN-0183')
  })

  it('nudges Citadel left and Small Clearing right', () => {
    expect(MAIN_MAP_NODE_LAYOUT['LOC-0027']).toEqual({ x: 38, y: 42 })
    expect(FOREST_MAP_NODE_LAYOUT['LOC-0050']).toEqual({ x: 62, y: 58 })
    const mapNodes = (rawDatabase as { MapNodes: Array<Record<string, unknown>> }).MapNodes
    const citadel = mapNodes.find((row) => row['Map Node ID'] === 'MN-0015')!
    const clearing = mapNodes.find((row) => row['Map Node ID'] === 'MN-0055')!
    expect(citadel.X).toBe(38)
    expect(clearing.X).toBe(62)
  })
})
