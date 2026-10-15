import type { GameDatabase } from '../data/types'
import type { PlayerSave } from './types'
import { STARTER_TITLE_COSMETIC_ID, TITLE_COSMETIC_SLOT_ID } from './types'

/** Which side of the name a title is written on. */
export type TitlePlacement = 'prefix' | 'suffix'

export interface PlayerTitle {
  text: string
  placement: TitlePlacement
}

/** Held from the first step until the first defeat. */
export const UNDYING_TITLE: PlayerTitle = { text: 'The Undying', placement: 'suffix' }

/** Equipped title text for chat, or null when the save holds none. */
export function chatTitleForSave(save: PlayerSave, db?: GameDatabase): string | null {
  return titleForSave(save, db)?.text ?? null
}

/**
 * Equipped title text from a stored save payload.
 *
 * Missing or unreadable payloads are untitled. A payload that is a save — even
 * an older one that never wrote the title slot — uses the same rules as
 * [titleForSave].
 */
export function chatTitleFromSavePayload(payload: unknown, db?: GameDatabase): string | null {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return null
  return chatTitleForSave(payload as PlayerSave, db)
}

/** The title a save has earned, or null when it holds none. */
export function titleForSave(save: PlayerSave, db?: GameDatabase): PlayerTitle | null {
  const equipped = save.cosmetics?.equipped
  const equippedId =
    equipped && Object.prototype.hasOwnProperty.call(equipped, TITLE_COSMETIC_SLOT_ID)
      ? equipped[TITLE_COSMETIC_SLOT_ID]
      : undefined
  if (equippedId && equippedId !== STARTER_TITLE_COSMETIC_ID) {
    // Faith (and later) titles stay visible after the first death; Undying does not.
    if (!db) return null
    const cosmetic = db.Cosmetics.find((row) => row['Cosmetic ID'] === equippedId)
    const itemId = cosmetic?.['Item ID']
    const text =
      typeof itemId === 'string'
        ? db.Items.find((row) => row['Item ID'] === itemId)?.['Display Name']
        : null
    return typeof text === 'string' && text.length > 0
      ? { text, placement: 'suffix' }
      : null
  }
  if (save.hasEverDied) return null
  if (equipped && Object.prototype.hasOwnProperty.call(equipped, TITLE_COSMETIC_SLOT_ID)) {
    return equipped[TITLE_COSMETIC_SLOT_ID] === STARTER_TITLE_COSMETIC_ID ? UNDYING_TITLE : null
  }
  // Older saves never wrote the title slot; they still wear The Undying.
  return UNDYING_TITLE
}

export function nameWithTitle(name: string, title: PlayerTitle | null): string {
  if (!title) return name
  return title.placement === 'prefix' ? `${title.text} ${name}` : `${name} ${title.text}`
}

/**
 * How a character is introduced: their name, with whatever title they hold.
 *
 * Falls back to [fallback] for a save that has not been named yet, which keeps
 * a title off an anonymous character.
 */
export function displayNameForSave(save: PlayerSave, fallback: string, db?: GameDatabase): string {
  const name = save.characterName
  if (!name) return fallback
  return nameWithTitle(name, titleForSave(save, db))
}
