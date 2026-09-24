import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'
import { prepareDatabase } from '../data/loadDatabase'
import { createNewSave } from '../save/saveStore'
import { migrateSave } from '../save/migrations'
import type { MailMessage, PlayerSave } from '../save/types'
import { SAVE_VERSION } from '../save/types'
import {
  MAIL_UPDATE_2026_09_24_CATALOG_ID,
  MAIL_UPDATE_2026_09_22_CATALOG_ID,
  MAILBOX_TEST_CATALOG_ID,
  MAILBOX_TTL_MS,
  claimMailAttachments,
  markMailRead,
  pruneExpiredMail,
  syncSystemMail,
  unreadMailCount,
  visibleMailbox,
} from './mail'

const rawDatabase = JSON.parse(
  readFileSync(resolve(process.cwd(), 'content/data/game-database.json'), 'utf8'),
)

const NOW_MS = Date.parse('2026-09-22T12:00:00.000Z')

function giftMail(nowMs: number, attachments: MailMessage['attachments'] = []): MailMessage {
  return {
    id: 'mail-gift',
    catalogId: null,
    subject: 'A parcel',
    body: 'Try this.',
    sentAt: new Date(nowMs).toISOString(),
    readAt: null,
    attachments,
    claimedAt: null,
  }
}

describe('mailbox', () => {
  it('delivers the test letter to a new save', () => {
    const { source } = prepareDatabase(rawDatabase)
    const save = createNewSave(source, NOW_MS)
    expect(save.mailbox.map((message) => message.id)).toContain(MAILBOX_TEST_CATALOG_ID)
    expect(save.mailbox.map((message) => message.id)).toContain(MAIL_UPDATE_2026_09_22_CATALOG_ID)
    expect(save.mailbox.map((message) => message.id)).toContain(MAIL_UPDATE_2026_09_24_CATALOG_ID)
    expect(unreadMailCount(save, NOW_MS)).toBe(3)
    expect(visibleMailbox(save, NOW_MS)[0]?.attachments).toEqual([])
  })

  it('stays after it is read and is not delivered twice', () => {
    const { source } = prepareDatabase(rawDatabase)
    const save = createNewSave(source, NOW_MS)
    const read = markMailRead(save, MAILBOX_TEST_CATALOG_ID, NOW_MS)
    expect(read.mailbox.find((message) => message.id === MAILBOX_TEST_CATALOG_ID)?.readAt).toBe(
      new Date(NOW_MS).toISOString(),
    )
    expect(unreadMailCount(read, NOW_MS)).toBe(2)
    expect(syncSystemMail(read, NOW_MS).mailbox).toHaveLength(save.mailbox.length)
  })

  it('drops letters 90 days after they were sent', () => {
    const { source } = prepareDatabase(rawDatabase)
    const save = createNewSave(source, NOW_MS)
    const later = NOW_MS + MAILBOX_TTL_MS + 3 * 24 * 60 * 60 * 1000
    expect(pruneExpiredMail(save, later).mailbox).toEqual([])
    expect(syncSystemMail(save, later).mailbox).toEqual([])
  })

  it('claims attached items into the bag or refuses when the bag is full', () => {
    const { source } = prepareDatabase(rawDatabase)
    const base = createNewSave(source, NOW_MS)
    const withGift: PlayerSave = {
      ...base,
      mailbox: [giftMail(NOW_MS, [{ itemId: 'ITEM-0025', quantity: 3 }])],
    }
    const claimed = claimMailAttachments(withGift, 'mail-gift', NOW_MS, source)
    expect(claimed.ok).toBe(true)
    if (!claimed.ok) return
    expect(claimed.save.inventory.find((stack) => stack.itemId === 'ITEM-0025')?.quantity).toBe(3)
    expect(claimed.save.mailbox[0]?.claimedAt).toBe(new Date(NOW_MS).toISOString())
    expect(claimMailAttachments(claimed.save, 'mail-gift', NOW_MS, source).ok).toBe(false)

    const full: PlayerSave = {
      ...withGift,
      inventory: Array.from({ length: 180 }, (_, index) => ({
        itemId: `FILL-${index}`,
        quantity: 1,
      })),
    }
    const refused = claimMailAttachments(full, 'mail-gift', NOW_MS, source)
    expect(refused.ok).toBe(false)
    if (refused.ok) return
    expect(refused.reason).toMatch(/full/)
  })

  it('adds an empty mailbox when migrating a v50 save', () => {
    const { source } = prepareDatabase(rawDatabase)
    const created = createNewSave(source, NOW_MS)
    const { mailbox: _dropped, ...rest } = created
    const legacy = { ...rest, saveVersion: 50, mailbox: undefined }
    const migrated = migrateSave(legacy as unknown as PlayerSave, NOW_MS)
    expect(migrated.saveVersion).toBe(SAVE_VERSION)
    expect(migrated.mailbox).toEqual([])
    expect(migrated.settings.skipHostileTravelWarning).toBe(false)
  })
})
