import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../combat/stats.dart';
import '../js_compat.dart';
import '../projects/enchantments.dart';
import '../save/generated/save_models.dart';
import '../spells/spells.dart';
import 'loadout.dart';
import 'tooltips.dart';

/// How one side of a compared stat sits relative to the other item.
enum EquipCompareDeltaKind { improved, reduced, unchanged, special }

/// One labeled stat with a value for the equipped item and the candidate.
class EquipCompareStatRow {
  const EquipCompareStatRow({
    required this.label,
    required this.equippedText,
    required this.candidateText,
    required this.equippedKind,
    required this.candidateKind,
  });

  final String label;
  final String equippedText;
  final String candidateText;
  final EquipCompareDeltaKind equippedKind;
  final EquipCompareDeltaKind candidateKind;

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'equippedText': equippedText,
    'candidateText': candidateText,
    'equippedKind': equippedKind.name,
    'candidateKind': candidateKind.name,
  };
}

/// Side-by-side preview of equipping [candidateItemId] without mutating the save.
class EquipmentCompareResult {
  const EquipmentCompareResult({
    required this.ok,
    required this.slotId,
    required this.candidateItemId,
    required this.candidateName,
    required this.candidateEnchantmentId,
    required this.equippedItemId,
    required this.equippedName,
    required this.equippedEnchantmentId,
    required this.displaced,
    required this.stats,
    required this.notes,
    this.reason,
  });

  final bool ok;
  final String? reason;
  final String? slotId;
  final String candidateItemId;
  final String candidateName;
  final String? candidateEnchantmentId;
  final String? equippedItemId;
  final String? equippedName;
  final String? equippedEnchantmentId;

  /// Extra slots cleared by two-handed / off-hand rules (not the primary replace).
  final List<({String slotId, String? itemId, String? name})> displaced;
  final List<EquipCompareStatRow> stats;
  final List<String> notes;

  bool get slotEmpty => equippedItemId == null;

  Map<String, Object?> toJson() => <String, Object?>{
    'ok': ok,
    if (reason != null) 'reason': reason,
    'slotId': slotId,
    'candidateItemId': candidateItemId,
    'candidateName': candidateName,
    'candidateEnchantmentId': candidateEnchantmentId,
    'equippedItemId': equippedItemId,
    'equippedName': equippedName,
    'equippedEnchantmentId': equippedEnchantmentId,
    'displaced': [
      for (final row in displaced)
        <String, Object?>{'slotId': row.slotId, 'itemId': row.itemId, 'name': row.name},
    ],
    'stats': stats.map((row) => row.toJson()).toList(),
    'notes': notes,
  };
}

String _itemName(GameDatabase db, String? itemId) {
  if (itemId == null || itemId.isEmpty) return 'Empty';
  final name = db.items.firstWhereOrNull((row) => row.itemId == itemId)?.displayName;
  return name is String && name.isNotEmpty ? name : itemId;
}

String _slotName(GameDatabase db, String slotId) {
  final name = db.equipmentSlots.firstWhereOrNull((row) => row.slotId == slotId)?.displayName;
  return name is String && name.isNotEmpty ? name : slotId;
}

PlayerSave _overlaySlot(PlayerSave save, String slotId, EquippedStack? stack) {
  return save.copyWith(
    equipment: EquipmentLoadout(slots: {...save.equipment.slots, slotId: stack}),
  );
}

/// Resolves which slot [itemId] would occupy, mirroring [equipInventoryIndex].
///
/// [targetSlotId] pins the comparison to one worn slot (used when comparing
/// from an equipped item), as long as the item fits there.
({String? slotId, String? reason}) resolveCompareSlot(
  GameDatabase db,
  PlayerSave save,
  String itemId, {
  String? preferredSlotId,
  String? targetSlotId,
}) {
  final equipment = equipmentForItemId(db, itemId);
  final equipmentSlotId = equipment?.raw['Slot ID'];
  if (equipment == null || equipmentSlotId is! String || equipmentSlotId.isEmpty) {
    return (slotId: null, reason: 'That item cannot be equipped.');
  }

  final templeRefusal = templeHandsRefusal(save, equipmentSlotId);
  if (templeRefusal != null) return (slotId: null, reason: templeRefusal);

  final requirementFailure = equipmentRequirementFailure(db, save, equipment);
  if (requirementFailure != null) return (slotId: null, reason: requirementFailure);

  if (targetSlotId != null) {
    if (!itemFitsEquipmentSlot(db, itemId, targetSlotId)) {
      return (slotId: null, reason: 'That item does not fit this slot.');
    }
    return (slotId: targetSlotId, reason: null);
  }

  var slotId = equipmentSlotId;
  if (isSpellEquipment(equipment) || isSpellSlotId(slotId)) {
    if (preferredSlotId != null &&
        isSpellSlotId(preferredSlotId) &&
        slotStack(save, preferredSlotId) == null) {
      slotId = preferredSlotId;
    } else {
      final empty = firstEmptySpellSlot(save);
      if (empty == null) return (slotId: null, reason: 'All spell slots are full.');
      slotId = empty;
    }
  } else if (isDaggerItem(db, itemId)) {
    slotId = offhandSlotId;
    final mainhandId = slotItemId(save, weaponToolSlotId);
    if (isNotBlank(mainhandId) && isDaggerItem(db, mainhandId!)) {
      return (
        slotId: null,
        reason: 'Unequip your main-hand dagger before equipping an off-hand dagger.',
      );
    }
  }

  return (slotId: slotId, reason: null);
}

/// Builds the save as if [itemId] were worn, without touching inventory capacity.
PlayerSave previewEquippedSave(
  GameDatabase db,
  PlayerSave save, {
  required String itemId,
  required String slotId,
  String? enchantmentId,
}) {
  var next = save;
  final stack = EquippedStack(
    itemId: itemId,
    quantity: 1,
    enchantmentId: isNotBlank(enchantmentId) ? enchantmentId : null,
  );

  if (isTwoHandedItem(db, itemId) && slotId == weaponToolSlotId) {
    next = _overlaySlot(next, offhandSlotId, null);
  } else if (slotId == offhandSlotId) {
    final mainhandId = slotItemId(next, weaponToolSlotId);
    if (isNotBlank(mainhandId) && isTwoHandedItem(db, mainhandId!)) {
      next = _overlaySlot(next, weaponToolSlotId, null);
    }
  }

  return _overlaySlot(next, slotId, stack);
}

String _fmtNum(num value) => jsNumberToString(value);

class _CombatBits {
  const _CombatBits({
    required this.minDamage,
    required this.maxDamage,
    required this.offMin,
    required this.offMax,
    required this.health,
    required this.damageReduction,
  });

  final num minDamage;
  final num maxDamage;
  final num offMin;
  final num offMax;
  final num health;
  final num damageReduction;

  _CombatBits minus(_CombatBits other) {
    return _CombatBits(
      minDamage: minDamage - other.minDamage,
      maxDamage: maxDamage - other.maxDamage,
      offMin: offMin - other.offMin,
      offMax: offMax - other.offMax,
      health: health - other.health,
      damageReduction: damageReduction - other.damageReduction,
    );
  }
}

_CombatBits _combatBits(GameDatabase db, PlayerSave save) {
  final damage = playerDamageRange(db, save);
  final offhand = playerOffhandDamageRange(db, save);
  return _CombatBits(
    minDamage: damage.min,
    maxDamage: damage.max,
    offMin: offhand?.min ?? 0,
    offMax: offhand?.max ?? 0,
    health: playerMaxHp(db, save),
    damageReduction: playerDamageReduction(db, save),
  );
}

/// What [save] gains from the item in [slotId] versus leaving that slot empty.
///
/// Might, Vitality, race, and already-worn blanket enchantments stay on both
/// sides, so only this item's own stats and any *new* blanket it brings remain.
_CombatBits _itemCombatContribution(GameDatabase db, PlayerSave save, String slotId) {
  final without = _overlaySlot(save, slotId, null);
  return _combatBits(db, save).minus(_combatBits(db, without));
}

bool _itemHasOwnDamage(EquipmentRow? row) {
  final min = row?.raw['Min Damage'];
  final max = row?.raw['Max Damage'];
  return min is num || max is num;
}

/// Displayed combat numbers for one worn item.
///
/// Weapons and daggers list their own scaled damage (starting value × Might and
/// any percent bonuses while that item is on). Health and damage reduction are
/// always the amount that item adds versus an empty slot, so a new HP%
/// enchantment includes the blanket on the rest of the player's health.
_CombatBits _itemDisplayBits(GameDatabase db, PlayerSave wornSave, String slotId, String? itemId) {
  if (itemId == null || itemId.isEmpty) {
    return const _CombatBits(
      minDamage: 0,
      maxDamage: 0,
      offMin: 0,
      offMax: 0,
      health: 0,
      damageReduction: 0,
    );
  }
  final added = _itemCombatContribution(db, wornSave, slotId);
  final full = _combatBits(db, wornSave);
  final primaryWeapon =
      _itemHasOwnDamage(equipmentForItemId(db, itemId)) && slotId == weaponToolSlotId;
  final dagger = isDaggerItem(db, itemId);
  return _CombatBits(
    minDamage: primaryWeapon ? full.minDamage : added.minDamage,
    maxDamage: primaryWeapon ? full.maxDamage : added.maxDamage,
    offMin: dagger ? full.offMin : added.offMin,
    offMax: dagger ? full.offMax : added.offMax,
    health: added.health,
    damageReduction: added.damageReduction,
  );
}

/// Main-hand + off-hand as one equipped side when a two-hander would replace both.
({_CombatBits bits, String? itemId, String? name, String? enchantmentId, bool present})
_handsEquippedSide(GameDatabase db, PlayerSave save) {
  final main = slotStack(save, weaponToolSlotId);
  final off = slotStack(save, offhandSlotId);
  final present = main != null || off != null;
  if (!present) {
    return (
      bits: const _CombatBits(
        minDamage: 0,
        maxDamage: 0,
        offMin: 0,
        offMax: 0,
        health: 0,
        damageReduction: 0,
      ),
      itemId: null,
      name: null,
      enchantmentId: null,
      present: false,
    );
  }

  final withoutBoth = _overlaySlot(_overlaySlot(save, weaponToolSlotId, null), offhandSlotId, null);
  final added = _combatBits(db, save).minus(_combatBits(db, withoutBoth));
  final full = _combatBits(db, save);
  final mainId = main?.itemId;
  final primaryWeapon = mainId != null && _itemHasOwnDamage(equipmentForItemId(db, mainId));
  final dagger = off != null && isDaggerItem(db, off.itemId);

  final mainName = main == null ? null : _itemName(db, main.itemId);
  final offName = off == null ? null : _itemName(db, off.itemId);
  final name = mainName == null
      ? offName
      : offName == null
      ? mainName
      : '$mainName + $offName';

  return (
    bits: _CombatBits(
      minDamage: primaryWeapon ? full.minDamage : added.minDamage,
      maxDamage: primaryWeapon ? full.maxDamage : added.maxDamage,
      offMin: dagger ? full.offMin : added.offMin,
      offMax: dagger ? full.offMax : added.offMax,
      health: added.health,
      damageReduction: added.damageReduction,
    ),
    itemId: main?.itemId ?? off?.itemId,
    name: name,
    enchantmentId: main?.enchantmentId ?? off?.enchantmentId,
    present: true,
  );
}

({EquipCompareDeltaKind equipped, EquipCompareDeltaKind candidate}) _kindsForValues(
  num? equipped,
  num? candidate, {
  required bool equippedPresent,
}) {
  if (!equippedPresent) {
    return (equipped: EquipCompareDeltaKind.unchanged, candidate: EquipCompareDeltaKind.improved);
  }
  final left = equipped ?? 0;
  final right = candidate ?? 0;
  if (left == right) {
    return (equipped: EquipCompareDeltaKind.unchanged, candidate: EquipCompareDeltaKind.unchanged);
  }
  if (right > left) {
    return (equipped: EquipCompareDeltaKind.reduced, candidate: EquipCompareDeltaKind.improved);
  }
  return (equipped: EquipCompareDeltaKind.improved, candidate: EquipCompareDeltaKind.reduced);
}

EquipCompareStatRow _statRow({
  required String label,
  required bool equippedPresent,
  required num equippedValue,
  required num candidateValue,
}) {
  final kinds = _kindsForValues(
    equippedPresent ? equippedValue : null,
    candidateValue,
    equippedPresent: equippedPresent,
  );
  return EquipCompareStatRow(
    label: label,
    equippedText: equippedPresent ? _fmtNum(equippedValue) : '—',
    candidateText: _fmtNum(candidateValue),
    equippedKind: kinds.equipped,
    candidateKind: kinds.candidate,
  );
}

List<EquipCompareStatRow> _combatStatRows({
  required bool equippedPresent,
  required _CombatBits equipped,
  required _CombatBits candidate,
}) {
  final rows = <EquipCompareStatRow>[];
  void add(String label, num left, num right) {
    if (!equippedPresent && right == 0) return;
    if (equippedPresent && left == 0 && right == 0) return;
    rows.add(
      _statRow(
        label: label,
        equippedPresent: equippedPresent,
        equippedValue: left,
        candidateValue: right,
      ),
    );
  }

  add('Min damage', equipped.minDamage, candidate.minDamage);
  add('Max damage', equipped.maxDamage, candidate.maxDamage);
  add('Off-hand min damage', equipped.offMin, candidate.offMin);
  add('Off-hand max damage', equipped.offMax, candidate.offMax);
  add('Health', equipped.health, candidate.health);
  add('Damage reduction', equipped.damageReduction, candidate.damageReduction);
  return rows;
}

num? _rowNumber(EquipmentRow? row, String key) {
  final value = row?.raw[key];
  return value is num && value != 0 ? value : null;
}

String? _skillName(GameDatabase db, Object? skillId) {
  if (skillId is! String || skillId.isEmpty) return null;
  final name = db.skills
      .firstWhereOrNull((row) => row.raw['Skill ID'] == skillId)
      ?.raw['Display Name'];
  return name is String && name.isNotEmpty ? name : skillId;
}

/// `Woodcutting success chance %` → value, so a hatchet and a pickaxe sharing
/// the Weapon/Tool slot land on separate rows.
Map<String, num> _successChanceBySkill(GameDatabase db, EquipmentRow? row) {
  final value = _rowNumber(row, 'Action Time Reduction %');
  if (value == null || value <= 0) return const {};
  final skills = <String>[
    for (final id in [row?.raw['Required Skill ID'], row?.raw['Secondary Required Skill ID']])
      ?_skillName(db, id),
  ];
  final label = skills.isEmpty ? 'Success chance %' : '${skills.join(', ')} success chance %';
  return {label: value};
}

EquipCompareStatRow _optionalRow(
  String label,
  num? left,
  num? right, {
  required bool equippedPresent,
}) {
  final kinds = _kindsForValues(left ?? 0, right ?? 0, equippedPresent: equippedPresent);
  return EquipCompareStatRow(
    label: label,
    equippedText: equippedPresent && left != null ? _fmtNum(left) : '—',
    candidateText: right != null ? _fmtNum(right) : '—',
    equippedKind: kinds.equipped,
    candidateKind: kinds.candidate,
  );
}

List<EquipCompareStatRow> _extraStatRows(
  GameDatabase db, {
  required bool equippedPresent,
  required List<EquipmentRow?> equippedRows,
  required EquipmentRow? candidateRow,
}) {
  final rows = <EquipCompareStatRow>[];
  num? leftHealing;
  for (final row in equippedRows) {
    final value = _rowNumber(row, 'Healing Amount');
    if (value != null) leftHealing = (leftHealing ?? 0) + value;
  }
  final rightHealing = _rowNumber(candidateRow, 'Healing Amount');
  if (leftHealing != null || rightHealing != null) {
    rows.add(_optionalRow('Healing', leftHealing, rightHealing, equippedPresent: equippedPresent));
  }

  final leftSuccess = <String, num>{};
  for (final row in equippedRows) {
    for (final entry in _successChanceBySkill(db, row).entries) {
      leftSuccess[entry.key] = (leftSuccess[entry.key] ?? 0) + entry.value;
    }
  }
  final rightSuccess = _successChanceBySkill(db, candidateRow);
  for (final label in <String>{...leftSuccess.keys, ...rightSuccess.keys}) {
    rows.add(
      _optionalRow(
        label,
        leftSuccess[label],
        rightSuccess[label],
        equippedPresent: equippedPresent,
      ),
    );
  }
  return rows;
}

/// Distinct bag stacks that could replace what is worn in [slotId].
List<({String itemId, String? enchantmentId})> compareCandidatesForSlot(
  GameDatabase db,
  PlayerSave save,
  String slotId,
) {
  if (isFoodSlot(slotId) || isPotionSlot(slotId)) return const [];
  final seen = <String>{};
  final out = <({String itemId, String? enchantmentId})>[];
  for (final stack in save.inventory) {
    if (!itemFitsEquipmentSlot(db, stack.itemId, slotId)) continue;
    final key = '${stack.itemId}|${stack.enchantmentId ?? ''}';
    if (!seen.add(key)) continue;
    out.add((itemId: stack.itemId, enchantmentId: stack.enchantmentId));
  }
  return out;
}

List<String> _itemNotes(GameDatabase db, String? itemId, String? enchantmentId) {
  if (itemId == null || itemId.isEmpty) return const [];
  final notes = <String>[
    ...enchantmentTooltipLines(db, enchantmentId),
    if (isSpellItem(db, itemId))
      ...spellTooltipLines(db, db.items.firstWhereOrNull((row) => row.itemId == itemId), itemId),
  ];
  return notes;
}

/// Compares equipping [itemId] against the gear it would replace.
///
/// Each column is what that item *adds* after Might, Vitality, race, and
/// enchantments — not the player's full totals. A new blanket percent on the
/// candidate (for example +5% maximum HP) is included in that item's Health
/// number; a blanket already worn on another piece is not counted again.
EquipmentCompareResult compareEquipmentCandidate(
  GameDatabase db,
  PlayerSave save, {
  required String itemId,
  String? enchantmentId,
  String? preferredSlotId,
  String? targetSlotId,
}) {
  final name = _itemName(db, itemId);
  final resolved = resolveCompareSlot(
    db,
    save,
    itemId,
    preferredSlotId: preferredSlotId,
    targetSlotId: targetSlotId,
  );
  if (resolved.slotId == null) {
    return EquipmentCompareResult(
      ok: false,
      reason: resolved.reason ?? 'That item cannot be equipped.',
      slotId: null,
      candidateItemId: itemId,
      candidateName: name,
      candidateEnchantmentId: enchantmentId,
      equippedItemId: null,
      equippedName: null,
      equippedEnchantmentId: null,
      displaced: const [],
      stats: const [],
      notes: const [],
    );
  }

  final slotId = resolved.slotId!;
  final current = slotStack(save, slotId);
  final displaced = <({String slotId, String? itemId, String? name})>[];

  if (isTwoHandedItem(db, itemId) && slotId == weaponToolSlotId) {
    final off = slotStack(save, offhandSlotId);
    if (off != null) {
      displaced.add((slotId: offhandSlotId, itemId: off.itemId, name: _itemName(db, off.itemId)));
    }
  } else if (slotId == offhandSlotId) {
    final mainId = slotItemId(save, weaponToolSlotId);
    if (isNotBlank(mainId) && isTwoHandedItem(db, mainId!)) {
      displaced.add((slotId: weaponToolSlotId, itemId: mainId, name: _itemName(db, mainId)));
    }
  }

  final preview = previewEquippedSave(
    db,
    save,
    itemId: itemId,
    slotId: slotId,
    enchantmentId: enchantmentId,
  );

  final againstBothHands = isTwoHandedItem(db, itemId) && slotId == weaponToolSlotId;
  final hands = againstBothHands ? _handsEquippedSide(db, save) : null;
  final equippedPresent = againstBothHands ? hands!.present : current != null;
  final equippedBits = againstBothHands
      ? hands!.bits
      : _itemDisplayBits(db, save, slotId, current?.itemId);
  final candidateBits = _itemDisplayBits(db, preview, slotId, itemId);

  final equippedRows = againstBothHands
      ? <EquipmentRow?>[
          if (slotStack(save, weaponToolSlotId) case final main?)
            equipmentForItemId(db, main.itemId),
          if (slotStack(save, offhandSlotId) case final off?) equipmentForItemId(db, off.itemId),
        ]
      : <EquipmentRow?>[if (current != null) equipmentForItemId(db, current.itemId)];

  final stats = <EquipCompareStatRow>[
    ..._combatStatRows(
      equippedPresent: equippedPresent,
      equipped: equippedBits,
      candidate: candidateBits,
    ),
    ..._extraStatRows(
      db,
      equippedPresent: equippedPresent,
      equippedRows: equippedRows,
      candidateRow: equipmentForItemId(db, itemId),
    ),
  ];

  final equippedItemId = againstBothHands ? hands!.itemId : current?.itemId;
  final equippedName = againstBothHands
      ? hands!.name
      : current == null
      ? null
      : _itemName(db, current.itemId);
  final equippedEnchantmentId = againstBothHands ? hands!.enchantmentId : current?.enchantmentId;

  final notes = <String>[
    for (final row in displaced) 'Also clears ${_slotName(db, row.slotId)}: ${row.name ?? 'Empty'}',
    if (againstBothHands) ...[
      for (final stack in [slotStack(save, weaponToolSlotId), slotStack(save, offhandSlotId)])
        if (stack != null)
          ..._itemNotes(db, stack.itemId, stack.enchantmentId).map((line) => 'Equipped: $line'),
    ] else
      ..._itemNotes(db, current?.itemId, current?.enchantmentId).map((line) => 'Equipped: $line'),
    ..._itemNotes(db, itemId, enchantmentId).map((line) => 'This item: $line'),
  ];

  return EquipmentCompareResult(
    ok: true,
    slotId: slotId,
    candidateItemId: itemId,
    candidateName: name,
    candidateEnchantmentId: enchantmentId,
    equippedItemId: equippedItemId,
    equippedName: equippedName,
    equippedEnchantmentId: equippedEnchantmentId,
    displaced: displaced,
    stats: stats,
    notes: notes,
  );
}
