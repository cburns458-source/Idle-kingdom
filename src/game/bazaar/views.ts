import type { BazaarPost, BazaarPostKind } from './types'

export const BAZAAR_BLURB = 'Market board for messages, recruitment, and trade notices.'
export const BAZAAR_SIGN_IN_NOTICE = 'Sign in to post.'
export const BAZAAR_PLACEHOLDER = 'Write a short notice…'

/** As long as a post can be, matching what the backend accepts. */
export const BAZAAR_BODY_MAX_LENGTH = 240

export interface BazaarKindOption {
  kind: BazaarPostKind
  label: string
}

export function bazaarKindOptions(): BazaarKindOption[] {
  return [
    { kind: 'message', label: 'Message' },
    { kind: 'recruit', label: 'Recruit' },
    { kind: 'trade', label: 'Trade' },
  ]
}

/** One notice on the board. */
export interface BazaarRowView {
  postId: string
  /** `Rowan · trade`. */
  heading: string
  body: string
}

/**
 * The board newest first.
 *
 * The backend hands posts back oldest first, which is the order a chat log
 * wants; a notice board reads the other way round.
 */
export function bazaarRows(posts: BazaarPost[]): BazaarRowView[] {
  return [...posts].reverse().map((post) => ({
    postId: post.id,
    heading: `${post.username} · ${post.kind}`,
    body: post.body,
  }))
}

export const BAZAAR_EMPTY_HEADING = 'Quiet for now'
export const BAZAAR_EMPTY_BODY = 'Be the first to post.'

export const BAZAAR_POSTED_NOTICE = 'Posted to the Grand Bazaar.'
