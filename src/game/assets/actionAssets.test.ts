import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { ACTION_ASSET_PATHS, actionAssetPath } from './actionAssets'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

describe('actionAssets', () => {
  it('maps every gathering action id to a versioned path', () => {
    const { launch } = prepareDatabase(rawDatabase)
    for (const action of launch.Actions) {
      if (action.Category !== 'Gathering' || !action['Action ID']) continue
      expect(
        ACTION_ASSET_PATHS[action['Action ID']],
        `${action['Action ID']} (${action['Display Name']})`,
      ).toBeDefined()
    }
    const path = actionAssetPath('ACN-0035')
    expect(path).toContain('/assets/actions/acn_harvest_potato.webp')
    expect(path).toContain('v=')
  })

  it('falls back for unknown action ids', () => {
    expect(actionAssetPath('ACN-MISSING')).toContain('acn_harvest_potato.webp')
  })
})
