import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

Map<String, Object?> _resultJson(EquipResult result) {
  return result.ok
      ? <String, Object?>{'ok': true, 'save': result.save!.toJson()}
      : <String, Object?>{'ok': false, 'reason': result.reason};
}

void main() {
  group('equip item parity', () {
    for (final fixture in loadParityFixtures('equipment/equip-item')) {
      test(fixture.name, () {
        final result = equipItemFromInventory(
          databaseOf(fixture),
          saveOf(fixture),
          fixture.inputField<String>('itemId'),
        );
        expect(checkParity(fixture, _resultJson(result)), isNull);
      });
    }
  });

  group('equip index parity', () {
    for (final fixture in loadParityFixtures('equipment/equip-index')) {
      test(fixture.name, () {
        final result = equipInventoryIndex(
          databaseOf(fixture),
          saveOf(fixture),
          fixture.inputField<num>('index'),
        );
        expect(checkParity(fixture, _resultJson(result)), isNull);
      });
    }
  });

  group('unequip parity', () {
    for (final fixture in loadParityFixtures('equipment/unequip')) {
      test(fixture.name, () {
        final result = unequipSlot(saveOf(fixture), fixture.inputField<String>('slotId'));
        expect(checkParity(fixture, _resultJson(result)), isNull);
      });
    }
  });

  group('force set slot parity', () {
    const cases = <String, (String, String, num)>{
      'replaces-weapon': ('SLOT-0001', 'ITEM-0114', 1),
      'zero-quantity-unequips': ('SLOT-0001', 'ITEM-0114', 0),
      'consumes-matching-inventory': ('SLOT-0011', 'ITEM-0059', 5),
    };
    for (final fixture in loadParityFixtures('equipment/force-set')) {
      test(fixture.name, () {
        final (slotId, itemId, quantity) = cases[fixture.name]!;
        final save = equipStackToSlot(saveOf(fixture), slotId, itemId, quantity);
        expect(checkParity(fixture, {'save': save.toJson()}), isNull);
      });
    }
  });

  group('equipment row parity', () {
    for (final fixture in loadParityFixtures('equipment/rows')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final rows = db.equipment.map((equipment) {
          final slotId = equipment.raw['Slot ID'];
          return <String, Object?>{
            'itemId': equipment.itemId,
            'requirementFailure': equipmentRequirementFailure(db, save, equipment),
            'tooltip': equipmentTooltipStatLines(equipment),
            'dagger': isDaggerItem(db, equipment.itemId),
            'consumableSlot': isStackableConsumableSlot(slotId is String ? slotId : ''),
          };
        }).toList();
        expect(checkParity(fixture, {'rows': rows}), isNull);
      });
    }
  });

  group('equipment lookup parity', () {
    for (final fixture in loadParityFixtures('equipment/lookup')) {
      test(fixture.name, () {
        expect(
          checkParity(fixture, {
            'found': equipmentForItemId(databaseOf(fixture), 'ITEM-9999') != null,
            'tooltip': equipmentTooltipStatLines(null),
          }),
          isNull,
        );
      });
    }
  });

  group('equipment summary parity', () {
    for (final fixture in loadParityFixtures('equipment/summary')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        expect(
          checkParity(fixture, {
            'actionTimeReduction': equippedActionTimeReductionPercent(db, save),
            'mainhand': slotItemId(save, 'SLOT-0001'),
            'offhand': slotItemId(save, 'SLOT-0002'),
            'vitals': withRecalculatedVitals(db, save).toJson(),
          }),
          isNull,
        );
      });
    }
  });

  group('auto equip parity', () {
    for (final fixture in loadParityFixtures('equipment/auto-equip')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final activityId = fixture.inputField<String>('activityId');
        final proposal = proposeAutoEquipForActivity(db, save, activityId, 'blocked');
        expect(
          checkParity(fixture, {
            'required': toolCapabilitiesRequiredForActivity(db, activityId),
            'missing': missingToolCapabilities(db, save, activityId),
            'proposal': proposal?.toJson(),
            'prompt': proposal == null ? null : autoEquipPromptView(proposal).toJson(),
          }),
          isNull,
        );
      });
    }
  });
}
