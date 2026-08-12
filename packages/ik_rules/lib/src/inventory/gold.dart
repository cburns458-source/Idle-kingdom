/// Primary currency item; never stays in the bag, converts to `save.gold`.
const String goldItemId = 'ITEM-0001';

bool isGoldCurrencyItem(String itemId) => itemId == goldItemId;
