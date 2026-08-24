import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

/// Fallback currency item when Config has no `currency_item_id`.
const String goldItemId = 'ITEM-0001';

/// Gold item ID from Config, or [goldItemId] when the row is missing.
String currencyItemId([GameDatabase? db]) {
  if (db == null) return goldItemId;
  final raw = db.config.firstWhereOrNull((row) => row.raw['Key'] == 'currency_item_id')?.raw['Value'];
  return raw is String && raw.isNotEmpty ? raw : goldItemId;
}

/// Primary currency item — never stays in the bag; converts to `save.gold`.
bool isGoldCurrencyItem(String itemId, [GameDatabase? db]) => itemId == currencyItemId(db);
