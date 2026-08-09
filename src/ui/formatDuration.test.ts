import { describe, expect, it } from 'vitest'
import { formatDurationSeconds } from './formatDuration'

describe('formatDurationSeconds', () => {
  it('formats seconds, minutes, and hours', () => {
    expect(formatDurationSeconds(0)).toBe('0s')
    expect(formatDurationSeconds(9)).toBe('9s')
    expect(formatDurationSeconds(65)).toBe('1m 5s')
    expect(formatDurationSeconds(3723)).toBe('1h 2m 3s')
  })
})
