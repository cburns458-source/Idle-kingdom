import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  test('deletes Regular Bow and Ancient Binding from content', () {
    expect(db.items.any((row) => row.itemId == removedRegularBowItemId), isFalse);
    expect(db.items.any((row) => row.itemId == removedAncientBindingItemId), isFalse);
    expect(db.equipment.any((row) => row.raw['Item ID'] == removedRegularBowItemId), isFalse);
    expect(db.recipes.any((row) => row.raw['Recipe ID'] == removedAncientBindingRecipeId), isFalse);
    expect(db.actions.any((row) => row.actionId == removedAncientBindingActionId), isFalse);
  });

  test('v65 drops leftover copies from bag, bank, equipment, presets, mail, and crafts', () {
    final base = createNewSave(db, 0);
    final legacy = base.toJson();
    legacy['saveVersion'] = 65;
    legacy['inventory'] = <Object?>[
      <String, Object?>{'itemId': removedRegularBowItemId, 'quantity': 1},
      <String, Object?>{'itemId': 'ITEM-0003', 'quantity': 4},
      <String, Object?>{'itemId': removedAncientBindingItemId, 'quantity': 2},
    ];
    legacy['bank'] = <Object?>[
      <String, Object?>{'itemId': removedRegularBowItemId, 'quantity': 3},
    ];
    final equipment = Map<String, Object?>.from(legacy['equipment']! as Map);
    final slots = Map<String, Object?>.from(equipment['slots']! as Map);
    slots[weaponToolSlotId] = <String, Object?>{'itemId': removedRegularBowItemId, 'quantity': 1};
    equipment['slots'] = slots;
    legacy['equipment'] = equipment;
    final presets = [
      for (final row in legacy['equipmentPresets']! as List) Map<String, Object?>.from(row as Map),
    ];
    final firstSlots = Map<String, Object?>.from(presets.first['slots']! as Map);
    firstSlots[weaponToolSlotId] = <String, Object?>{
      'itemId': removedRegularBowItemId,
      'quantity': 1,
    };
    presets.first['slots'] = firstSlots;
    legacy['equipmentPresets'] = presets;
    legacy['mailbox'] = <Object?>[
      <String, Object?>{
        'id': 'mail-ren01',
        'catalogId': null,
        'subject': 'A bow',
        'body': 'Keep this Regular Bow.',
        'sentAt': '2026-01-01T00:00:00.000Z',
        'readAt': null,
        'attachments': <Object?>[
          <String, Object?>{'itemId': removedRegularBowItemId, 'quantity': 1},
        ],
        'claimedAt': null,
      },
    ];
    legacy['productionRecipeId'] = removedAncientBindingRecipeId;
    legacy['productionQuantityTotal'] = 1;
    legacy['productionQuantityRemaining'] = 1;
    legacy['currentActionId'] = removedAncientBindingActionId;
    legacy['currentActivityId'] = 'ACT-0001';
    legacy['actionStartedAt'] = '2026-01-01T00:00:00.000Z';
    legacy['actionDurationMs'] = 12000;
    legacy['activityStartedAt'] = '2026-01-01T00:00:00.000Z';
    legacy['heldActionByActivityId'] = <String, Object?>{'ACT-0001': removedAncientBindingActionId};
    legacy['activityTransition'] = <String, Object?>{
      'kind': 'starting',
      'activityId': 'ACT-0001',
      'followUpActivityId': null,
      'productionRecipeId': removedAncientBindingRecipeId,
      'productionQuantity': 1,
      'startedAt': '2026-01-01T00:00:00.000Z',
      'durationMs': 1000,
    };

    final migrated = migrateSaveJson(legacy, 0);
    expect(migrated['saveVersion'], saveVersion);
    expect(migrated['inventory'], [
      {'itemId': 'ITEM-0003', 'quantity': 4},
    ]);
    expect(migrated['bank'], isEmpty);
    final nextEquipment = migrated['equipment'] as Map;
    final nextSlots = nextEquipment['slots'] as Map;
    expect(nextSlots[weaponToolSlotId], isNull);
    final nextPresets = migrated['equipmentPresets'] as List;
    final nextFirstSlots = (nextPresets.first as Map)['slots'] as Map;
    expect(nextFirstSlots[weaponToolSlotId], isNull);
    final mail = (migrated['mailbox'] as List).first as Map;
    expect(mail['body'], 'Keep this Regular Bow.');
    expect(mail['attachments'], isEmpty);
    expect(migrated['productionRecipeId'], isNull);
    expect(migrated['productionQuantityTotal'], isNull);
    expect(migrated['productionQuantityRemaining'], isNull);
    expect(migrated['currentActionId'], isNull);
    expect(migrated['currentActivityId'], isNull);
    expect(migrated['activityTransition'], isNull);
    expect(migrated['heldActionByActivityId'], isEmpty);
  });
}
