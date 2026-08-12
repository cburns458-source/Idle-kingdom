import { describe, expect, it } from 'vitest'
import { canonicalEquals, canonicalJson, canonicalNumber } from './canonicalJson'

describe('canonicalJson', () => {
  it('sorts object keys so encoding is order independent', () => {
    expect(canonicalJson({ b: 1, a: 2 })).toBe('{"a":2,"b":1}')
    expect(canonicalEquals({ b: 1, a: 2 }, { a: 2, b: 1 })).toBe(true)
  })

  it('normalizes integral numbers and negative zero', () => {
    expect(canonicalNumber(1)).toBe('1')
    expect(canonicalNumber(1.0)).toBe('1')
    expect(canonicalNumber(-0)).toBe('0')
    expect(canonicalNumber(1.0000001)).toBe('1.0000001')
  })

  it('drops undefined fields to match what JSON.stringify writes to disk', () => {
    expect(canonicalJson({ a: 1, b: undefined })).toBe('{"a":1}')
    expect(canonicalJson({ a: 1, b: null })).toBe('{"a":1,"b":null}')
  })

  it('quotes non-finite numbers, which JSON has no literals for', () => {
    expect(canonicalJson(Number.POSITIVE_INFINITY)).toBe('"Infinity"')
    expect(canonicalJson(Number.NEGATIVE_INFINITY)).toBe('"-Infinity"')
    expect(canonicalJson(Number.NaN)).toBe('"NaN"')
  })

  it('rejects values that cannot round-trip', () => {
    expect(() => canonicalJson(undefined)).toThrow(/undefined/)
    const cyclic: Record<string, unknown> = {}
    cyclic.self = cyclic
    expect(() => canonicalJson(cyclic)).toThrow(/cyclic/)
  })
})
