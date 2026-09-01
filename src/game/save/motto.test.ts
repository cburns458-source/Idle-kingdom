import { describe, expect, it } from 'vitest'
import { isValidMotto, normalizeMotto } from './motto'
import { MOTTO_MAX_LENGTH } from './types'

describe('normalizeMotto', () => {
  it('trims, collapses whitespace, and returns null when empty', () => {
    expect(normalizeMotto('')).toBeNull()
    expect(normalizeMotto('   ')).toBeNull()
    expect(normalizeMotto('  hello   world  ')).toBe('hello world')
  })

  it('caps length at MOTTO_MAX_LENGTH', () => {
    const long = 'x'.repeat(MOTTO_MAX_LENGTH + 20)
    expect(normalizeMotto(long)?.length).toBe(MOTTO_MAX_LENGTH)
  })

  it('accepts empty as valid and rejects over-cap', () => {
    expect(isValidMotto('')).toBe(true)
    expect(isValidMotto('ok')).toBe(true)
    expect(isValidMotto('x'.repeat(MOTTO_MAX_LENGTH + 1))).toBe(false)
  })
})
