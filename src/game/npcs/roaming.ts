import type { GameDatabase, NpcRow } from '../data/types'

/** Mountains, Deep Mines, Abandoned Mineshaft. */
export const MASTER_DWARF_ROUTE = ['LOC-0006', 'LOC-0011', 'LOC-0022'] as const

export const MASTER_DWARF_ID = 'NPC-0003'
export const DWARVEN_MINING_MERCHANT_ID = 'NPC-0008'

/** UTC calendar day `YYYY-MM-DD` for [nowMs]. */
export function roamingDayKey(nowMs: number): string {
  return new Date(nowMs).toISOString().slice(0, 10)
}

function hashString(input: string): number {
  let hash = 2166136261
  for (let i = 0; i < input.length; i += 1) {
    hash ^= input.charCodeAt(i)
    hash = Math.imul(hash, 16777619)
  }
  return hash >>> 0
}

/** One shared stop for the day, independent of yesterday's roll. */
export function roamingLocationFor(
  npcId: string,
  route: readonly string[],
  nowMs: number,
): string {
  if (route.length === 0) return ''
  const seed = hashString(`${npcId}:${roamingDayKey(nowMs)}`)
  return route[seed % route.length] ?? route[0]!
}

export function npcLocationAt(npc: NpcRow, nowMs: number): string {
  if (npc['NPC ID'] === MASTER_DWARF_ID) {
    return roamingLocationFor(MASTER_DWARF_ID, MASTER_DWARF_ROUTE, nowMs)
  }
  return npc['Location ID']
}

export function masterDwarfLocationId(nowMs: number): string {
  return roamingLocationFor(MASTER_DWARF_ID, MASTER_DWARF_ROUTE, nowMs)
}

export function locationDisplayName(db: GameDatabase, locationId: string): string {
  return db.Locations.find((row) => row['Location ID'] === locationId)?.['Display Name'] ?? locationId
}
