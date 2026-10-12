import 'dart:convert';

import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:test/test.dart';

const String _machete = 'ITEM-0406';
const String _excavatorsPickaxe = 'ITEM-0313';
const String _stolenCoinPurse = 'ITEM-0299';
const String _beggarsHood = 'ITEM-0300';
const String _goldenSpud = 'ITEM-0026';
const String _chefsHat = 'ITEM-0165';
const String _pirateInsignia = 'ITEM-0288';

/// A private copy of the real database, safe to edit.
Map<String, Object?> _rawCopy() =>
    jsonDecode(jsonEncode(contentDatabaseJson())) as Map<String, Object?>;

Map<String, Object?> _itemRow(Map<String, Object?> raw, String itemId) =>
    (raw['Items']! as List<Object?>).cast<Map<String, Object?>>().firstWhere(
      (row) => row['Item ID'] == itemId,
    );

ItemRow _item(GameDatabase db, String itemId) => db.items.firstWhere((row) => row.itemId == itemId);

void main() {
  group('the Tradeable column', () {
    test('marks the four quest-only rewards untradeable and nothing else', () {
      final db = assertGameDatabaseShape(_rawCopy());
      final untradeable = db.items.where((item) => !item.isTradeable).map((item) => item.itemId);
      expect(untradeable.toSet(), <String>{
        _machete,
        _excavatorsPickaxe,
        _stolenCoinPurse,
        _beggarsHood,
      });
      for (final itemId in <String>[_goldenSpud, _chefsHat, _pirateInsignia]) {
        expect(_item(db, itemId).isTradeable, isTrue, reason: itemId);
      }
    });

    test('parses as a boolean, and a missing or blank cell means true', () {
      final raw = _rawCopy();
      _itemRow(raw, _goldenSpud).remove('Tradeable');
      _itemRow(raw, _chefsHat)['Tradeable'] = null;
      _itemRow(raw, _pirateInsignia)['Tradeable'] = '';
      final db = assertGameDatabaseShape(raw);

      expect(_item(db, _machete).tradeable, isFalse);
      expect(_item(db, _machete).isTradeable, isFalse);
      expect(_item(db, _goldenSpud).tradeable, isNull);
      expect(_item(db, _goldenSpud).isTradeable, isTrue);
      expect(_item(db, _chefsHat).isTradeable, isTrue);
      expect(_item(db, _pirateInsignia).isTradeable, isTrue);
      expect(validateTradeability(db), isEmpty);
    });
  });

  group('validateTradeability', () {
    test('passes on the real database', () {
      expect(validateTradeability(assertGameDatabaseShape(_rawCopy())), isEmpty);
    });

    test('sees the quest rewards, the quest drop, and the quest cosmetic', () {
      final sources = scanItemSources(assertGameDatabaseShape(_rawCopy()));
      for (final itemId in <String>[_machete, _excavatorsPickaxe, _stolenCoinPurse, _beggarsHood]) {
        expect(sources.isQuestOnly(itemId), isTrue, reason: itemId);
      }
      // Quest rewards that can also be harvested, bought, or dropped.
      expect(sources.isQuestOnly(_goldenSpud), isFalse);
      expect(sources.isQuestOnly(_chefsHat), isFalse);
      expect(sources.hasOtherSource(_pirateInsignia), isTrue);
    });

    test('errors on a quest-only item left tradeable', () {
      final raw = _rawCopy();
      _itemRow(raw, _machete)['Tradeable'] = true;
      final issues = validateTradeability(assertGameDatabaseShape(raw));
      expect(issues, hasLength(1));
      expect(issues.single.isError, isTrue);
      expect(issues.single.id, _machete);
      expect(issues.single.message, contains('QST-0010'));
    });

    test('treats a missing cell on a quest-only item as tradeable, so errors', () {
      final raw = _rawCopy();
      _itemRow(raw, _excavatorsPickaxe).remove('Tradeable');
      final issues = validateTradeability(assertGameDatabaseShape(raw));
      expect(issues.map((issue) => (issue.id, issue.isError)), <(String?, bool)>[
        (_excavatorsPickaxe, true),
      ]);
    });

    test('lets a code-sourced item through when it is on the override list', () {
      final raw = _rawCopy();
      _itemRow(raw, _machete)['Tradeable'] = true;
      final db = assertGameDatabaseShape(raw);
      expect(validateTradeability(db, codeSourcedItemIds: <String>{_machete}), isEmpty);
    });

    test('warns when an untradeable item can be had some other way', () {
      final raw = _rawCopy();
      _itemRow(raw, _goldenSpud)['Tradeable'] = false;
      final issues = validateTradeability(assertGameDatabaseShape(raw));
      expect(issues, hasLength(1));
      expect(issues.single.severity, IssueSeverity.warning);
      expect(issues.single.id, _goldenSpud);
    });

    test('errors on a cell that is not a boolean', () {
      final raw = _rawCopy();
      _itemRow(raw, _goldenSpud)['Tradeable'] = 'no';
      final issues = validateTradeability(assertGameDatabaseShape(raw));
      expect(issues.single.isError, isTrue);
      expect(issues.single.message, 'Tradeable must be true, false, or blank');
    });
  });
}
