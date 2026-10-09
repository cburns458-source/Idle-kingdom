import { addItemToInventoryExact } from '../activity/rewards'
import type { GameDatabase } from '../data/types'
import type { MailAttachment, MailMessage, PlayerSave } from '../save/types'

/** Mail is dropped this long after it was sent. */
export const MAILBOX_TTL_MS = 90 * 24 * 60 * 60 * 1000

export const MAILBOX_TEST_CATALOG_ID = 'mail-mailbox-test'

export const MAIL_UPDATE_2026_09_22_CATALOG_ID = 'mail-update-2026-09-22'

export const MAIL_UPDATE_2026_09_24_CATALOG_ID = 'mail-update-2026-09-24'

export const MAIL_UPDATE_2026_09_29_PART1_CATALOG_ID = 'mail-update-2026-09-29-1'

export const MAIL_UPDATE_2026_09_29_PART2_CATALOG_ID = 'mail-update-2026-09-29-2'

export const MAIL_UPDATE_2026_10_06_CATALOG_ID = 'mail-update-2026-10-06'

const MAIL_UPDATE_2026_10_06_BODY = `Update October 5th

- Might: +1% damage every 2 levels from 2 (50% at 100)
- Vitality: +1% damage resistance every 4 levels from 4 (25% at 100)
- Combat Level: +3% max HP every 3 levels from 3 (150% at 150)
- Damage resistance from gear, stance, spells, and Vitality adds into one percent
- Kill Combat XP is half the foe's effective HP after their damage resistance
- Enemy HP retuned for the new Combat Level steps
- When you return after being away, the summary only lists finished fights, not every hit mid-battle

- actions use a 12 second base duration, XP/hr adjusted to stay the same
- Gathering and crafting success chances reworked
- Gear bonuses changed from time reduction to success chance

- Sell prices rescaled, very cheap items sell for 1–2 gold, high-value items mostly unchanged

- Cooked duck and cooked boar meat recipes, pheasant cooking level lowered
- High Elf bonus is fishing instead of extra max HP; Human keeps woodcutting only
- Vesper's race-change gifts are 40 maple for Human and 40 bass for High Elf

- Tools and weapons no longer need leather straps in the forge, armor and shields still do
- Smithing XP on armor and shields increased

- Up to three pot placements per fishing site per UTC day

- A failed steal attempt gets you caught: you take damage and get no XP or loot. Lockpicks can still break on a catch

- Friends list shows Online, Away, or Offline, with an optional setting to share your location with friends

- Natural HP regen waits 60 seconds after damage, then heals 1% max HP per minute, doubling each minute until you take damage again or you are full

- Minor UI tweaks

Vari`

const MAIL_UPDATE_2026_09_29_PART1_BODY = `Update (Sep 24–29)

Combat and enemies
- Enemies use updated Might and Vitality splits; XP rebalanced
- Large pass on combat and hunting loot tables
- New Kingsroad between Farm and Town with bandit fights
- Mixed gather-and-fight activities warn you may be attacked while working; skip prompts are per place or per activity, not one global toggle
- Bow hunting bonus XP follows your combat stance; quiver hunting XP only with a bow equipped

World and travel
- Many locations got new or shuffled activities
- Riverside Manor added with fishing, grounds, hunting, storeroom, and kitchen

Ancient Forest and quests
- Through the Thicket reworked into the Ancient Forest access quest
- Green Thumb is a miniquest after Getting Started that teaches botany
- Library tab with the Newcomer's Guide and Botanist's Guide, books for now are placeholders
- Forest Offering and Stolen Coin Purse cannot be sold, listed, or destroyed`

const MAIL_UPDATE_2026_09_29_PART2_BODY = `Update (Sep 24–29)

Gathering and crafting
- Broad rebalance of gathering, fishing, hunting, botany, and crafting unlock levels
- Production crafts succeed slightly more often now
- Tuna is now bass
- Cooking stews, potions, metallurgy bars, smithing, and artisanry recipes retuned

Thievery
- Expanded steal ladder plus updated loot on barracks, armory, kitchen, storeroom, noble purse, wizard shop, bank vault, and more

Arcana
- New spells including Hoard, Iron Ward, Lifesteal, Warrior Might, Haste, and Pathfinder
- Enchantment ladder expanded and rebalanced

Critters and deeds
- New habitat critters; farm fly replaced by chick
- Rare baby dragon pet from dragon kills
- New Champion deeds and milestones; Critter collector is a Log milestone now

Botany
- Fixed botany collections not returning seeds
- Planting unlock levels shifted; new willow, ironwood, and elder yew saplings in the ladder

Other
- Chat sends immediately with no cooldown between messages
- Favorite or unfavorite from the item detail sheet; bag hearts are display only

Minor UI tweaks

Vari - ❤️`

const MAIL_UPDATE_2026_09_24_BODY = `Update (Sep 23–24)

Combat
- Enemies now use Might and Vitality; bestiary shows Combat XP plus those stats
- Rebalanced XP for defeating monsters
- Danger warnings updated for Goblin Camp, Docks, Queen's Quarters, and Castle Crypt
- Auto-eat after each combat round; Eat now on the map on the right (inventory Eat menu unchanged)
- Twelve new foes listed in the bestiary (not placed in the world yet)

Mountains
- Mountains are a sub-map with The Slopes, Temple, The Peak, Badlands, and Giant Camp
- The Peak and Giant Camp are hostile areas with new fights

Gathering
- Expanded gathering and recipes through higher levels: wild boar hunt, new trees and mines, marlin and swordfish, and more
- Added willow, cinnamon, ironwood, Elder Yew, and Heartwood woodcutting
- Added chromium and vanadium ore and bars
- Rebalanced Starroot; added Bleeding Tooth mushrooms
- Man of War at the jellyfish tier
- New gathering actions are in menus and the codex but not placed at a location yet (wild boar hunt in Kingswoods is live)

Leather
- Cows, bulls, and elk drop hides instead of leather
- Tanner at each Crafting Workshop: tan hides from your bag or bank for gold

Minor UI tweaks

Vari - ❤️`

const MAIL_UPDATE_2026_09_22_BODY = `Update (Sep 22–23)

Combat
- Added copper sword and dagger
- New Combat Level leaderboard!
- New characters default to Offensive stance
- View an opponent's gear before PvP

Gathering
- Rebalanced gather and craft success
- Pot fishing XP increased

Food and potions
- Eat now on your equipment screen
- Auto-eat tweaks
- Potion icon while adventuring; tap to pause

Botany
- Plants can fail when they grow; gather compost on Patches and use it when planting to improve your odds
- New botany seeds and mutations, including Moonblossom at Botany 70
- Botany menu: Crops, Herbs, Flowers, Trees
- Pruners give reduced Botany XP

Features
- New in-game mailbox! Open mail from the top bar, read messages, and claim attached items
- Bazaar expanded to six offer slots; recent trades open from a button on the page
- XP and Loot trackers under your location name on the map
- Lockpicks require Thievery 20
- Added soup stock, go to a kitchen and combine water and kitchen scraps, used to make stews and soups
- Signing in on another device ends your other active session while you are playing

Minor balance changes
Minor UI tweaks
Minor art updates

Vari - ❤️`

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
  {
    id: MAIL_UPDATE_2026_09_22_CATALOG_ID,
    subject: 'Update (Sep 22–23)',
    body: MAIL_UPDATE_2026_09_22_BODY,
    sentAt: '2026-09-23T00:00:00.000Z',
    attachments: [],
  },
  {
    id: MAIL_UPDATE_2026_09_24_CATALOG_ID,
    subject: 'Update (Sep 23–24)',
    body: MAIL_UPDATE_2026_09_24_BODY,
    sentAt: '2026-09-24T00:00:00.000Z',
    attachments: [],
  },
  {
    id: MAIL_UPDATE_2026_09_29_PART1_CATALOG_ID,
    subject: 'Update (Sep 24–29)',
    body: MAIL_UPDATE_2026_09_29_PART1_BODY,
    sentAt: '2026-09-29T00:00:00.000Z',
    attachments: [],
  },
  {
    id: MAIL_UPDATE_2026_09_29_PART2_CATALOG_ID,
    subject: 'Update (Sep 24–29) continued',
    body: MAIL_UPDATE_2026_09_29_PART2_BODY,
    sentAt: '2026-09-29T00:00:01.000Z',
    attachments: [],
  },
  {
    id: MAIL_UPDATE_2026_10_06_CATALOG_ID,
    subject: 'Update October 5th',
    body: MAIL_UPDATE_2026_10_06_BODY,
    sentAt: '2026-10-06T00:00:00.000Z',
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
