import { withAssetVersion } from './cacheBust'
import {
  DEFAULT_GENDER_PRESENTATION_ID,
  type PlayerAppearance,
  type PlayerSave,
} from '../save/types'

const RACE_PLAYER_KEYS: Record<string, string> = {
  'RACE-0001': 'human',
  'RACE-0002': 'wood_elf',
  'RACE-0003': 'high_elf',
  'RACE-0004': 'orc',
  'RACE-0005': 'goblin',
  'RACE-0006': 'dwarf',
  'RACE-0007': 'halfling',
}

/** @deprecated Prefer {@link playerPortraitAssetPath}. Kept for older imports. */
export const PLAYER_COMBAT_ASSET_PATH = '/assets/player/player_human_feminine.png'

/** Feminine and androgynous share one plate per race; masculine has its own. */
export function playerArtStem(
  raceId: string | null | undefined,
  genderPresentationId: string | null | undefined,
): string {
  const raceKey = (raceId && RACE_PLAYER_KEYS[raceId]) || 'human'
  const masculine = genderPresentationId === 'APR-0018'
  const bucket = masculine ? 'masculine' : 'feminine'
  return `player_${raceKey}_${bucket}`
}

/** @deprecated Use {@link playerPortraitAssetPath} with a save race id. */
export function genderPresentationAssetPath(
  genderPresentationId: string | null | undefined,
): string {
  return withAssetVersion(`/assets/player/${playerArtStem(null, genderPresentationId)}.png`)
}

export function playerPortraitAssetPath(
  appearanceOrSave: PlayerAppearance | PlayerSave | null | undefined,
): string {
  if (!appearanceOrSave) {
    return withAssetVersion(`/assets/player/${playerArtStem(null, DEFAULT_GENDER_PRESENTATION_ID)}.png`)
  }
  const raceId = 'raceId' in appearanceOrSave ? appearanceOrSave.raceId : null
  const appearance =
    'appearance' in appearanceOrSave ? appearanceOrSave.appearance : appearanceOrSave
  return withAssetVersion(
    `/assets/player/${playerArtStem(raceId, appearance?.genderPresentation)}.png`,
  )
}

/** Combat / gathering / production action sprite (same art as portrait for now). */
export function playerCombatAssetPath(
  appearanceOrSave?: PlayerAppearance | PlayerSave | null,
): string {
  return playerPortraitAssetPath(appearanceOrSave)
}
