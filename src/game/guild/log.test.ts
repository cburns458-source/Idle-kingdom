import { describe, expect, it } from 'vitest'
import { mergeDonationItems, mergeGuildLogDonation, type GuildLogEntry } from './log'

function donation(overrides: Partial<GuildLogEntry> = {}): GuildLogEntry {
  return {
    id: '1',
    guildId: 'g',
    kind: 'donation',
    createdAt: 't',
    actorUserId: 'u1',
    actorUsername: 'Ada',
    role: null,
    targetUserId: null,
    targetUsername: null,
    tierId: null,
    message: '',
    gold: 50,
    items: [{ itemId: 'ITEM-0002', quantity: 10 }],
    ...overrides,
  }
}

describe('guild log donation merge', () => {
  it('merges back-to-back donations from one player into one line', () => {
    const first = donation()
    const merged = mergeGuildLogDonation(first, {
      ...first,
      gold: 25,
      items: [{ itemId: 'ITEM-0002', quantity: 5 }],
    })
    expect(merged.merged).toBe(true)
    if (!merged.merged) return
    expect(merged.entry.id).toBe('1')
    expect(merged.entry.gold).toBe(75)
    expect(merged.entry.items).toEqual([{ itemId: 'ITEM-0002', quantity: 15 }])
  })

  it('adds a new item onto the same line when the second donation is a different stack', () => {
    const first = donation()
    const merged = mergeGuildLogDonation(first, {
      ...first,
      gold: 0,
      items: [{ itemId: 'ITEM-0015', quantity: 3 }],
    })
    expect(merged.merged).toBe(true)
    if (!merged.merged) return
    expect(merged.entry.gold).toBe(50)
    expect(merged.entry.items).toEqual([
      { itemId: 'ITEM-0002', quantity: 10 },
      { itemId: 'ITEM-0015', quantity: 3 },
    ])
  })

  it('does not merge when another kind of event is the newest line', () => {
    const newest = donation({ kind: 'tier_complete', gold: 0, items: [] })
    const incoming = donation({ gold: 10, items: [] })
    expect(mergeGuildLogDonation(newest, incoming)).toEqual({ merged: false })
  })

  it('does not merge donations from two different players', () => {
    const first = donation()
    expect(mergeGuildLogDonation(first, { ...first, actorUserId: 'u2', gold: 1, items: [] })).toEqual(
      { merged: false },
    )
  })

  it('does not merge when the actor is missing', () => {
    const first = donation({ actorUserId: null })
    expect(mergeGuildLogDonation(first, { ...first, gold: 1, items: [] })).toEqual({ merged: false })
  })

  it('keeps the incoming message when the second donation has one', () => {
    const first = donation({ message: 'first' })
    const merged = mergeGuildLogDonation(first, { ...first, gold: 1, items: [], message: 'again' })
    expect(merged.merged).toBe(true)
    if (!merged.merged) return
    expect(merged.entry.message).toBe('again')
  })

  it('mergeDonationItems stacks the same itemId and appends a new one', () => {
    expect(
      mergeDonationItems(
        [
          { itemId: 'ITEM-0002', quantity: 10 },
          { itemId: 'ITEM-0015', quantity: 2 },
        ],
        [
          { itemId: 'ITEM-0002', quantity: 4 },
          { itemId: 'ITEM-0095', quantity: 1 },
        ],
      ),
    ).toEqual([
      { itemId: 'ITEM-0002', quantity: 14 },
      { itemId: 'ITEM-0015', quantity: 2 },
      { itemId: 'ITEM-0095', quantity: 1 },
    ])
  })
})
