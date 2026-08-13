const BASIC_PROFANITY = /\b(fuck|shit|asshole|cunt|nigger|faggot)\b/gi

/**
 * Masks the words the shipped list covers, leaving length intact so the reader
 * can tell something was removed.
 *
 * Kept apart from any one backend because everything a player writes goes
 * through it — chat, Bazaar notices — and a hosted backend has to mask the same
 * words as the local one.
 */
export function filterProfanity(body: string): string {
  return body.replace(BASIC_PROFANITY, (match) => '*'.repeat(match.length))
}
