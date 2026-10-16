export const GUILD_LOG_KINDS = [
  'tier_complete',
  'donation',
  'join',
  'leave',
  'rank_change',
] as const

export type GuildLogKind = (typeof GUILD_LOG_KINDS)[number]

export type GuildLogDonationItem = {
  itemId: string
  quantity: number
}

export type GuildLogEntry = {
  id: string
  guildId: string
  kind: GuildLogKind
  createdAt: string
  actorUserId: string | null
  actorUsername: string
  /** Rank after a change, or the role the player joined as. */
  role: string | null
  /** Target of a rank change or a leave/kick. */
  targetUserId: string | null
  targetUsername: string | null
  tierId: string | null
  message: string
  gold: number
  items: GuildLogDonationItem[]
}

export function guildLogDonationItemsEqual(
  left: GuildLogDonationItem[],
  right: GuildLogDonationItem[],
): boolean {
  if (left.length !== right.length) return false
  for (let i = 0; i < left.length; i += 1) {
    if (left[i].itemId !== right[i].itemId || left[i].quantity !== right[i].quantity) return false
  }
  return true
}

/**
 * Consecutive donation batches from one player merge into one line.
 *
 * Same actor, same kind, no other event in between: gold and item quantities add.
 */
export function mergeGuildLogDonation(
  newest: GuildLogEntry | null,
  incoming: Omit<GuildLogEntry, 'id' | 'createdAt'> & { createdAt?: string; id?: string },
): { merged: true; entry: GuildLogEntry } | { merged: false } {
  if (!newest || newest.kind !== 'donation' || incoming.kind !== 'donation') {
    return { merged: false }
  }
  if (newest.actorUserId !== incoming.actorUserId || !newest.actorUserId) {
    return { merged: false }
  }
  const items = mergeDonationItems(newest.items, incoming.items)
  return {
    merged: true,
    entry: {
      ...newest,
      gold: newest.gold + incoming.gold,
      items,
      message: incoming.message || newest.message,
    },
  }
}

export function mergeDonationItems(
  existing: GuildLogDonationItem[],
  added: GuildLogDonationItem[],
): GuildLogDonationItem[] {
  const next = existing.map((row) => ({ ...row }))
  for (const row of added) {
    const at = next.findIndex((entry) => entry.itemId === row.itemId)
    if (at < 0) next.push({ itemId: row.itemId, quantity: row.quantity })
    else next[at] = { ...next[at], quantity: next[at].quantity + row.quantity }
  }
  return next
}
