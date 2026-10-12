import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { addItemToInventory } from '../activity/rewards'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { applyGameCommand } from '../server/authority'
import { confirmShopOffer, isValidOfferQuantity, type ShopOfferLine } from './transactions'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)
const { launch } = prepareDatabase(rawDatabase)
const NOW = Date.parse('2026-01-01T00:00:00.000Z')
const REASON = 'Offer quantities must be at least 1.'

function shopSave() {
  let save = createNewSave(launch, NOW)
  save = { ...save, gold: 1000, currentLocationId: 'LOC-0024' }
  return addItemToInventory(save, 'ITEM-0025', 1)
}

const invalid: Array<[string, unknown]> = [
  ['string', '1'],
  ['null', null],
  ['undefined', undefined],
  ['NaN', Number.NaN],
  ['Infinity', Number.POSITIVE_INFINITY],
  ['-Infinity', Number.NEGATIVE_INFINITY],
  ['fraction', 1.5],
  ['small fraction', 0.5],
  ['zero', 0],
  ['negative', -1],
  ['above MAX_SAFE_INTEGER', Number.MAX_SAFE_INTEGER + 1],
]

describe('shop_confirm quantity validation', () => {
  for (const [label, quantity] of invalid) {
    for (const side of ['buys', 'sells'] as const) {
      it(`rejects ${label} on ${side} and changes nothing`, () => {
        const save = shopSave()
        const before = JSON.stringify(save)
        const itemId = side === 'buys' ? 'ITEM-0102' : 'ITEM-0025'
        const line = { itemId, quantity } as unknown as ShopOfferLine
        const offer = side === 'buys' ? { buys: [line], sells: [] } : { buys: [], sells: [line] }
        const result = confirmShopOffer(launch, save, 'SHP-0001', offer, NOW)
        expect(result).toEqual({ ok: false, reason: REASON })
        expect(JSON.stringify(save)).toBe(before)
        expect(isValidOfferQuantity(quantity)).toBe(false)
      })
    }
  }

  it('rejects a bad line even when another line is valid', () => {
    const result = confirmShopOffer(
      launch,
      shopSave(),
      'SHP-0001',
      { buys: [{ itemId: 'ITEM-0102', quantity: 1 }], sells: [{ itemId: 'ITEM-0025', quantity: -5 }] },
      NOW,
    )
    expect(result).toEqual({ ok: false, reason: REASON })
  })

  it('accepts MAX_SAFE_INTEGER as a quantity shape', () => {
    expect(isValidOfferQuantity(Number.MAX_SAFE_INTEGER)).toBe(true)
    expect(isValidOfferQuantity(1)).toBe(true)
  })

  it('accepts a valid whole-number buy', () => {
    const save = shopSave()
    const result = confirmShopOffer(
      launch,
      save,
      'SHP-0001',
      { buys: [{ itemId: 'ITEM-0102', quantity: 1 }], sells: [] },
      NOW,
    )
    expect(result.ok).toBe(true)
    if (!result.ok) return
    expect(result.save.inventory.some((stack) => stack.itemId === 'ITEM-0102')).toBe(true)
    expect(result.save.gold).toBeLessThan(save.gold)
  })

  it('rejects through the shop_confirm server command with the same reason', () => {
    const save = shopSave()
    for (const quantity of ['3', 2.5, 0, -1, Number.MAX_SAFE_INTEGER + 1]) {
      const result = applyGameCommand(rawDatabase, {
        command: 'shop_confirm',
        args: { shopId: 'SHP-0001', offer: { buys: [], sells: [{ itemId: 'ITEM-0025', quantity }] } },
        save,
        nowMs: NOW,
        random: () => 0,
      })
      expect(result.ok).toBe(false)
      if (result.ok) continue
      expect(result.reason).toBe(REASON)
    }
  })
})
