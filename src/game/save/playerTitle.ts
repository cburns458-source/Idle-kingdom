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

/** The title a save has earned, or null when it holds none. */
export function titleForSave(save: PlayerSave): PlayerTitle | null {
  if (save.hasEverDied) return null
  const equipped = save.cosmetics?.equipped
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
export function displayNameForSave(save: PlayerSave, fallback: string): string {
  const name = save.characterName
  if (!name) return fallback
  return nameWithTitle(name, titleForSave(save))
}
