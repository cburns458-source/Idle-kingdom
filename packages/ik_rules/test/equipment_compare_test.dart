import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

GameDatabase _db() => filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = _db();
  });

  PlayerSave withSkill(PlayerSave save, String skillId, num level) {
    final skills = [...save.skills];
    final index = skills.indexWhere((skill) => skill.skillId == skillId);
    final progress = SkillProgress(skillId: skillId, level: level, xp: 0);
    if (index < 0) {
      skills.add(progress);
    } else {
      skills[index] = progress;
    }
    return save.copyWith(skills: skills);
  }

  PlayerSave wear(PlayerSave save, String slotId, String itemId, {String? enchantmentId}) {
    return save.copyWith(
      equipment: EquipmentLoadout(
        slots: {
          ...save.equipment.slots,
          slotId: EquippedStack(itemId: itemId, quantity: 1, enchantmentId: enchantmentId),
        },
      ),
    );
  }

  EquipCompareStatRow stat(EquipmentCompareResult result, String label) {
    return result.stats.singleWhere((row) => row.label == label);
  }

  test('empty weapon slot lists the candidate damage after Might, not the full sheet', () {
    var save = createNewSave(db, 0);
    save = withSkill(save, mightSkillId, 20);
    final result = compareEquipmentCandidate(db, save, itemId: 'ITEM-0124');
    expect(result.ok, isTrue, reason: result.reason);
    expect(result.slotEmpty, isTrue);

    final preview = previewEquippedSave(db, save, itemId: 'ITEM-0124', slotId: result.slotId!);
    final shown = playerDamageRange(db, preview);
    final min = stat(result, 'Min damage');
    expect(min.equippedText, '—');
    expect(min.candidateText, jsNumberToString(shown.min));
    expect(min.candidateKind, EquipCompareDeltaKind.improved);
    expect(min.equippedKind, EquipCompareDeltaKind.unchanged);
    expect(result.stats.any((row) => row.label == 'Attack damage'), isFalse);
  });

  test('stronger sword wins damage rows after Might', () {
    var save = createNewSave(db, 0);
    save = withSkill(save, mightSkillId, 20);
    save = wear(save, weaponToolSlotId, 'ITEM-0124');
    final result = compareEquipmentCandidate(db, save, itemId: 'ITEM-0128');
    expect(result.ok, isTrue, reason: result.reason);
    expect(result.equippedName, 'Wooden Sword');
    expect(result.candidateName, 'Iron Sword');

    final wooden = playerDamageRange(db, save);
    final ironPreview = previewEquippedSave(
      db,
      save,
      itemId: 'ITEM-0128',
      slotId: weaponToolSlotId,
    );
    final iron = playerDamageRange(db, ironPreview);
    expect(iron.min, greaterThan(wooden.min));

    final min = stat(result, 'Min damage');
    expect(min.equippedText, jsNumberToString(wooden.min));
    expect(min.candidateText, jsNumberToString(iron.min));
    expect(min.candidateKind, EquipCompareDeltaKind.improved);
    expect(min.equippedKind, EquipCompareDeltaKind.reduced);
  });

  test('helmet Health is the added HP after Vitality and a new blanket enchantment', () {
    var save = createNewSave(db, 0);
    save = withSkill(save, vitalitySkillId, 10);
    const helmetId = 'ITEM-0308';
    const vitalPlating = 'ENCH-0013';
    final result = compareEquipmentCandidate(
      db,
      save,
      itemId: helmetId,
      enchantmentId: vitalPlating,
    );
    expect(result.ok, isTrue, reason: result.reason);

    final preview = previewEquippedSave(
      db,
      save,
      itemId: helmetId,
      slotId: result.slotId!,
      enchantmentId: vitalPlating,
    );
    final emptySlot = save;
    final added = playerMaxHp(db, preview) - playerMaxHp(db, emptySlot);
    // 15 HP × 110% Vitality + 5% of all HP after the helmet is on.
    expect(added, playerMaxHp(db, preview) - playerMaxHp(db, save));
    expect(added, isNot(playerMaxHp(db, preview)));

    final health = stat(result, 'Health');
    expect(health.candidateText, jsNumberToString(added));
    expect(health.equippedText, '—');
    expect(health.candidateKind, EquipCompareDeltaKind.improved);
  });

  test('already-worn HP% enchantment is not counted again on a plain helmet', () {
    var save = createNewSave(db, 0);
    save = withSkill(save, vitalitySkillId, 10);
    save = wear(save, 'SLOT-0004', 'ITEM-0309', enchantmentId: 'ENCH-0013');
    final result = compareEquipmentCandidate(db, save, itemId: 'ITEM-0308');
    expect(result.ok, isTrue, reason: result.reason);

    final preview = previewEquippedSave(db, save, itemId: 'ITEM-0308', slotId: result.slotId!);
    final added = playerMaxHp(db, preview) - playerMaxHp(db, save);
    final health = stat(result, 'Health');
    expect(health.candidateText, jsNumberToString(added));

    // Existing +5% stays on both sides; only the helmet's 15 HP (scaled) is new.
    final withoutExistingPercent = playerMaxHp(db, wear(save, 'SLOT-0004', 'ITEM-0309'));
    final fullBlanketIfRecounted = playerMaxHp(db, preview) - withoutExistingPercent;
    expect(added, lessThan(fullBlanketIfRecounted));
  });

  test('steel shield beats wooden shield on Health and damage reduction', () {
    var save = createNewSave(db, 0);
    save = withSkill(save, vitalitySkillId, 35);
    save = wear(save, offhandSlotId, 'ITEM-0145');
    final result = compareEquipmentCandidate(db, save, itemId: 'ITEM-0148');
    expect(result.ok, isTrue, reason: result.reason);
    expect(stat(result, 'Health').candidateKind, EquipCompareDeltaKind.improved);
    expect(stat(result, 'Damage reduction').candidateKind, EquipCompareDeltaKind.improved);
  });

  test('two-handed weapon notes clearing the off-hand', () {
    var save = createNewSave(db, 0);
    save = withSkill(save, 'SKL-0008', 35);
    save = wear(save, offhandSlotId, 'ITEM-0145');
    final result = compareEquipmentCandidate(db, save, itemId: 'ITEM-0123');
    expect(result.ok, isTrue, reason: result.reason);
    expect(result.displaced, isNotEmpty);
    expect(result.displaced.single.slotId, offhandSlotId);
    expect(result.notes.any((line) => line.startsWith('Also clears')), isTrue);
  });

  test('off-hand item notes clearing a worn two-hander', () {
    var save = createNewSave(db, 0);
    save = withSkill(save, 'SKL-0008', 35);
    save = wear(save, weaponToolSlotId, 'ITEM-0123');
    final result = compareEquipmentCandidate(db, save, itemId: 'ITEM-0145');
    expect(result.ok, isTrue, reason: result.reason);
    expect(result.displaced.single.slotId, weaponToolSlotId);
  });

  test('refuses non-equipment items', () {
    final save = createNewSave(db, 0);
    final result = compareEquipmentCandidate(db, save, itemId: 'ITEM-0003');
    expect(result.ok, isFalse);
    expect(result.reason, 'That item cannot be equipped.');
    expect(result.stats, isEmpty);
  });

  test('refuses gear that fails skill requirements', () {
    final save = createNewSave(db, 0);
    final result = compareEquipmentCandidate(db, save, itemId: 'ITEM-0255');
    expect(result.ok, isFalse);
    expect(result.reason, contains('Requires'));
  });

  test('preview does not mutate the original save', () {
    var save = createNewSave(db, 0);
    save = wear(save, weaponToolSlotId, 'ITEM-0124');
    final before = save.toJson();
    compareEquipmentCandidate(db, save, itemId: 'ITEM-0128');
    expect(save.toJson(), before);
    expect(slotItemId(save, weaponToolSlotId), 'ITEM-0124');
  });

  test('success chance rows name the skill and split hatchet from pickaxe', () {
    var save = createNewSave(db, 0);
    save = wear(save, weaponToolSlotId, 'ITEM-0110');
    const copperPickaxe = 'ITEM-0111';
    final result = compareEquipmentCandidate(db, save, itemId: copperPickaxe);
    expect(result.ok, isTrue, reason: result.reason);

    final woodcutting = stat(result, 'Woodcutting success chance %');
    expect(woodcutting.equippedText, '3');
    expect(woodcutting.candidateText, '—');
    expect(woodcutting.equippedKind, EquipCompareDeltaKind.improved);

    final mining = stat(result, 'Mining success chance %');
    expect(mining.equippedText, '—');
    expect(mining.candidateKind, EquipCompareDeltaKind.improved);
  });

  test('targetSlotId compares a bag piece against a worn slot', () {
    var save = createNewSave(db, 0);
    save = wear(save, weaponToolSlotId, 'ITEM-0110');
    save = save.copyWith(
      inventory: [
        ...save.inventory,
        const InventoryStack(itemId: 'ITEM-0124', quantity: 1),
      ],
    );
    final candidates = compareCandidatesForSlot(db, save, weaponToolSlotId);
    expect(candidates.map((row) => row.itemId), contains('ITEM-0124'));

    final result = compareEquipmentCandidate(
      db,
      save,
      itemId: 'ITEM-0124',
      targetSlotId: weaponToolSlotId,
    );
    expect(result.ok, isTrue, reason: result.reason);
    expect(result.equippedItemId, 'ITEM-0110');
    expect(result.slotId, weaponToolSlotId);
  });

  test('daggers resolve to the off-hand slot', () {
    final save = createNewSave(db, 0);
    final resolved = resolveCompareSlot(db, save, 'ITEM-0125');
    expect(resolved.slotId, offhandSlotId);
    expect(resolved.reason, isNull);
  });
}
