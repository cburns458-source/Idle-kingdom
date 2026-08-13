import { describe, expect, it } from 'vitest'
import type { BazaarPost } from './types'
import { bazaarKindOptions, bazaarRows } from './views'

function post(id: string, username: string, kind: BazaarPost['kind'], body: string): BazaarPost {
  return { id, kind, userId: `usr-${id}`, username, body, createdAt: '2026-08-12T13:00:00.000Z' }
}

describe('bazaar rows', () => {
  it('shows the newest notice first', () => {
    const rows = bazaarRows([
      post('1', 'Rowan', 'message', 'Hello'),
      post('2', 'Bryn', 'trade', 'Selling ore'),
    ])
    expect(rows.map((row) => row.postId)).toEqual(['2', '1'])
    expect(rows[0]).toEqual({ postId: '2', heading: 'Bryn · trade', body: 'Selling ore' })
  })

  it('leaves the list it was handed alone', () => {
    const posts = [post('1', 'Rowan', 'message', 'Hello'), post('2', 'Bryn', 'trade', 'Ore')]
    bazaarRows(posts)
    expect(posts.map((row) => row.id)).toEqual(['1', '2'])
  })

  it('offers the three kinds a post can be', () => {
    expect(bazaarKindOptions().map((option) => option.kind)).toEqual([
      'message',
      'recruit',
      'trade',
    ])
    expect(bazaarKindOptions().map((option) => option.label)).toEqual([
      'Message',
      'Recruit',
      'Trade',
    ])
  })
})
