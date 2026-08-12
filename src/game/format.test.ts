import { describe, expect, it } from 'vitest'
import { formatNumber } from './format'

describe('formatNumber', () => {
  it('shows small integers as-is', () => {
    expect(formatNumber(0)).toBe('0')
    expect(formatNumber(42)).toBe('42')
  })

  it('shows one decimal for small fractions', () => {
    expect(formatNumber(12.34)).toBe('12.3')
  })

  it('compacts thousands and millions', () => {
    expect(formatNumber(1500)).toBe('1.50K')
    expect(formatNumber(2_500_000)).toBe('2.50M')
    expect(formatNumber(3_000_000_000)).toBe('3.00B')
  })
})
