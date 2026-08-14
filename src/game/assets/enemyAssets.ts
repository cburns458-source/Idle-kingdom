import { withAssetVersion } from './cacheBust'

/** Stable enemy sprite paths keyed by Enemy ID / internal key. */

export const ENEMY_ASSET_PATHS: Record<string, string> = {
  'ENM-0001': '/assets/enemies/enm_cow.webp',
  'ENM-0002': '/assets/enemies/enm_bull.webp',
  'ENM-0003': '/assets/enemies/enm_goblin_scout.webp',
  'ENM-0004': '/assets/enemies/enm_goblin_chief.webp',
  'ENM-0005': '/assets/enemies/enm_pirate.webp',
  'ENM-0006': '/assets/enemies/enm_dragon.webp',
  'ENM-0007': '/assets/enemies/enm_rock_troll.webp',
  'ENM-0008': '/assets/enemies/enm_skeleton.webp',
  'ENM-0009': '/assets/enemies/enm_zombie.webp',
  'ENM-0010': '/assets/enemies/enm_wild_boar.webp',
  'ENM-0011': '/assets/enemies/enm_castle_guard.webp',
  'ENM-0012': '/assets/enemies/enm_ent.webp',
  'ENM-0013': '/assets/enemies/enm_ancient_ent.webp',
  'ENM-0014': '/assets/enemies/enm_corrupted_ent.webp',
  'ENM-0015': '/assets/enemies/enm_shade_goblin.webp',
  'ENM-0016': '/assets/enemies/enm_goblin_warrior.webp',
  'ENM-0017': '/assets/enemies/enm_rabbit_buck.webp',
  'ENM-0018': '/assets/enemies/enm_elder_rock_troll.webp',
  'ENM-0019': '/assets/enemies/enm_castle_guard.webp',
}

export function enemyAssetPath(enemyId: string): string {
  return withAssetVersion(ENEMY_ASSET_PATHS[enemyId] ?? '/assets/enemies/enm_cow.webp')
}
