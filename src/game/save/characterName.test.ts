import { describe, expect, it } from 'vitest'
import { isValidCharacterName, normalizeCharacterName } from './characterName'

describe('character name', () => {
  it('trims and collapses whitespace', () => {
    expect(normalizeCharacterName('  Ada   Vale  ')).toBe('Ada Vale')
  })

  it('rejects empty names', () => {
    expect(isValidCharacterName('   ')).toBe(false)
    expect(normalizeCharacterName('')).toBeNull()
  })
})
