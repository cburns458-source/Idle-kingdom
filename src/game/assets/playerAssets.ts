import { withAssetVersion } from './cacheBust'

/** Temporary player combat sprite (old-school RPG pixel art). */
export const PLAYER_COMBAT_ASSET_PATH = '/assets/player/player_adventurer_temp.png'

export function playerCombatAssetPath(): string {
  return withAssetVersion(PLAYER_COMBAT_ASSET_PATH)
}
