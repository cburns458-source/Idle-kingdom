/** Stable enemy sprite paths keyed by Enemy ID / internal key. */

export const ENEMY_ASSET_PATHS: Record<string, string> = {
  'ENM-0001': '/assets/enemies/enm_cow.png',
  'ENM-0002': '/assets/enemies/enm_bull.png',
  'ENM-0003': '/assets/enemies/enm_goblin_scout.png',
  'ENM-0004': '/assets/enemies/enm_goblin_chief.png',
  'ENM-0005': '/assets/enemies/enm_pirate.png',
  'ENM-0007': '/assets/enemies/enm_rock_troll.png',
  'ENM-0008': '/assets/enemies/enm_skeleton.png',
  'ENM-0009': '/assets/enemies/enm_zombie.png',
  'ENM-0010': '/assets/enemies/enm_wild_boar.png',
  'ENM-0011': '/assets/enemies/enm_castle_guard.png',
  'ENM-0016': '/assets/enemies/enm_goblin_warrior.png',
  'ENM-0017': '/assets/enemies/enm_rabbit_buck.png',
}

export function enemyAssetPath(enemyId: string): string {
  return ENEMY_ASSET_PATHS[enemyId] ?? '/assets/enemies/enm_cow.png'
}
