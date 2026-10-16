/** ADM-04 submit-feedback validation. Keep in lockstep with packages/ik_net/lib/src/feedback.dart. */

import type { FeedbackKind } from './discord.ts'
import { stripZeroWidth } from './discord.ts'

export const FEEDBACK_KINDS = ['bug', 'suggestion', 'player'] as const
export const FEEDBACK_TITLE_MIN = 5
export const FEEDBACK_TITLE_MAX = 80
export const FEEDBACK_BODY_MIN = 10
export const FEEDBACK_BODY_MAX = 1000
export const FEEDBACK_COOLDOWN_MS = 60_000
export const FEEDBACK_DAILY_CAP = 5
export const FEEDBACK_DAILY_WINDOW_MS = 86_400_000
export const FEEDBACK_GLOBAL_PER_MINUTE = 20
export const FEEDBACK_CONTEXT_MAX_BYTES = 2048
export const FEEDBACK_CHANNEL_KEY = 'feedback'

export const FEEDBACK_CONTEXT_KEYS = ['build', 'platform', 'gameArea'] as const

export type FeedbackContext = {
  build?: string
  platform?: string
  gameArea?: string
}

export type ParsedFeedback = {
  kind: FeedbackKind
  title: string
  body: string
  targetUsername: string
  reportReason: string
  context: FeedbackContext
}

export type FeedbackParseError = { error: string; status: number }

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

export function isUuid(value: string): boolean {
  return UUID.test(value)
}

export function shortPlayerId(userId: string): string {
  return userId.replaceAll('-', '').slice(0, 8)
}

export function clipField(raw: unknown, max: number): string {
  if (typeof raw !== 'string') return ''
  return stripZeroWidth(raw).trim().slice(0, max)
}

export function sanitizeContext(raw: unknown): FeedbackContext {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return {}
  const source = raw as Record<string, unknown>
  const context: FeedbackContext = {}
  const build = clipField(source.build, 40)
  const platform = clipField(source.platform, 16).toLowerCase()
  const gameArea = clipField(source.gameArea, 40)
  if (build) context.build = build
  if (platform === 'web' || platform === 'android' || platform === 'ios' || platform === 'other') {
    context.platform = platform
  }
  if (gameArea) context.gameArea = gameArea
  return context
}

export function contextWithinLimit(context: FeedbackContext): boolean {
  return new TextEncoder().encode(JSON.stringify(context)).length <= FEEDBACK_CONTEXT_MAX_BYTES
}

export function parseFeedbackBody(raw: unknown): ParsedFeedback | FeedbackParseError {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    return { error: 'Details are too short.', status: 400 }
  }
  const body = raw as Record<string, unknown>
  const kindRaw = typeof body.kind === 'string' ? body.kind.trim().toLowerCase() : ''
  if (!FEEDBACK_KINDS.includes(kindRaw as FeedbackKind)) {
    return { error: 'Choose Bug, Suggestion, or Player.', status: 400 }
  }
  const title = clipField(body.title, FEEDBACK_TITLE_MAX + 20)
  const details = clipField(body.body, FEEDBACK_BODY_MAX + 40)
  if (title.length < FEEDBACK_TITLE_MIN) return { error: 'Summary is too short.', status: 400 }
  if (title.length > FEEDBACK_TITLE_MAX) return { error: 'Summary is too long.', status: 400 }
  if (details.length < FEEDBACK_BODY_MIN) return { error: 'Details are too short.', status: 400 }
  if (details.length > FEEDBACK_BODY_MAX) return { error: 'Details are too long.', status: 400 }

  const targetUsername = clipField(body.targetUsername ?? body.target, 24)
  if (kindRaw === 'player' && targetUsername.length < 2) {
    return { error: 'Enter the player to report.', status: 400 }
  }

  const reportReason = clipField(body.reportReason, 280)
  const context = sanitizeContext(body.context)
  if (!contextWithinLimit(context)) {
    return { error: 'That report could not be sent.', status: 400 }
  }

  return {
    kind: kindRaw as FeedbackKind,
    title,
    body: details,
    targetUsername,
    reportReason,
    context,
  }
}

export function feedbackHashInput(parsed: ParsedFeedback): string {
  const target = parsed.kind === 'player' ? parsed.targetUsername.trim().toLowerCase() : ''
  return `${parsed.kind}\n${parsed.title}\n${parsed.body}${target ? `\n${target}` : ''}`
}

export async function sha256Hex(text: string): Promise<string> {
  const data = new TextEncoder().encode(text)
  const hash = await crypto.subtle.digest('SHA-256', data)
  return [...new Uint8Array(hash)].map((byte) => byte.toString(16).padStart(2, '0')).join('')
}

export function retryAfterSeconds(untilMs: number, nowMs: number): number {
  return Math.max(1, Math.ceil((untilMs - nowMs) / 1000))
}

export function usernameFromPublic(raw: unknown): string {
  if (typeof raw !== 'string') return ''
  const trimmed = raw.trim()
  if (!trimmed || trimmed.startsWith('pending_')) return ''
  return trimmed.slice(0, 24)
}
