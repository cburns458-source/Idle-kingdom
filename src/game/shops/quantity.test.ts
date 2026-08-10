import { describe, expect, it } from 'vitest'
import { parseShopQuantity } from './quantity'

describe('parseShopQuantity', () => {
  it('accepts positive whole numbers', () => {
    expect(parseShopQuantity('12')).toEqual({ ok: true, quantity: 12 })
  })

  it('rejects empty and non-integers', () => {
    expect(parseShopQuantity('').ok).toBe(false)
    expect(parseShopQuantity('1.5').ok).toBe(false)
    expect(parseShopQuantity('-2').ok).toBe(false)
    expect(parseShopQuantity('0').ok).toBe(false)
  })

  it('enforces optional max for selling', () => {
    expect(parseShopQuantity('5', 4)).toEqual({
      ok: false,
      reason: 'You can sell at most 4.',
    })
    expect(parseShopQuantity('3', 4)).toEqual({ ok: true, quantity: 3 })
  })
})
