import { addItemToInventoryExact } from '../activity/rewards'
import type { GameDatabase } from '../data/types'
import type { MailAttachment, MailMessage, PlayerSave } from '../save/types'

/** Mail is dropped this long after it was sent. */
export const MAILBOX_TTL_MS = 90 * 24 * 60 * 60 * 1000

export const MAILBOX_TEST_CATALOG_ID = 'mail-mailbox-test'

export interface SystemMailCatalogEntry {
  id: string
  subject: string
  body: string
  sentAt: string
  attachments: MailAttachment[]
}

/**
 * Broadcast mail every save should receive. New rows are appended; existing
 * players pick them up on the next parse. Do not invent update-list copy here —
 * approved text is added as its own catalog row.
 */
export const SYSTEM_MAIL_CATALOG: readonly SystemMailCatalogEntry[] = [
  {
    id: MAILBOX_TEST_CATALOG_ID,
    subject: 'Mailbox',
    body: 'This is a test of the kingdom post. Update lists will arrive here.',
    sentAt: '2026-09-22T00:00:00.000Z',
    attachments: [],
  },
]

export function mailSentAtMs(sentAt: string): number {
  const ms = Date.parse(sentAt)
  return Number.isFinite(ms) ? ms : Number.NaN
}

export function isMailExpired(sentAt: string, nowMs: number): boolean {
  const sentMs = mailSentAtMs(sentAt)
  if (!Number.isFinite(sentMs)) return true
  return nowMs - sentMs >= MAILBOX_TTL_MS
}

export function pruneExpiredMail(save: PlayerSave, nowMs: number): PlayerSave {
  const mailbox = save.mailbox.filter((message) => !isMailExpired(message.sentAt, nowMs))
  if (mailbox.length === save.mailbox.length) return save
  return { ...save, mailbox }
}

export function syncSystemMail(save: PlayerSave, nowMs: number): PlayerSave {
  const pruned = pruneExpiredMail(save, nowMs)
  const have = new Set(
    pruned.mailbox.map((message) => message.catalogId).filter((id): id is string => id != null),
  )
  const extras: MailMessage[] = []
  for (const entry of SYSTEM_MAIL_CATALOG) {
    if (have.has(entry.id)) continue
    if (isMailExpired(entry.sentAt, nowMs)) continue
    extras.push({
      id: entry.id,
      catalogId: entry.id,
      subject: entry.subject,
      body: entry.body,
      sentAt: entry.sentAt,
      readAt: null,
      attachments: entry.attachments.map((attachment) => ({ ...attachment })),
      claimedAt: null,
    })
  }
  if (extras.length === 0) return pruned
  return { ...pruned, mailbox: [...pruned.mailbox, ...extras] }
}

function compareVisibleMail(a: MailMessage, b: MailMessage): number {
  const aUnread = a.readAt == null
  const bUnread = b.readAt == null
  if (aUnread !== bUnread) return aUnread ? -1 : 1
  const sent = mailSentAtMs(b.sentAt) - mailSentAtMs(a.sentAt)
  if (sent !== 0 && Number.isFinite(sent)) return sent
  return a.id < b.id ? -1 : a.id > b.id ? 1 : 0
}

export function visibleMailbox(save: PlayerSave, nowMs: number): MailMessage[] {
  return save.mailbox
    .filter((message) => !isMailExpired(message.sentAt, nowMs))
    .slice()
    .sort(compareVisibleMail)
}

export function unreadMailCount(save: PlayerSave, nowMs: number): number {
  return visibleMailbox(save, nowMs).filter((message) => message.readAt == null).length
}

export function markMailRead(save: PlayerSave, messageId: string, nowMs: number): PlayerSave {
  const mailbox = save.mailbox.map((message) => {
    if (message.id !== messageId || message.readAt != null) return message
    if (isMailExpired(message.sentAt, nowMs)) return message
    return { ...message, readAt: new Date(nowMs).toISOString() }
  })
  return { ...save, mailbox }
}

export function claimMailAttachments(
  save: PlayerSave,
  messageId: string,
  nowMs: number,
  db?: GameDatabase,
): { ok: true; save: PlayerSave } | { ok: false; reason: string } {
  const message = save.mailbox.find((entry) => entry.id === messageId)
  if (!message || isMailExpired(message.sentAt, nowMs)) {
    return { ok: false, reason: 'That letter is gone.' }
  }
  if (message.attachments.length === 0) {
    return { ok: false, reason: 'Nothing to claim.' }
  }
  if (message.claimedAt != null) {
    return { ok: false, reason: 'Those items were already claimed.' }
  }
  let next = save
  for (const attachment of message.attachments) {
    const granted = addItemToInventoryExact(next, attachment.itemId, attachment.quantity, null, false, db)
    if (!granted.ok) return granted
    next = granted.save
  }
  const claimedAt = new Date(nowMs).toISOString()
  return {
    ok: true,
    save: {
      ...next,
      mailbox: next.mailbox.map((entry) =>
        entry.id === messageId
          ? { ...entry, claimedAt, readAt: entry.readAt ?? claimedAt }
          : entry,
      ),
    },
  }
}
