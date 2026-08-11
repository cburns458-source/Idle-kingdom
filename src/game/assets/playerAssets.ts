import { withAssetVersion } from './cacheBust'
import {
  DEFAULT_GENDER_PRESENTATION_ID,
  type PlayerAppearance,
  type PlayerSave,
} from '../save/types'

/** Feminine presentation — original adventurer sprite. */
export const PLAYER_GENDER_FEMININE_PATH = '/assets/player/player_gender_feminine.png'
export const PLAYER_GENDER_ANDROGYNOUS_PATH = '/assets/player/player_gender_androgynous.png'
export const PLAYER_GENDER_MASCULINE_PATH = '/assets/player/player_gender_masculine.png'

/** @deprecated Prefer {@link playerPortraitAssetPath}. Kept for older imports. */
export const PLAYER_COMBAT_ASSET_PATH = PLAYER_GENDER_FEMININE_PATH

const GENDER_PRESENTATION_ASSET: Record<string, string> = {
  'APR-0017': PLAYER_GENDER_FEMININE_PATH, // Feminine
  'APR-0019': PLAYER_GENDER_ANDROGYNOUS_PATH, // Androgynous
  'APR-0018': PLAYER_GENDER_MASCULINE_PATH, // Masculine
}

export function genderPresentationAssetPath(
  genderPresentationId: string | null | undefined,
): string {
  const path =
    (genderPresentationId && GENDER_PRESENTATION_ASSET[genderPresentationId]) ||
    GENDER_PRESENTATION_ASSET[DEFAULT_GENDER_PRESENTATION_ID] ||
    PLAYER_GENDER_FEMININE_PATH
  return withAssetVersion(path)
}

export function playerPortraitAssetPath(
  appearanceOrSave: PlayerAppearance | PlayerSave | null | undefined,
): string {
  if (!appearanceOrSave) return genderPresentationAssetPath(DEFAULT_GENDER_PRESENTATION_ID)
  const appearance =
    'appearance' in appearanceOrSave ? appearanceOrSave.appearance : appearanceOrSave
  return genderPresentationAssetPath(appearance?.genderPresentation)
}

/** Combat / gathering / production action sprite (same art as portrait for now). */
export function playerCombatAssetPath(
  appearanceOrSave?: PlayerAppearance | PlayerSave | null,
): string {
  return playerPortraitAssetPath(appearanceOrSave)
}
