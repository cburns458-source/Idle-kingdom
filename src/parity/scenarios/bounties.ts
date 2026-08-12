import { BOUNTIES_PER_HOUR, BOUNTY_CATALOG } from '../../game/bounties/catalog'
import {
  applyBountyDefeatProgress,
  applyBountyProcessProgress,
  applyBountyProjectProgress,
  bountyProgressFor,
  isBountyReadyToClaim,
  syncBountyHour,
} from '../../game/bounties/progress'
import {
  bountyHourExpiresAtMs,
  bountyHourKey,
  hourlyBountyBoard,
} from '../../game/bounties/rotation'
import type { PlayerSave } from '../../game/save/types'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import { contentDatabase } from './contentDatabase'
import { asJson, baseSave, questSave } from './saveFixtures'

type SaveKind = 'base' | 'quest'

function saveFor(kind: SaveKind): PlayerSave {
  const db = contentDatabase()
  return kind === 'base' ? baseSave(db) : questSave(db)
}

/**
 * Hours spread across a day and a year boundary, since the board is sampled
 * from a hash of the UTC hour key.
 */
const HOUR_STAMPS = [
  '2026-01-01T00:00:00.000Z',
  '2026-01-01T00:59:59.999Z',
  '2026-01-01T13:30:00.000Z',
  '2026-08-12T21:00:00.000Z',
  '2026-12-31T23:45:00.000Z',
  '1970-01-01T00:00:00.000Z',
]

const HOUR_KEYS = ['2026-08-12T13', '2026-12-31T23', 'not-an-hour']

const NOW_MS = Date.parse('2026-08-12T21:00:00.000Z')

export const bountyScenarios: ParityScenario[] = [
  scenario('bounties/catalog', 'rows', { source: 'content' }, () => ({
    perHour: BOUNTIES_PER_HOUR,
    bounties: BOUNTY_CATALOG as unknown as JsonValue,
  })),

  scenario('bounties/rotation', 'hourly-boards', { source: 'content', stamps: HOUR_STAMPS }, () => ({
    boards: HOUR_STAMPS.map((stamp) => {
      const nowMs = Date.parse(stamp)
      return {
        stamp,
        hourKey: bountyHourKey(nowMs),
        board: hourlyBountyBoard(nowMs) as unknown as JsonValue,
      }
    }),
    // An unparseable key falls back to one hour from the caller's clock.
    expiries: HOUR_KEYS.map((hourKey) => ({
      hourKey,
      expires: bountyHourExpiresAtMs(hourKey, NOW_MS),
    })),
  }) as unknown as JsonValue),

  ...(['base', 'quest'] as const).map((kind) =>
    scenario(
      'bounties/progress',
      kind,
      { source: 'content', save: asJson(saveFor(kind)), nowMs: NOW_MS },
      () => {
        const save = saveFor(kind)
        const synced = syncBountyHour(save, NOW_MS)
        const board = hourlyBountyBoard(NOW_MS)
        const defeated = applyBountyDefeatProgress(save, 'ENM-0001', 3, NOW_MS)
        const processed = applyBountyProcessProgress(defeated, 'RCP-0001', 2, NOW_MS)
        const projected = applyBountyProjectProgress(processed, 'PRJ-0007', 1, NOW_MS)
        return {
          synced: asJson(synced),
          defeated: asJson(defeated),
          processed: asJson(processed),
          projected: asJson(projected),
          // gather_deliver counts the bag, so it never writes a counter.
          gatherStaysUncounted: asJson(
            applyBountyProcessProgress(save, 'ITEM-0030', 5, NOW_MS),
          ),
          progressAfter: board.bounties.map((bounty) => ({
            id: bounty.id,
            kind: bounty.kind,
            progress: bountyProgressFor(projected, bounty, NOW_MS),
            ready: isBountyReadyToClaim(projected, bounty, NOW_MS),
          })),
        } as unknown as JsonValue
      },
    ),
  ),

  scenario(
    'bounties/progress',
    'hour-rollover',
    { source: 'content', save: asJson(saveFor('base')), nowMs: NOW_MS },
    () => {
      const board = hourlyBountyBoard(NOW_MS)
      const stale: PlayerSave = {
        ...saveFor('base'),
        bountyHourKey: '2020-01-01T00',
        bountyProgress: { 'BNT-0005': 4 },
        bountyClaimedIds: ['BNT-0005'],
      }
      return {
        stale: asJson(stale),
        synced: asJson(syncBountyHour(stale, NOW_MS)),
        readyBefore: board.bounties.map((bounty) => isBountyReadyToClaim(stale, bounty, NOW_MS)),
      }
    },
  ),
]
