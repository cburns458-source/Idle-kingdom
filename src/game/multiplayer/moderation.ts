const BASIC_PROFANITY = /\b(fuck|shit|asshole|cunt|nigger|faggot)\b/gi
const SLURS = /\b(nigger|faggot)\b/gi

/**
 * Masks the words the shipped list covers, leaving length intact so the reader
 * can tell something was removed.
 *
 * Kept apart from any one backend because a client-side filter and the Bazaar
 * both use it, and a hosted backend has to mask the same words as the local one.
 */
export function filterProfanity(body: string): string {
  return body.replace(BASIC_PROFANITY, (match) => '*'.repeat(match.length))
}

/** Slurs are not a display toggle: sending one disables chat for that account. */
export function containsSlur(body: string): boolean {
  SLURS.lastIndex = 0
  return SLURS.test(body)
}

/** What sendChat says after a slur, and on every later send from that account. */
export const CHAT_DISABLED_NOTICE = 'Chat has been disabled.'
