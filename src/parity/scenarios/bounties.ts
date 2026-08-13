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
import {
  BOUNTY_SIGN_IN_NOTICE,
  bountyClaimedNotice,
  bountyRotationLine,
  bountyRows,
} from '../../game/bounties/views'
import {
  BAZAAR_BLURB,
  BAZAAR_BODY_MAX_LENGTH,
  BAZAAR_EMPTY_BODY,
  BAZAAR_EMPTY_HEADING,
  BAZAAR_PLACEHOLDER,
  BAZAAR_POSTED_NOTICE,
  BAZAAR_SIGN_IN_NOTICE,
  bazaarKindOptions,
  bazaarRows,
} from '../../game/bazaar/views'
import type { BazaarPost } from '../../game/bazaar/types'
import {
  CITADEL_HUB_TAB_LABELS,
  citadelHubTabsFor,
  citadelHubTitleFor,
} from '../../game/multiplayer/citadel'
import { CITADEL_MARKET_ID, CITADEL_PLAZA_ID } from '../../game/world/constants'
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

/**
 * A save part-way through the board this hour: one bounty finished, one half
 * done, one already claimed, and the bag stocked for anything that asks for
 * delivery rather than a counter.
 */
function boardSave(): PlayerSave {
  const board = hourlyBountyBoard(NOW_MS)
  const base = syncBountyHour(baseSave(contentDatabase()), NOW_MS)
  const progress: Record<string, number> = {}
  const [first, second, third] = board.bounties
  if (first) progress[first.id] = first.amount
  if (second) progress[second.id] = Math.floor(second.amount / 2)
  return {
    ...base,
    bountyProgress: progress,
    bountyClaimedIds: third ? [third.id] : [],
    inventory: board.bounties
      .filter((bounty) => bounty.kind === 'gather_deliver')
      .map((bounty) => ({ itemId: bounty.targetId, quantity: bounty.amount })),
  }
}

/**
 * The same board one short of done everywhere, so the counters and the bag are
 * both read while nothing is claimable.
 */
function partialBoardSave(): PlayerSave {
  const board = hourlyBountyBoard(NOW_MS)
  const base = syncBountyHour(baseSave(contentDatabase()), NOW_MS)
  return {
    ...base,
    bountyProgress: Object.fromEntries(
      board.bounties.map((bounty) => [bounty.id, Math.max(0, bounty.amount - 1)]),
    ),
    inventory: board.bounties
      .filter((bounty) => bounty.kind === 'gather_deliver')
      .map((bounty) => ({ itemId: bounty.targetId, quantity: Math.max(0, bounty.amount - 1) })),
  }
}

/** The hour's recorded first turn-in, for the one bounty somebody finished. */
function boardClaims() {
  const first = hourlyBountyBoard(NOW_MS).bounties[0]
  if (!first) return []
  return [
    {
      hourKey: hourlyBountyBoard(NOW_MS).hourKey,
      bountyId: first.id,
      userId: 'usr_0001',
      username: 'Rowan',
      claimedAt: '2026-08-12T21:00:00.000Z',
    },
  ]
}

const BAZAAR_POSTS: BazaarPost[] = [
  {
    id: 'baz_0001',
    kind: 'message',
    userId: 'usr_0001',
    username: 'Rowan',
    body: 'Anyone seen the smith?',
    createdAt: '2026-08-12T20:00:00.000Z',
  },
  {
    id: 'baz_0002',
    kind: 'recruit',
    userId: 'usr_0002',
    username: 'Bryn',
    body: 'Iron League is hiring',
    createdAt: '2026-08-12T20:30:00.000Z',
  },
  {
    id: 'baz_0003',
    kind: 'trade',
    userId: 'usr_0003',
    username: 'Wren',
    body: 'Selling copper ore, 20 each',
    createdAt: '2026-08-12T20:45:00.000Z',
  },
]

const HUB_LOCATION_IDS = [CITADEL_PLAZA_ID, CITADEL_MARKET_ID, 'LOC-0002', 'not-a-location']

const REMAINING_LABELS = ['44m 5s', '0s', '1h 2m 3s']

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

  scenario(
    'bounties/views',
    'board',
    {
      source: 'content',
      save: asJson(boardSave()),
      partial: asJson(partialBoardSave()),
      fresh: asJson(syncBountyHour(baseSave(contentDatabase()), NOW_MS)),
      claims: boardClaims() as unknown as JsonValue,
      remainingLabels: REMAINING_LABELS,
      nowMs: NOW_MS,
    },
    () => {
      const board = hourlyBountyBoard(NOW_MS)
      const save = boardSave()
      const fresh = syncBountyHour(baseSave(contentDatabase()), NOW_MS)
      const claims = boardClaims()
      return {
        rows: bountyRows(save, board, claims, true, NOW_MS),
        signedOutRows: bountyRows(save, board, claims, false, NOW_MS),
        partialRows: bountyRows(partialBoardSave(), board, claims, true, NOW_MS),
        // Nothing started and nobody ahead: every row reads the same way.
        freshRows: bountyRows(fresh, board, [], true, NOW_MS),
        rotationLines: REMAINING_LABELS.map(bountyRotationLine),
        claimedNotices: [bountyClaimedNotice(180, true), bountyClaimedNotice(120, false)],
        signInNotice: BOUNTY_SIGN_IN_NOTICE,
      } as unknown as JsonValue
    },
  ),

  scenario(
    'bazaar/views',
    'board',
    { source: 'raw', posts: BAZAAR_POSTS as unknown as JsonValue },
    () =>
      ({
        rows: bazaarRows(BAZAAR_POSTS),
        empty: bazaarRows([]),
        kinds: bazaarKindOptions(),
        blurb: BAZAAR_BLURB,
        placeholder: BAZAAR_PLACEHOLDER,
        maxLength: BAZAAR_BODY_MAX_LENGTH,
        signInNotice: BAZAAR_SIGN_IN_NOTICE,
        emptyHeading: BAZAAR_EMPTY_HEADING,
        emptyBody: BAZAAR_EMPTY_BODY,
        postedNotice: BAZAAR_POSTED_NOTICE,
      }) as unknown as JsonValue,
  ),

  scenario(
    'citadel/hub',
    'tabs',
    { source: 'raw', locationIds: HUB_LOCATION_IDS },
    () =>
      ({
        districts: HUB_LOCATION_IDS.map((locationId) => ({
          locationId,
          tabs: citadelHubTabsFor(locationId),
          title: citadelHubTitleFor(locationId),
        })),
        labels: CITADEL_HUB_TAB_LABELS,
      }) as unknown as JsonValue,
  ),
]
