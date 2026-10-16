// Equipped chat title from a stored save payload.
//
// The client's copy lives in `src/game/save/playerTitle.ts` (`titleForSave` /
// `chatTitleFromSavePayload`). This file is the send-chat function's half: it
// reads only the cosmetics slot and death flag, and it never takes a title the
// client sent.

const TITLE_COSMETIC_SLOT_ID = 'CSLOT-0003'
const STARTER_TITLE_COSMETIC_ID = 'COS-0003'
const UNDYING_TITLE_TEXT = 'The Undying'

export type TitleCatalog = {
  Cosmetics?: Array<Record<string, unknown>>
  Items?: Array<Record<string, unknown>>
}

/** Equipped title text, or null when the payload holds none. */
export function chatTitleFromSavePayload(
  payload: unknown,
  catalog?: TitleCatalog,
): string | null {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return null
  const save = payload as {
    cosmetics?: { equipped?: Record<string, unknown> }
    hasEverDied?: unknown
  }
  const equipped = save.cosmetics?.equipped
  const slotWritten = !!equipped && Object.prototype.hasOwnProperty.call(equipped, TITLE_COSMETIC_SLOT_ID)
  const equippedId = slotWritten ? equipped![TITLE_COSMETIC_SLOT_ID] : undefined
  const equippedStr = typeof equippedId === 'string' && equippedId.length > 0 ? equippedId : null
  if (equippedStr && equippedStr !== STARTER_TITLE_COSMETIC_ID) {
    if (!catalog) return null
    return titleTextForCosmetic(equippedStr, catalog)
  }
  if (save.hasEverDied === true) return null
  if (slotWritten) {
    return equippedStr === STARTER_TITLE_COSMETIC_ID ? UNDYING_TITLE_TEXT : null
  }
  // Older saves never wrote the title slot; they still wear The Undying.
  return UNDYING_TITLE_TEXT
}

function titleTextForCosmetic(cosmeticId: string, catalog: TitleCatalog): string | null {
  const cosmetic = (catalog.Cosmetics ?? []).find((row) => row['Cosmetic ID'] === cosmeticId)
  const itemId = cosmetic?.['Item ID']
  if (typeof itemId !== 'string') return null
  // Faith titles (cosmetic_faith_*_title) set Title Placement = prefix; chat
  // stores the display name and the client writes it before the speaker's name.
  const text = (catalog.Items ?? []).find((row) => row['Item ID'] === itemId)?.['Display Name']
  return typeof text === 'string' && text.length > 0 ? text : null
}
