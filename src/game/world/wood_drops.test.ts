import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('woodcutting byproduct drops', () => {
  const { launch, source } = prepareDatabase(rawDatabase)

  function action(id: string) {
    return launch.Actions.find((row) => row['Action ID'] === id)!
  }

  function primaryItem(actionId: string) {
    const tableId = action(actionId)['Reward Table ID']
    const entry = source.RewardEntries.find((row) => row['Reward Table ID'] === tableId)
    return entry?.['Reward ID / Value']
  }

  it('drops only named byproducts for willow and elder yew', () => {
    expect(primaryItem('ACN-0200')).toBe('ITEM-0386')
    expect(launch.Items.find((row) => row['Item ID'] === 'ITEM-0386')?.['Display Name']).toBe(
      'Willow Branches',
    )
    expect(action('ACN-0200')['Drop Chance']).toBe(63.75)
    expect(action('ACN-0200')['Secondary Reward Table ID']).toBe('RWT-0182')

    // Cinnamon woodcutting is Expansion-gated until it has a world pool.
    expect(launch.Actions.find((row) => row['Action ID'] === 'ACN-0201')).toBeUndefined()
    expect(launch.Items.find((row) => row['Item ID'] === 'ITEM-0387')).toBeUndefined()
    const cinnamon = source.Actions.find((row) => row['Action ID'] === 'ACN-0201')!
    expect(cinnamon['Release Phase']).toBe('Expansion')
    expect(cinnamon['Drop Chance']).toBe(63.75)

    expect(primaryItem('ACN-0051')).toBe('ITEM-0219')
    expect(launch.Items.find((row) => row['Item ID'] === 'ITEM-0219')?.['Display Name']).toBe(
      'Yew Branches',
    )
    expect(action('ACN-0051')['Drop Chance']).toBe(56.25)
  })

  it('removes generic bark from ironwood and keeps a sapling secondary', () => {
    expect(primaryItem('ACN-0202')).toBe('ITEM-0385')
    expect(action('ACN-0202')['Secondary Reward Table ID']).toBe('RWT-0183')
    const sec = source.RewardEntries.find((row) => row['Reward Table ID'] === 'RWT-0183')
    expect(sec?.['Reward ID / Value']).toBe('ITEM-0411')
  })

  it('uses yew branches in ancient crafts', () => {
    const bow = source.Projects.find((row) => row['Project ID'] === 'PRJ-0131')!
    expect(bow['Input 1 Item ID']).toBe('ITEM-0219')
    expect(launch.Items.find((row) => row['Item ID'] === 'ITEM-0219')?.['Display Name']).toBe(
      'Yew Branches',
    )
  })
})
