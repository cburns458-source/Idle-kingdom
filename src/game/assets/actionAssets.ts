import { withAssetVersion } from './cacheBust'

/** Gathering action scene sprites keyed by Action ID. */

export const ACTION_ASSET_PATHS: Record<string, string> = {
  'ACN-0013': '/assets/actions/acn_hunt_duck.webp',
  'ACN-0014': '/assets/actions/acn_hunt_elk.webp',
  'ACN-0015': '/assets/actions/acn_hunt_butterfly.webp',
  'ACN-0016': '/assets/actions/acn_hunt_rabbit.webp',
  'ACN-0017': '/assets/actions/acn_hunt_pheasant.webp',
  'ACN-0018': '/assets/actions/acn_mine_copper.webp',
  'ACN-0019': '/assets/actions/acn_dig_clay.webp',
  'ACN-0020': '/assets/actions/acn_mine_tin.webp',
  'ACN-0021': '/assets/actions/acn_mine_coal.webp',
  'ACN-0022': '/assets/actions/acn_mine_iron.webp',
  'ACN-0026': '/assets/actions/acn_mine_titanium.webp',
  'ACN-0027': '/assets/actions/acn_mine_tungsten.webp',
  'ACN-0028': '/assets/actions/acn_delve_essence.webp',
  'ACN-0035': '/assets/actions/acn_harvest_potato.webp',
  'ACN-0036': '/assets/actions/acn_harvest_potato_golden.webp',
  'ACN-0046': '/assets/actions/acn_cut_cedar.webp',
  'ACN-0047': '/assets/actions/acn_cut_oak.webp',
  'ACN-0048': '/assets/actions/acn_cut_poplar.webp',
  'ACN-0049': '/assets/actions/acn_cut_maple.webp',
  'ACN-0050': '/assets/actions/acn_cut_mahogany.webp',
  'ACN-0051': '/assets/actions/acn_cut_ancient.webp',
  'ACN-0097': '/assets/actions/acn_mine_silver.webp',
  'ACN-0098': '/assets/actions/acn_mine_gold.webp',
  'ACN-0099': '/assets/actions/acn_catch_crawfish.webp',
  'ACN-0100': '/assets/actions/acn_catch_trout.webp',
  'ACN-0101': '/assets/actions/acn_catch_salmon.webp',
  'ACN-0102': '/assets/actions/acn_catch_tuna.webp',
  'ACN-0103': '/assets/actions/acn_catch_shark.webp',
  'ACN-0104': '/assets/actions/acn_catch_baby_giant_squid.webp',
  'ACN-0105': '/assets/actions/acn_gather_wild_roots.webp',
  'ACN-0106': '/assets/actions/acn_gather_fernleaf.webp',
  'ACN-0107': '/assets/actions/acn_gather_mosstole.webp',
  'ACN-0108': '/assets/actions/acn_gather_wild_berries.webp',
  'ACN-0109': '/assets/actions/acn_gather_augur_weed.webp',
  'ACN-0174': '/assets/actions/acn_gather_augur_weed.webp',
  'ACN-0110': '/assets/actions/acn_gather_moonblossom.webp',
  'ACN-0111': '/assets/actions/acn_gather_starroot.webp',
  'ACN-0112': '/assets/actions/acn_hunt_mountain_goat.webp',
  'ACN-0113': '/assets/actions/acn_hunt_great_stag.webp',
  'ACN-0114': '/assets/actions/acn_hunt_moonhorn_elk.webp',
  'ACN-0162': '/assets/actions/acn_gather_carrot.webp',
  'ACN-0163': '/assets/actions/acn_gather_grapes.webp',
  'ACN-0166': '/assets/actions/acn_mine_sapphire.webp',
  'ACN-0167': '/assets/actions/acn_mine_emerald.webp',
  'ACN-0168': '/assets/actions/acn_mine_ruby.webp',
}

const FALLBACK_ACTION_ASSET = '/assets/actions/acn_harvest_potato.webp'

export function actionAssetPath(actionId: string): string {
  return withAssetVersion(ACTION_ASSET_PATHS[actionId] ?? FALLBACK_ACTION_ASSET)
}
