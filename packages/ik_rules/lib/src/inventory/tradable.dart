import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../cosmetics/cosmetics.dart';
import '../js_compat.dart';
import 'gold.dart';

bool _itemHasTag(ItemRow? item, String tag) {
  return jsString(item?.raw['Functional / Source Tags'] ?? '')
      .split(RegExp(r'[;,]'))
      .map((part) => part.trim().toLowerCase())
      .contains(tag);
}

/// Default tradable. Untradable tags, cosmetics, and gold cannot be sold or destroyed.
bool itemIsTradable(GameDatabase db, String itemId) {
  if (itemId == currencyItemId(db)) return false;
  final item = db.items.firstWhereOrNull((row) => row.itemId == itemId);
  if (item == null) return true;
  if ((item.category ?? '').toLowerCase() == 'cosmetic') return false;
  if (cosmeticByItemId(db, itemId) != null) return false;
  if (_itemHasTag(item, 'untradable')) return false;
  return true;
}
