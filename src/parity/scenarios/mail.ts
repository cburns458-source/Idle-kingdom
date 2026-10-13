import { INVENTORY_SLOT_LIMIT } from '../../game/inventory/capacity'
import { claimMailAttachments } from '../../game/mail/mail'
import type { PlayerSave } from '../../game/save/types'
import { scenario, type JsonValue, type ParityScenario } from '../types'
import { contentDatabase } from './contentDatabase'
import { asJson, baseSave, FIXED_TIMESTAMP_MS } from './saveFixtures'

const CLAIM_NOW_MS = FIXED_TIMESTAMP_MS

function giftMail(save: PlayerSave): PlayerSave {
  return {
    ...save,
    mailbox: [
      {
        id: 'mail-gift',
        catalogId: null,
        subject: 'A parcel',
        body: 'Try this.',
        sentAt: new Date(CLAIM_NOW_MS).toISOString(),
        readAt: null,
        attachments: [
          { itemId: 'ITEM-0025', quantity: 1 },
          { itemId: 'ITEM-0058', quantity: 1 },
          { itemId: 'ITEM-0003', quantity: 1 },
        ],
        claimedAt: null,
      },
    ],
  }
}

function oneFreeSlotSave(): PlayerSave {
  const base = giftMail(baseSave(contentDatabase()))
  return {
    ...base,
    inventory: Array.from({ length: INVENTORY_SLOT_LIMIT - 1 }, (_, index) => ({
      itemId: `FILL-${index}`,
      quantity: 1,
    })),
  }
}

export const mailScenarios: ParityScenario[] = [
  scenario(
    'mail/claim',
    'one-free-slot',
    {
      source: 'content',
      save: asJson(oneFreeSlotSave()),
      messageId: 'mail-gift',
      nowMs: CLAIM_NOW_MS,
    },
    () =>
      claimMailAttachments(
        oneFreeSlotSave(),
        'mail-gift',
        CLAIM_NOW_MS,
        contentDatabase(),
      ) as unknown as JsonValue,
  ),
]
