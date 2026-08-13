import { filterProfanity } from '../multiplayer/moderation'
import type { BazaarPostKind } from './types'

/** As long as a notice may be, which is what every backend stores. */
export const BAZAAR_POST_MAX_LENGTH = 240

export const BAZAAR_POST_KINDS: readonly BazaarPostKind[] = ['message', 'recruit', 'trade'] as const

export const BAZAAR_EMPTY_POST = 'Message is empty.'
export const BAZAAR_UNKNOWN_KIND = 'Unknown bazaar post kind.'

export type PreparedBazaarPost =
  | { ok: true; body: string }
  | { ok: false; reason: string }

/**
 * What a notice reads as once it has been accepted, or why it was not.
 *
 * Shared because both backends have to agree: a post written against the local
 * board and the same post written against a hosted one should come out the same
 * length, with the same words masked. The cooldown is not decided here, since
 * that needs a clock and a record of the last post.
 */
export function prepareBazaarPost(kind: BazaarPostKind, body: string): PreparedBazaarPost {
  const trimmed = body.trim().slice(0, BAZAAR_POST_MAX_LENGTH)
  if (!trimmed) return { ok: false, reason: BAZAAR_EMPTY_POST }
  if (!BAZAAR_POST_KINDS.includes(kind)) return { ok: false, reason: BAZAAR_UNKNOWN_KIND }
  return { ok: true, body: filterProfanity(trimmed) }
}
