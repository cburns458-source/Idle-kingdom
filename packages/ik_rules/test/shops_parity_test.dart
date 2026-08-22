import 'package:collection/collection.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

List<String> _stringList(ParityFixture fixture, String key) {
  return fixture.inputField<List<Object?>>(key).map((value) => value! as String).toList();
}

Map<String, Object?> _equipJson(EquipResult result) {
  return result.ok
      ? <String, Object?>{'ok': true, 'save': result.save!.toJson()}
      : <String, Object?>{'ok': false, 'reason': result.reason};
}

ShopOffer _offerOf(ParityFixture fixture) {
  final raw = asJsonMap(fixture.inputMap['offer']);
  List<ShopOfferLine> lines(String key) {
    return (raw[key]! as List<Object?>)
        .map((entry) => asJsonMap(entry))
        .map(
          (line) =>
              ShopOfferLine(itemId: line['itemId']! as String, quantity: line['quantity']! as num),
        )
        .toList();
  }

  return ShopOffer(buys: lines('buys'), sells: lines('sells'));
}

void main() {
  group('shop row parity', () {
    for (final fixture in loadParityFixtures('shops/rows')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final priced = const <String>[
          'ITEM-0001',
          'ITEM-0011',
          'ITEM-0003',
          'ITEM-0025',
          'ITEM-0100',
          'ITEM-9999',
        ];
        final shops = db.shops.map((shop) {
          final stock = shopStockEntries(shop);
          return <String, Object?>{
            'shopId': shop.shopId,
            'stock': stock.map((entry) => entry.toJson()).toList(),
            'visibleStock': shopStockForPlayer(
              db,
              createNewSave(db, 0),
              shop,
            ).map((entry) => entry.toJson()).toList(),
            'buyPrices': priced.map((itemId) => playerBuyPrice(db, shop, itemId)).toList(),
            'sellPrices': priced.map((itemId) => playerSellPrice(db, shop, itemId)).toList(),
            'sellsFirstStock': shopSellsItem(
              shop,
              stock.isEmpty ? 'ITEM-9999' : stock.first.itemId,
            ),
            'sellsUnstocked': shopSellsItem(shop, 'ITEM-9999'),
          };
        }).toList();
        expect(
          checkParity(fixture, {
            'currencyItemId': currencyItemId(db),
            'shops': shops,
            'lookups': _stringList(
              fixture,
              'shopIds',
            ).map((shopId) => getShop(db, shopId)?.shopId).toList(),
            'baseValues': priced
                .map(
                  (itemId) =>
                      baseSellValue(db.items.firstWhereOrNull((row) => row.itemId == itemId)),
                )
                .toList(),
            'ore': db.items.where(isOreItem).map((item) => item.itemId).toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('shop access parity', () {
    for (final fixture in loadParityFixtures('shops/access')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final byLocation = _stringList(fixture, 'locations')
            .map(
              (locationId) => <String, Object?>{
                'locationId': locationId,
                'shops': shopsAtLocation(db, locationId)
                    .map(
                      (shop) => <String, Object?>{
                        'shopId': shop.shopId,
                        'access': canAccessShop(db, save, shop).toJson(),
                      },
                    )
                    .toList(),
              },
            )
            .toList();
        expect(checkParity(fixture, {'byLocation': byLocation}), isNull);
      });
    }
  });

  group('shop quantity parity', () {
    for (final fixture in loadParityFixtures('shops/quantity')) {
      test(fixture.name, () {
        final results = fixture
            .inputField<List<Object?>>('cases')
            .map((entry) => asJsonMap(entry))
            .map(
              (entry) => parseShopQuantity(entry['raw']! as String, entry['max'] as num?).toJson(),
            )
            .toList();
        expect(checkParity(fixture, {'results': results}), isNull);
      });
    }
  });

  group('shop offer parity', () {
    for (final fixture in loadParityFixtures('shops/offer')) {
      test(fixture.name, () {
        final result = confirmShopOffer(
          databaseOf(fixture),
          saveOf(fixture),
          fixture.inputField<String>('shopId'),
          _offerOf(fixture),
        );
        expect(checkParity(fixture, result.toJson()), isNull);
      });
    }
  });

  group('sell price parity', () {
    for (final fixture in loadParityFixtures('shops/sell-price')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final itemIds = _stringList(fixture, 'itemIds');
        expect(
          checkParity(fixture, {
            'field': itemIds.map((itemId) => fieldSellPrice(db, itemId)).toList(),
            'atLocation': itemIds
                .map((itemId) => sellPriceAtLocation(db, save, itemId)?.toJson())
                .toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('sell bag parity', () {
    for (final fixture in loadParityFixtures('shops/sell-bag')) {
      test(fixture.name, () {
        final result = sellInventoryIndexes(
          databaseOf(fixture),
          saveOf(fixture),
          numListOf(fixture, 'indexes'),
        );
        expect(checkParity(fixture, result.toJson()), isNull);
      });
    }
  });

  group('wardrobe parity', () {
    for (final fixture in loadParityFixtures('cosmetics/wardrobe')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final base = saveOf(fixture);
        final first = grantCosmetic(base, 'COS-0001');
        final second = grantCosmetic(first.save, 'COS-9999');
        final again = grantCosmetic(second.save, 'COS-0001');
        final equipped = equipCosmetic(db, second.save, 'CSLOT-0001', 'COS-0001');
        final worn = equipped.ok ? equipped.save! : second.save;
        expect(
          checkParity(fixture, {
            'first': <String, Object?>{
              'save': first.save.toJson(),
              'granted': first.granted,
              'isFirstEver': first.isFirstEver,
            },
            'second': <String, Object?>{
              'granted': second.granted,
              'isFirstEver': second.isFirstEver,
            },
            'again': <String, Object?>{'granted': again.granted, 'isFirstEver': again.isFirstEver},
            'equipped': _equipJson(equipped),
            'unknownCosmetic': _equipJson(equipCosmetic(db, second.save, 'CSLOT-0001', 'COS-9999')),
            'wrongSlot': _equipJson(equipCosmetic(db, second.save, 'CSLOT-0002', 'COS-0001')),
            'locked': _equipJson(equipCosmetic(db, base, 'CSLOT-0001', 'COS-0001')),
            'unequipped': _equipJson(equipCosmetic(db, worn, 'CSLOT-0001', null)),
            'unlocked': <bool>[
              isCosmeticUnlocked(first.save, 'COS-0001'),
              isCosmeticUnlocked(base, 'COS-0001'),
            ],
            'equippedId': <String?>[
              equippedCosmeticId(equipped.ok ? worn : base, 'CSLOT-0001'),
              equippedCosmeticId(base, 'CSLOT-0001'),
            ],
          }),
          isNull,
        );
      });
    }
  });

  group('skill menu parity', () {
    for (final fixture in loadParityFixtures('skills/menu')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final bySkill = _stringList(fixture, 'skillIds')
            .map(
              (skillId) => <String, Object?>{
                'skillId': skillId,
                'actions': actionsForSkill(db, skillId).map((item) => item.toJson()).toList(),
                'projects': projectsForSkill(db, skillId).map((item) => item.toJson()).toList(),
                'combined': skillMenuEntries(db, skillId).map((item) => item.id).toList(),
                'display': skillMenuDisplayEntries(
                  db,
                  skillId,
                ).map((item) => item.toJson()).toList(),
                'view': skillMenuView(db, skillId).toJson(),
              },
            )
            .toList();
        expect(checkParity(fixture, {'bySkill': bySkill}), isNull);
      });
    }
  });
}
