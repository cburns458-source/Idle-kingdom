import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

PlayerSave _withPresetSlots(PlayerSave save, int index, Map<String, EquippedStack?> extras) {
  return save.copyWith(
    equipmentPresets: [
      for (var i = 0; i < save.equipmentPresets.length; i += 1)
        if (i == index)
          save.equipmentPresets[i].copyWith(
            slots: <String, EquippedStack?>{...save.equipmentPresets[i].slots, ...extras},
          )
        else
          save.equipmentPresets[i],
    ],
  );
}

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  test('creates four default presets', () {
    final save = createNewSave(db, 0);
    expect(save.equipmentPresets, hasLength(4));
    expect(save.equipmentPresets[0].name, 'Preset 1');
    expect(save.activeEquipmentPresetIndex, 0);
  });

  test('auto-tracks preset 1 while active and saves snapshots for others', () {
    var save = addItemToInventory(createNewSave(db, 0), 'ITEM-0111', 1);
    final equipped = equipItemFromInventory(db, save, 'ITEM-0111');
    expect(equipped.ok, isTrue);
    save = trackActiveEquipmentPreset(equipped.save!);
    expect(save.equipmentPresets[0].slots['SLOT-0001']?.itemId, 'ITEM-0111');

    final toTwo = applyEquipmentPreset(db, save, 1);
    expect(toTwo.ok, isTrue);
    expect(toTwo.save!.activeEquipmentPresetIndex, 1);
    expect(toTwo.save!.equipment.slots['SLOT-0001'], isNull);
    expect(toTwo.save!.inventory.any((stack) => stack.itemId == 'ITEM-0111'), isTrue);

    var onTwo = addItemToInventory(toTwo.save!, 'ITEM-0110', 1);
    final hatchet = equipItemFromInventory(db, onTwo, 'ITEM-0110');
    expect(hatchet.ok, isTrue);
    onTwo = saveActiveEquipmentPreset(hatchet.save!);
    expect(onTwo.equipmentPresets[1].slots['SLOT-0001']?.itemId, 'ITEM-0110');

    final back = applyEquipmentPreset(db, onTwo, 0);
    expect(back.ok, isTrue);
    expect(back.save!.equipment.slots['SLOT-0001']?.itemId, 'ITEM-0111');
  });

  test('blocks preset swaps when the bag cannot hold unequipped gear', () {
    var save = createNewSave(db, 0);
    save = save.copyWith(
      equipment: EquipmentLoadout(
        slots: {
          ...save.equipment.slots,
          'SLOT-0001': const EquippedStack(itemId: 'ITEM-0111', quantity: 1),
        },
      ),
      inventory: [
        for (var i = 0; i < inventorySlotLimit; i += 1)
          InventoryStack(itemId: 'ITEM-PAD-$i', quantity: 1),
      ],
    );
    save = _withPresetSlots(save, 0, {
      'SLOT-0001': const EquippedStack(itemId: 'ITEM-0111', quantity: 1),
    });

    final blocked = applyEquipmentPreset(db, save, 1);
    expect(blocked.ok, isFalse);
    expect(blocked.reason, contains('inventory space'));
  });

  test('equips owned pieces and leaves missing slots empty without rewriting the snapshot', () {
    var save = addItemToInventory(createNewSave(db, 0), 'ITEM-0111', 1);
    final equipped = equipItemFromInventory(db, save, 'ITEM-0111');
    expect(equipped.ok, isTrue);
    save = trackActiveEquipmentPreset(equipped.save!);
    save = _withPresetSlots(save, 1, {
      'SLOT-0001': const EquippedStack(itemId: 'ITEM-0111', quantity: 1),
      'SLOT-0003': const EquippedStack(itemId: 'ITEM-0155', quantity: 1),
    });

    final applied = applyEquipmentPreset(db, save, 1);
    expect(applied.ok, isTrue);
    expect(applied.warning, 'Some items were missing.');
    expect(applied.save!.equipment.slots['SLOT-0001']?.itemId, 'ITEM-0111');
    expect(applied.save!.equipment.slots['SLOT-0003'], isNull);
    expect(applied.save!.equipmentPresets[1].slots['SLOT-0003']?.itemId, 'ITEM-0155');

    final withHelm = addItemToInventory(applied.save!, 'ITEM-0155', 1);
    final toOne = applyEquipmentPreset(db, withHelm, 0);
    expect(toOne.ok, isTrue);
    final again = applyEquipmentPreset(db, toOne.save!, 1);
    expect(again.ok, isTrue);
    expect(again.warning, isNull);
    expect(again.save!.equipment.slots['SLOT-0003']?.itemId, 'ITEM-0155');
  });

  test(
    'keeps an unowned stored piece on preset 1 and clears it when the piece is still in the bag',
    () {
      var save = createNewSave(db, 0);
      save = save.copyWith(
        equipment: EquipmentLoadout(
          slots: {
            ...save.equipment.slots,
            'SLOT-0001': const EquippedStack(itemId: 'ITEM-0111', quantity: 1),
          },
        ),
      );
      save = _withPresetSlots(save, 0, {
        'SLOT-0001': const EquippedStack(itemId: 'ITEM-0111', quantity: 1),
        'SLOT-0003': const EquippedStack(itemId: 'ITEM-0155', quantity: 1),
      });

      final kept = trackActiveEquipmentPreset(save);
      expect(kept.equipmentPresets[0].slots['SLOT-0001']?.itemId, 'ITEM-0111');
      expect(kept.equipmentPresets[0].slots['SLOT-0003']?.itemId, 'ITEM-0155');

      final withHelm = addItemToInventory(save, 'ITEM-0155', 1);
      final cleared = trackActiveEquipmentPreset(withHelm);
      expect(cleared.equipmentPresets[0].slots['SLOT-0003'], isNull);
    },
  );

  test('writes a snapshot slot without changing worn gear or the active preset', () {
    final save = addItemToInventory(createNewSave(db, 0), 'ITEM-0111', 1);
    final equipped = equipItemFromInventory(db, save, 'ITEM-0111');
    expect(equipped.ok, isTrue);
    final next = setEquipmentPresetSlot(
      db,
      equipped.save!,
      1,
      'SLOT-0001',
      const EquippedStack(itemId: 'ITEM-0110', quantity: 1),
    );
    expect(next.activeEquipmentPresetIndex, 0);
    expect(next.equipment.slots['SLOT-0001']?.itemId, 'ITEM-0111');
    expect(next.equipmentPresets[1].slots['SLOT-0001']?.itemId, 'ITEM-0110');
  });

  test('renames presets and sets icons', () {
    final renamed = renameEquipmentPreset(createNewSave(db, 0), 1, 'Mining Kit');
    final save = setEquipmentPresetIcon(
      renamed,
      1,
      const EquipmentPresetIcon(kind: 'skill', skillId: 'SKL-0002'),
    );
    expect(save.equipmentPresets[1].name, 'Mining Kit');
    expect(save.equipmentPresets[1].icon.kind, 'skill');
    expect(save.equipmentPresets[1].icon.skillId, 'SKL-0002');
  });
}
