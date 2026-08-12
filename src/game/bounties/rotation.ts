import { BOUNTIES_PER_HOUR, BOUNTY_CATALOG } from './catalog'
import type { BountyDefinition, HourlyBountyBoard } from './types'

/** UTC hour bucket, e.g. 2026-08-12T13 */
export function bountyHourKey(nowMs: number = Date.now()): string {
  const date = new Date(nowMs)
  const y = date.getUTCFullYear()
  const m = String(date.getUTCMonth() + 1).padStart(2, '0')
  const d = String(date.getUTCDate()).padStart(2, '0')
  const h = String(date.getUTCHours()).padStart(2, '0')
  return `${y}-${m}-${d}T${h}`
}

export function bountyHourExpiresAtMs(hourKey: string, nowMs: number = Date.now()): number {
  const parsed = Date.parse(`${hourKey}:00:00.000Z`)
  if (!Number.isFinite(parsed)) return nowMs + 3_600_000
  return parsed + 3_600_000
}

function hashString(input: string): number {
  let hash = 2166136261
  for (let i = 0; i < input.length; i += 1) {
    hash ^= input.charCodeAt(i)
    hash = Math.imul(hash, 16777619)
  }
  return hash >>> 0
}

/** Deterministic hourly sample from the bounty catalog. */
export function hourlyBountyBoard(nowMs: number = Date.now()): HourlyBountyBoard {
  const hourKey = bountyHourKey(nowMs)
  const pool = [...BOUNTY_CATALOG]
  const selected: BountyDefinition[] = []
  let seed = hashString(hourKey)
  while (selected.length < BOUNTIES_PER_HOUR && pool.length > 0) {
    seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0
    const index = seed % pool.length
    selected.push(pool.splice(index, 1)[0]!)
  }
  return {
    hourKey,
    expiresAtMs: bountyHourExpiresAtMs(hourKey),
    bounties: selected,
  }
}
