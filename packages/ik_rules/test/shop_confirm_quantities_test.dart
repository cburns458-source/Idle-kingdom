import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

/// Parity with src/game/shops/shopConfirmQuantities.test.ts.
void main() {
  late GameDatabase db;
  const reason = 'Offer quantities must be at least 1.';
  const now = 1767225600000;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  PlayerSave shopSave() => createNewSave(db, now).copyWith(
    currentLocationId: 'LOC-0024',
    gold: 1000,
    inventory: const <InventoryStack>[InventoryStack(itemId: 'ITEM-0025', quantity: 1)],
  );

  final invalid = <String, num>{
    'NaN': double.nan,
    'Infinity': double.infinity,
    '-Infinity': double.negativeInfinity,
    'fraction': 1.5,
    'small fraction': 0.5,
    'zero': 0,
    'negative': -1,
    'above MAX_SAFE_INTEGER': 9007199254740992,
  };

  for (final entry in invalid.entries) {
    for (final side in <String>['buys', 'sells']) {
      test('rejects ${entry.key} on $side and changes nothing', () {
        final save = shopSave();
        final before = save.toJson().toString();
        final line = ShopOfferLine(
          itemId: side == 'buys' ? 'ITEM-0102' : 'ITEM-0025',
          quantity: entry.value,
        );
        final offer = side == 'buys'
            ? ShopOffer(buys: <ShopOfferLine>[line])
            : ShopOffer(sells: <ShopOfferLine>[line]);
        final result = confirmShopOffer(db, save, 'SHP-0001', offer, nowMs: now);
        expect(result.ok, isFalse);
        expect(result.reason, reason);
        expect(save.toJson().toString(), before);
        expect(isValidOfferQuantity(entry.value), isFalse);
      });
    }
  }

  test('rejects non-numbers', () {
    expect(isValidOfferQuantity('1'), isFalse);
    expect(isValidOfferQuantity(null), isFalse);
  });

  test('accepts MAX_SAFE_INTEGER and 1 as quantity shapes', () {
    expect(isValidOfferQuantity(9007199254740991), isTrue);
    expect(isValidOfferQuantity(1), isTrue);
    expect(isValidOfferQuantity(2.0), isTrue);
  });

  test('accepts a valid whole-number buy', () {
    final save = shopSave();
    final result = confirmShopOffer(
      db,
      save,
      'SHP-0001',
      const ShopOffer(buys: <ShopOfferLine>[ShopOfferLine(itemId: 'ITEM-0102', quantity: 1)]),
      nowMs: now,
    );
    expect(result.ok, isTrue);
    expect(result.save!.inventory.any((s) => s.itemId == 'ITEM-0102'), isTrue);
    expect(result.save!.gold, lessThan(save.gold));
  });
}
