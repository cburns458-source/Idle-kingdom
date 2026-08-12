import { getSession, isSignedIn } from '../multiplayer/auth'
import { getLocalBackend } from '../multiplayer/client'
import type { BazaarPost, BazaarPostKind } from './types'

export function listBazaarPosts(limit = 40): BazaarPost[] {
  return getLocalBackend().listBazaarPosts(limit)
}

export function postToBazaar(
  kind: BazaarPostKind,
  body: string,
): { ok: true; post: BazaarPost } | { ok: false; reason: string } {
  if (!isSignedIn()) return { ok: false, reason: 'Sign in to post in the Grand Bazaar.' }
  const session = getSession()
  if (!session) return { ok: false, reason: 'Sign in to post in the Grand Bazaar.' }
  return getLocalBackend().postBazaar(session, kind, body)
}
