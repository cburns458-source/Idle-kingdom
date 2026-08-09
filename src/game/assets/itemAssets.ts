/** Known generated item icon paths keyed by Item ID. */

export const ITEM_ASSET_PATHS: Record<string, string> = {
  'ITEM-0108': '/assets/items/item_net.png',
  'ITEM-0058': '/assets/items/item_baked_potato.png',
  'ITEM-0111': '/assets/items/item_copper_pickaxe.png',
}

export function itemAssetPath(itemId: string): string | null {
  return ITEM_ASSET_PATHS[itemId] ?? null
}
