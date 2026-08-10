/** Primary currency item — never stays in the bag; converts to `save.gold`. */
export const GOLD_ITEM_ID = 'ITEM-0001'

export function isGoldCurrencyItem(itemId: string): boolean {
  return itemId === GOLD_ITEM_ID
}
