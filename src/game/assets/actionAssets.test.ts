import { describe, expect, it } from 'vitest'
import { ACTION_ASSET_PATHS, actionAssetPath } from './actionAssets'

describe('actionAssets', () => {
  it('maps every gathering action id to a versioned path', () => {
    expect(Object.keys(ACTION_ASSET_PATHS).length).toBe(45)
    const path = actionAssetPath('ACN-0035')
    expect(path).toContain('/assets/actions/acn_harvest_potato.webp')
    expect(path).toContain('v=')
  })

  it('falls back for unknown action ids', () => {
    expect(actionAssetPath('ACN-MISSING')).toContain('acn_harvest_potato.webp')
  })
})
