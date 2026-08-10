import { describe, expect, it } from 'vitest'
import { consolidateAfkMessages, exampleAfkSummary } from './AfkSummaryPanel'

describe('consolidateAfkMessages', () => {
  it('merges repeated craft lines into one total', () => {
    expect(
      consolidateAfkMessages([
        'Won 2 fights while away.',
        'Crafted 1 Baked Potato (+120 XP)',
        'Crafted 1 Baked Potato (+120 XP)',
        'Defeated by Cow while away.',
      ]),
    ).toEqual([
      'Won 2 fights while away.',
      'Crafted 2 Baked Potato (+240 XP)',
      'Defeated by Cow while away.',
    ])
  })

  it('keeps different crafted items on separate lines', () => {
    expect(
      consolidateAfkMessages([
        'Crafted 1 Baked Potato (+120 XP)',
        'Crafted 2 Copper Bar (+50 XP)',
        'Crafted 1 Baked Potato (+120 XP)',
      ]),
    ).toEqual([
      'Crafted 2 Baked Potato (+240 XP)',
      'Crafted 2 Copper Bar (+50 XP)',
    ])
  })
})

describe('exampleAfkSummary', () => {
  it('shows consolidated craft totals', () => {
    expect(exampleAfkSummary().messages).toContain('Crafted 2 Baked Potato (+240 XP)')
    expect(exampleAfkSummary().messages).not.toContain('Crafted 1 Baked Potato (+120 XP)')
  })
})
