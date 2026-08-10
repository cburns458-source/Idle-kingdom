import { withAssetVersion } from './cacheBust'

/** Gathering action scene sprites keyed by Action ID. */

export const ACTION_ASSET_PATHS: Record<string, string> = {
  'ACN-0013': '/assets/actions/acn_hunt_duck.png',
  'ACN-0014': '/assets/actions/acn_hunt_elk.png',
  'ACN-0015': '/assets/actions/acn_hunt_butterfly.png',
  'ACN-0016': '/assets/actions/acn_hunt_rabbit.png',
  'ACN-0017': '/assets/actions/acn_hunt_pheasant.png',
  'ACN-0018': '/assets/actions/acn_mine_copper.png',
  'ACN-0019': '/assets/actions/acn_dig_clay.png',
  'ACN-0020': '/assets/actions/acn_mine_tin.png',
  'ACN-0021': '/assets/actions/acn_mine_coal.png',
  'ACN-0022': '/assets/actions/acn_mine_iron.png',
  'ACN-0026': '/assets/actions/acn_mine_titanium.png',
  'ACN-0027': '/assets/actions/acn_mine_tungsten.png',
  'ACN-0028': '/assets/actions/acn_delve_essence.png',
  'ACN-0035': '/assets/actions/acn_harvest_potato.png',
  'ACN-0036': '/assets/actions/acn_harvest_potato_golden.png',
  'ACN-0046': '/assets/actions/acn_cut_cedar.png',
  'ACN-0047': '/assets/actions/acn_cut_oak.png',
  'ACN-0048': '/assets/actions/acn_cut_poplar.png',
  'ACN-0049': '/assets/actions/acn_cut_maple.png',
  'ACN-0050': '/assets/actions/acn_cut_mahogany.png',
  'ACN-0051': '/assets/actions/acn_cut_ancient.png',
  'ACN-0097': '/assets/actions/acn_mine_silver.png',
  'ACN-0098': '/assets/actions/acn_mine_gold.png',
  'ACN-0099': '/assets/actions/acn_catch_crawfish.png',
  'ACN-0100': '/assets/actions/acn_catch_trout.png',
  'ACN-0101': '/assets/actions/acn_catch_salmon.png',
  'ACN-0102': '/assets/actions/acn_catch_tuna.png',
  'ACN-0103': '/assets/actions/acn_catch_shark.png',
  'ACN-0104': '/assets/actions/acn_catch_baby_giant_squid.png',
  'ACN-0105': '/assets/actions/acn_gather_wild_roots.png',
  'ACN-0106': '/assets/actions/acn_gather_fernleaf.png',
  'ACN-0107': '/assets/actions/acn_gather_mosstole.png',
  'ACN-0108': '/assets/actions/acn_gather_wild_berries.png',
  'ACN-0109': '/assets/actions/acn_gather_augur_weed.png',
  'ACN-0110': '/assets/actions/acn_gather_moonblossom.png',
  'ACN-0111': '/assets/actions/acn_gather_starroot.png',
  'ACN-0112': '/assets/actions/acn_hunt_mountain_goat.png',
  'ACN-0113': '/assets/actions/acn_hunt_great_stag.png',
  'ACN-0114': '/assets/actions/acn_hunt_moonhorn_elk.png',
  'ACN-0162': '/assets/actions/acn_gather_carrot.png',
  'ACN-0163': '/assets/actions/acn_gather_grapes.png',
  'ACN-0164': '/assets/actions/acn_gather_herb_1.png',
  'ACN-0165': '/assets/actions/acn_gather_herb_2.png',
  'ACN-0166': '/assets/actions/acn_mine_sapphire.png',
  'ACN-0167': '/assets/actions/acn_mine_emerald.png',
  'ACN-0168': '/assets/actions/acn_mine_ruby.png',
}

const FALLBACK_ACTION_ASSET = '/assets/actions/acn_harvest_potato.png'

export function actionAssetPath(actionId: string): string {
  return withAssetVersion(ACTION_ASSET_PATHS[actionId] ?? FALLBACK_ACTION_ASSET)
}
