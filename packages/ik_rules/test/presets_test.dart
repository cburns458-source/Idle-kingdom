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

  test('save snapshots the worn loadout; switching does not rewrite other presets', () {
    var save = addItemToInventory(createNewSave(db, 0), 'ITEM-0111', 1);
    final equipped = equipItemFromInventory(db, save, 'ITEM-0111');
    expect(equipped.ok, isTrue);
    save = saveActiveEquipmentPreset(equipped.save!);
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
    expect(onTwo.equipmentPresets[0].slots['SLOT-0001']?.itemId, 'ITEM-0111');

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
    save = saveActiveEquipmentPreset(equipped.save!);
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

  test('does not copy worn gear onto a preset when tracking', () {
    var save = createNewSave(db, 0);
    save = save.copyWith(
      equipment: EquipmentLoadout(
        slots: {
          ...save.equipment.slots,
          'SLOT-0001': const EquippedStack(itemId: 'ITEM-0111', quantity: 1),
        },
      ),
    );
    final tracked = trackActiveEquipmentPreset(save);
    expect(tracked.equipmentPresets[0].slots['SLOT-0001'], isNull);
    expect(presetMatchesLoadout(tracked, 0), isFalse);
    expect(shouldHighlightEquipmentPreset(tracked, 0), isFalse);
  });

  test('matches loadouts by item identity and ignores food quantity', () {
    var save = createNewSave(db, 0);
    save = save.copyWith(
      equipment: EquipmentLoadout(
        slots: {
          ...save.equipment.slots,
          'SLOT-0001': const EquippedStack(itemId: 'ITEM-0111', quantity: 1),
          foodSlotId: const EquippedStack(itemId: 'ITEM-0058', quantity: 2),
        },
      ),
    );
    save = _withPresetSlots(save, 1, {
      'SLOT-0001': const EquippedStack(itemId: 'ITEM-0111', quantity: 1),
      foodSlotId: const EquippedStack(itemId: 'ITEM-0058', quantity: 5),
    });
    expect(presetMatchesLoadout(save, 1), isTrue);
    expect(shouldHighlightEquipmentPreset(save, 1), isFalse);
    save = save.copyWith(activeEquipmentPresetIndex: 1);
    expect(shouldHighlightEquipmentPreset(save, 1), isTrue);
    expect(shouldHighlightEquipmentPreset(save, 0), isFalse);

    save = save.copyWith(
      equipment: EquipmentLoadout(
        slots: {
          ...save.equipment.slots,
          foodSlotId: const EquippedStack(itemId: 'ITEM-0059', quantity: 2),
        },
      ),
    );
    expect(presetMatchesLoadout(save, 1), isFalse);
  });

  test('matching clones do not highlight together', () {
    var save = createNewSave(db, 0);
    save = save.copyWith(
      equipment: EquipmentLoadout(
        slots: {
          ...save.equipment.slots,
          'SLOT-0001': const EquippedStack(itemId: 'ITEM-0111', quantity: 1),
        },
      ),
      activeEquipmentPresetIndex: 0,
    );
    save = _withPresetSlots(save, 0, {
      'SLOT-0001': const EquippedStack(itemId: 'ITEM-0111', quantity: 1),
    });
    save = _withPresetSlots(save, 1, {
      'SLOT-0001': const EquippedStack(itemId: 'ITEM-0111', quantity: 1),
    });
    expect(presetMatchesLoadout(save, 0), isTrue);
    expect(presetMatchesLoadout(save, 1), isTrue);
    expect(shouldHighlightEquipmentPreset(save, 0), isTrue);
    expect(shouldHighlightEquipmentPreset(save, 1), isFalse);
  });

  test('editing a selected preset wears the new snapshot', () {
    var save = addItemToInventory(createNewSave(db, 0), 'ITEM-0111', 1);
    save = addItemToInventory(save, 'ITEM-0110', 1);
    final equipped = equipItemFromInventory(db, save, 'ITEM-0111');
    expect(equipped.ok, isTrue);
    save = saveActiveEquipmentPreset(equipped.save!);

    final next = editSelectedEquipmentPresetSlot(
      db,
      save,
      0,
      'SLOT-0001',
      const EquippedStack(itemId: 'ITEM-0110', quantity: 1),
    );
    expect(next.equipmentPresets[0].slots['SLOT-0001']?.itemId, 'ITEM-0110');
    expect(next.equipment.slots['SLOT-0001']?.itemId, 'ITEM-0110');
    expect(next.inventory.any((stack) => stack.itemId == 'ITEM-0111'), isTrue);
  });

  test('applying the active preset still restores it after the loadout diverged', () {
    var save = addItemToInventory(createNewSave(db, 0), 'ITEM-0111', 1);
    save = addItemToInventory(save, 'ITEM-0110', 1);
    final equipped = equipItemFromInventory(db, save, 'ITEM-0111');
    expect(equipped.ok, isTrue);
    save = saveActiveEquipmentPreset(equipped.save!);
    final hatchet = equipItemFromInventory(db, save, 'ITEM-0110');
    expect(hatchet.ok, isTrue);
    save = hatchet.save!;
    expect(save.activeEquipmentPresetIndex, 0);
    expect(save.equipment.slots['SLOT-0001']?.itemId, 'ITEM-0110');

    final restored = applyEquipmentPreset(db, save, 0);
    expect(restored.ok, isTrue);
    expect(restored.save!.equipment.slots['SLOT-0001']?.itemId, 'ITEM-0111');
  });

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
