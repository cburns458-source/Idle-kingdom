import type { AppearanceCategoryKey, AppearanceOptionRow, GameDatabase } from '../data/types'
import {
  APPEARANCE_CATEGORIES,
  DEFAULT_BEARD_ID,
  DEFAULT_EXPRESSION_ID,
  DEFAULT_GENDER_PRESENTATION_ID,
  DEFAULT_HAIRSTYLE_ID,
  DEFAULT_HAIR_COLOR_ID,
  DEFAULT_SKIN_TONE_ID,
  type AppearanceCategory,
  type PlayerAppearance,
  type PlayerSave,
} from '../save/types'

export { APPEARANCE_CATEGORIES }
export type { AppearanceCategory }

/** Save-schema camelCase category -> data-table snake_case Category value. */
const CATEGORY_DATA_KEY: Record<AppearanceCategory, AppearanceCategoryKey> = {
  skinTone: 'skin_tone',
  hairstyle: 'hairstyle',
  hairColor: 'hair_color',
  expression: 'expression',
  beard: 'beard',
  genderPresentation: 'gender_presentation',
}

const CATEGORY_LABELS: Record<AppearanceCategory, string> = {
  skinTone: 'Skin tone',
  hairstyle: 'Hairstyle',
  hairColor: 'Hair color',
  expression: 'Expression',
  beard: 'Beard',
  genderPresentation: 'Gender presentation',
}

export function appearanceCategoryLabel(category: AppearanceCategory): string {
  return CATEGORY_LABELS[category]
}

/** Options for one Appearance category, sorted for stable display order. */
export function appearanceOptions(db: GameDatabase, category: AppearanceCategory): AppearanceOptionRow[] {
  const key = CATEGORY_DATA_KEY[category]
  return db.AppearanceOptions.filter((row) => row.Category === key).sort(
    (a, b) => (a['Sort Order'] ?? 0) - (b['Sort Order'] ?? 0),
  )
}

export function appearanceOptionById(
  db: GameDatabase,
  optionId: string,
): AppearanceOptionRow | undefined {
  return db.AppearanceOptions.find((row) => row['Appearance Option ID'] === optionId)
}

export function isValidAppearanceOption(
  db: GameDatabase,
  category: AppearanceCategory,
  optionId: string,
): boolean {
  return appearanceOptions(db, category).some((row) => row['Appearance Option ID'] === optionId)
}

const FALLBACK_DEFAULTS: PlayerAppearance = {
  skinTone: DEFAULT_SKIN_TONE_ID,
  hairstyle: DEFAULT_HAIRSTYLE_ID,
  hairColor: DEFAULT_HAIR_COLOR_ID,
  expression: DEFAULT_EXPRESSION_ID,
  beard: DEFAULT_BEARD_ID,
  genderPresentation: DEFAULT_GENDER_PRESENTATION_ID,
}

/** First (by Sort Order) option per category, falling back to the baseline constants. */
export function defaultAppearance(db: GameDatabase): PlayerAppearance {
  const result = { ...FALLBACK_DEFAULTS }
  for (const category of APPEARANCE_CATEGORIES) {
    const first = appearanceOptions(db, category)[0]
    if (first) result[category] = first['Appearance Option ID']
  }
  return result
}

/**
 * One category swapped out, without a save to put it in.
 *
 * Unvalidated on purpose: character creation drives this from the sliders,
 * which only offer options the tables list.
 */
export function withAppearanceOption(
  appearance: PlayerAppearance,
  category: AppearanceCategory,
  optionId: string,
): PlayerAppearance {
  return { ...appearance, [category]: optionId }
}

/** Freely re-selectable at any time (skin tone, hairstyle, etc. carry no gameplay effect). */
export function setAppearanceOption(
  db: GameDatabase,
  save: PlayerSave,
  category: AppearanceCategory,
  optionId: string,
): PlayerSave | null {
  if (!isValidAppearanceOption(db, category, optionId)) return null
  return { ...save, appearance: withAppearanceOption(save.appearance, category, optionId) }
}
