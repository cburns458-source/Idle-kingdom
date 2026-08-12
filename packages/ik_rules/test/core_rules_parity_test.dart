import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  group('save round trip parity', () {
    for (final fixture in loadParityFixtures('save/roundtrip')) {
      test(fixture.name, () {
        expect(checkParity(fixture, {'save': saveOf(fixture).toJson()}), isNull);
      });
    }
  });

  group('inventory capacity parity', () {
    for (final fixture in loadParityFixtures('inventory/capacity')) {
      test(fixture.name, () {
        final save = saveOf(fixture);
        final itemId = fixture.inputField<String>('itemId');
        final enchantmentId = fixture.inputMap['enchantmentId'] as String?;
        final favorite = fixture.inputField<bool>('favorite');
        expect(
          checkParity(fixture, {
            'slotCount': inventorySlotCount(save),
            'slotsFree': inventorySlotsFree(save),
            'maxAddable': maxAddableQuantity(save, itemId, enchantmentId, favorite),
            'canFitOne': canFitItemQuantity(save, itemId, 1, enchantmentId, favorite),
            'canFitZero': canFitItemQuantity(save, itemId, 0, enchantmentId, favorite),
            'canFitMany': canFitItemQuantity(save, itemId, 1000, enchantmentId, favorite),
          }),
          isNull,
        );
      });
    }
  });

  group('inventory add parity', () {
    for (final fixture in loadParityFixtures('inventory/add')) {
      test(fixture.name, () {
        final itemId = fixture.inputField<String>('itemId');
        final quantity = fixture.inputField<num>('quantity');
        final enchantmentId = fixture.inputMap['enchantmentId'] as String?;
        final favorite = fixture.inputField<bool>('favorite');

        final partial = addItemsToInventory(
          saveOf(fixture),
          itemId,
          quantity,
          enchantmentId,
          favorite,
        );
        final exact = addItemToInventoryExact(
          saveOf(fixture),
          itemId,
          quantity,
          enchantmentId,
          favorite,
        );

        expect(
          checkParity(fixture, {
            'added': partial.added,
            'save': partial.save.toJson(),
            'exact': exact.ok
                ? <String, Object?>{'ok': true, 'save': exact.save!.toJson()}
                : <String, Object?>{'ok': false, 'reason': exact.reason},
          }),
          isNull,
        );
      });
    }
  });

  group('inventory destroy parity', () {
    for (final fixture in loadParityFixtures('inventory/destroy')) {
      test(fixture.name, () {
        final indexes = numListOf(fixture, 'indexes');
        final result = destroyInventoryIndexes(saveOf(fixture), indexes);
        expect(checkParity(fixture, {'save': result.toJson()}), isNull);
      });
    }
  });

  group('inventory favorites parity', () {
    for (final fixture in loadParityFixtures('inventory/favorites')) {
      test(fixture.name, () {
        final save = saveOf(fixture);
        final actual = fixture.name == 'sort-favorites-first'
            ? <String, Object?>{'save': sortInventoryFavoritesFirst(save).toJson()}
            : <String, Object?>{
                'save': toggleInventoryFavorite(
                  save,
                  fixture.inputField<num>('index').toInt(),
                )?.toJson(),
              };
        expect(checkParity(fixture, actual), isNull);
      });
    }
  });

  group('xp curve parity', () {
    for (final fixture in loadParityFixtures('xp/level-for-total')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final totals = numListOf(fixture, 'totals');
        expect(
          checkParity(fixture, {
            'levels': totals.map((total) => levelForTotalXp(db, total)).toList(),
          }),
          isNull,
        );
      });
    }

    for (final fixture in loadParityFixtures('xp/progress')) {
      test(fixture.name, () {
        final source = databaseOf(fixture);
        final db = fixture.name == 'launch-view' ? filterLaunchContent(source) : source;
        final totals = numListOf(fixture, 'totals');
        expect(
          checkParity(fixture, {
            'progress': totals.map((total) => skillXpProgress(db, total).toJson()).toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('applyXp parity', () {
    for (final fixture in loadParityFixtures('xp/apply')) {
      test(fixture.name, () {
        final skillId = fixture.inputField<String>('skillId');
        final result = applyXp(
          saveOf(fixture),
          databaseOf(fixture),
          skillId,
          fixture.inputField<num>('amount'),
        );
        expect(
          checkParity(fixture, {
            'leveledUpTo': result.leveledUpTo,
            'progress': getSkillProgress(result.save, skillId).toJson(),
            'save': result.save.toJson(),
          }),
          isNull,
        );
      });
    }
  });

  group('raiseSkillToMinimumLevel parity', () {
    for (final fixture in loadParityFixtures('xp/raise-to-minimum')) {
      test(fixture.name, () {
        final skillId = fixture.inputField<String>('skillId');
        final result = raiseSkillToMinimumLevel(
          saveOf(fixture),
          databaseOf(fixture),
          skillId,
          fixture.inputField<num>('minLevel'),
        );
        expect(
          checkParity(fixture, {
            'raised': result.raised,
            'progress': getSkillProgress(result.save, skillId).toJson(),
            'save': result.save.toJson(),
          }),
          isNull,
        );
      });
    }
  });

  group('skill totals parity', () {
    for (final fixture in loadParityFixtures('skills/totals')) {
      test(fixture.name, () {
        final save = saveOf(fixture);
        expect(
          checkParity(fixture, {
            'totalSkillXp': totalSkillXp(save),
            'totalLevel': totalLevel(save),
          }),
          isNull,
        );
      });
    }
  });

  group('requirement parity', () {
    for (final fixture in loadParityFixtures('requirements/evaluate')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final results = db.requirements.map((requirement) {
          final check = evaluateRequirement(db, save, requirement);
          return <String, Object?>{
            'requirementId': requirement.requirementId,
            'hard': isHardRequirement(requirement),
            'met': check.met,
            'detail': check.detail,
          };
        }).toList();
        expect(checkParity(fixture, {'results': results}), isNull);
      });
    }

    for (final fixture in loadParityFixtures('requirements/for-entity')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final rows = requirementsForEntity(
          db,
          fixture.inputField<String>('entityType'),
          fixture.inputField<String>('entityId'),
        );
        expect(
          checkParity(fixture, {
            'requirementIds': rows.map((row) => row.requirementId).toList(),
            'unmet': unmetHardRequirements(db, save, rows),
          }),
          isNull,
        );
      });
    }
  });
}
