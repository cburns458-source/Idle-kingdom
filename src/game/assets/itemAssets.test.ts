import { describe, expect, it } from 'vitest'
import { itemAssetPath } from './itemAssets'
import type { ItemRow } from '../data/types'

function item(partial: {
  'Item ID': string
  'Display Name': string
  'Internal Key'?: string
  Category?: string | null
  Subtype?: string | null
}): ItemRow {
  return {
    'Item ID': partial['Item ID'],
    'Internal Key': partial['Internal Key'] ?? '',
    'Display Name': partial['Display Name'],
    Category: partial.Category ?? null,
    Subtype: partial.Subtype ?? null,
    Status: 'Confirmed',
    'Release Phase': 'Launch',
    'Associated Skill ID': null,
    'Equipment Slot ID': null,
    'Base Sell Value': null,
    'Icon Asset Key': null,
    Description: null,
    'Functional / Source Tags': null,
    Notes: null,
  }
}

describe('itemAssetPath', () => {
  it('uses ID overrides for distinct Launch icons', () => {
    expect(itemAssetPath('ITEM-0028')).toContain('item_berries.png')
    expect(itemAssetPath('ITEM-0046')).toContain('item_dragon_scale.png')
    expect(itemAssetPath('ITEM-0288')).toContain('item_insignia.png')
    expect(itemAssetPath('ITEM-0169')).toContain('item_backpack.png')
    expect(itemAssetPath('ITEM-0123')).toContain('item_hammer.png')
    expect(itemAssetPath('ITEM-0103')).toContain('item_fishing_tool.png')
  })

  it('maps platelegs to legs instead of chest', () => {
    const path = itemAssetPath(
      item({
        'Item ID': 'ITEM-0157',
        'Display Name': 'Iron Platelegs',
        'Internal Key': 'iron_platelegs',
        Category: 'Armor',
        Subtype: 'Platelegs',
      }),
    )
    expect(path).toContain('item_legs.png')
  })

  it('does not treat explorer as ore', () => {
    const path = itemAssetPath(
      item({
        'Item ID': 'ITEM-0999',
        'Display Name': "Explorer's Pack",
        'Internal Key': 'explorer_s_pack',
        Category: 'Armor',
        Subtype: 'Specialist back item',
      }),
    )
    expect(path).toContain('item_backpack.png')
  })

  it('prefers jewelry shapes over gem color names', () => {
    expect(
      itemAssetPath(
        item({
          'Item ID': 'ITEM-0174',
          'Display Name': 'Sapphire Necklace',
          'Internal Key': 'sapphire_necklace',
          Category: 'Jewelry',
          Subtype: 'Necklace',
        }),
      ),
    ).toContain('item_necklace.png')
  })
})
