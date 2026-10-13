import { plazaPointsOf } from '../economy/plaza'
import type { PlayerSave } from './types'

function claimedIds(save: PlayerSave): string[] {
  return Array.isArray(save.bountyClaimedIds) ? save.bountyClaimedIds : []
}

function counter(value: unknown): number {
  return Math.max(0, Math.floor(Number(value) || 0))
}

/**
 * True when a client save tried to invent gold, a bounty claim, or PvP wins
 * relative to the hosted copy. Hosted `sync` already ignores the client
 * payload; this is the remaining client-write path (`_uploadClientSave` and
 * tests).
 */
export function clientSaveRaisesPayouts(server: PlayerSave, client: PlayerSave): boolean {
  if (client.gold > server.gold) return true
  if (plazaPointsOf(client) > plazaPointsOf(server)) return true
  const allowed = new Set(claimedIds(server))
  if (claimedIds(client).some((id) => !allowed.has(id))) return true
  if (counter(client.rankedPvpWins) > counter(server.rankedPvpWins)) return true
  if (counter(client.rankedPvpLosses) > counter(server.rankedPvpLosses)) return true
  if (client.rankedPvpDayKey === server.rankedPvpDayKey) {
    if (counter(client.rankedPvpFightsToday) > counter(server.rankedPvpFightsToday)) return true
  } else if (counter(client.rankedPvpFightsToday) > 0 && server.rankedPvpDayKey != null) {
    return true
  }
  return false
}

/**
 * Keeps the client's other progress, but puts gold, bounty claims, and PvP
 * win counters back to the server's values when the client raised them.
 */
export function replaceUnauthorizedPayouts(server: PlayerSave, client: PlayerSave): PlayerSave {
  const allowed = new Set(claimedIds(server))
  const gold = client.gold > server.gold ? server.gold : client.gold
  const plazaPoints =
    plazaPointsOf(client) > plazaPointsOf(server) ? plazaPointsOf(server) : plazaPointsOf(client)
  const rankedPvpWins =
    counter(client.rankedPvpWins) > counter(server.rankedPvpWins)
      ? server.rankedPvpWins
      : client.rankedPvpWins
  const rankedPvpLosses =
    counter(client.rankedPvpLosses) > counter(server.rankedPvpLosses)
      ? server.rankedPvpLosses
      : client.rankedPvpLosses
  let rankedPvpDayKey = client.rankedPvpDayKey
  let rankedPvpFightsToday = client.rankedPvpFightsToday
  if (client.rankedPvpDayKey === server.rankedPvpDayKey) {
    if (counter(client.rankedPvpFightsToday) > counter(server.rankedPvpFightsToday)) {
      rankedPvpFightsToday = server.rankedPvpFightsToday
    }
  } else if (counter(client.rankedPvpFightsToday) > 0 && server.rankedPvpDayKey != null) {
    rankedPvpDayKey = server.rankedPvpDayKey
    rankedPvpFightsToday = server.rankedPvpFightsToday
  }
  return {
    ...client,
    gold,
    plazaPoints,
    bountyClaimedIds: claimedIds(client).filter((id) => allowed.has(id)),
    rankedPvpWins,
    rankedPvpLosses,
    rankedPvpDayKey,
    rankedPvpFightsToday,
  }
}
