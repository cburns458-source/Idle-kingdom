import { withAssetVersion } from './cacheBust'

/** Transparent workstation art for Standard Production stations. */
export const WORKSTATION_ASSET_PATHS: Record<string, string> = {
  // Kitchen / Cooking
  'FAC-0001': '/assets/workstations/ws_cooking_stove.png',
  // Crafting Workshop
  'FAC-0003': '/assets/workstations/ws_crafting_bench.png',
  // Metallurgy Furnace
  'FAC-0004': '/assets/workstations/ws_metallurgy_furnace.png',
  // Apothecary / Alchemy
  'FAC-0006': '/assets/workstations/ws_alchemy_apothecary.png',
}

export function workstationAssetPath(facilityId: string | null | undefined): string {
  if (!facilityId) return withAssetVersion('/assets/workstations/ws_crafting_bench.png')
  return withAssetVersion(
    WORKSTATION_ASSET_PATHS[facilityId] ?? '/assets/workstations/ws_crafting_bench.png',
  )
}
