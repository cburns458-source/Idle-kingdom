import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../combat/stats.dart';
import '../js_compat.dart';
import '../projects/enchantments.dart';
import '../save/generated/save_models.dart';
import '../spells/spells.dart';
import 'loadout.dart';
import 'tooltips.dart';

/// How a compared value moved relative to the currently equipped gear.
enum EquipCompareDeltaKind { improved, reduced, unchanged, special }

/// One labeled difference between the candidate and what it would replace.
class EquipCompareLine {
  const EquipCompareLine({
    required this.label,
    required this.kind,
    required this.detail,
    this.before,
    this.after,
  });

  final String label;
  final EquipCompareDeltaKind kind;

  /// Human-readable summary, e.g. `+20` or `clears off-hand`.
  final String detail;
  final String? before;
  final String? after;

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'kind': kind.name,
    'detail': detail,
    if (before != null) 'before': before,
    if (after != null) 'after': after,
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
    required this.lines,
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
  final List<EquipCompareLine> lines;

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
    'lines': lines.map((line) => line.toJson()).toList(),
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
({String? slotId, String? reason}) resolveCompareSlot(
  GameDatabase db,
  PlayerSave save,
  String itemId, {
  String? preferredSlotId,
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

EquipCompareDeltaKind _kindForSigned(num delta) {
  if (delta > 0) return EquipCompareDeltaKind.improved;
  if (delta < 0) return EquipCompareDeltaKind.reduced;
  return EquipCompareDeltaKind.unchanged;
}

String _fmtNum(num value) => jsNumberToString(value);

String _fmtRange(DamageRange range) => '${_fmtNum(range.min)}–${_fmtNum(range.max)}';

String _signed(num delta) {
  if (delta > 0) return '+${_fmtNum(delta)}';
  if (delta < 0) return _fmtNum(delta);
  return '0';
}

List<EquipCompareLine> _diffCombatTotals(GameDatabase db, PlayerSave before, PlayerSave after) {
  final lines = <EquipCompareLine>[];
  final dmgBefore = playerDamageRange(db, before);
  final dmgAfter = playerDamageRange(db, after);
  final dmgMin = dmgAfter.min - dmgBefore.min;
  final dmgMax = dmgAfter.max - dmgBefore.max;
  final dmgKind = dmgMin == 0 && dmgMax == 0
      ? EquipCompareDeltaKind.unchanged
      : (dmgMin + dmgMax) >= 0
      ? (dmgMin < 0 || dmgMax < 0 ? EquipCompareDeltaKind.special : EquipCompareDeltaKind.improved)
      : EquipCompareDeltaKind.reduced;
  lines.add(
    EquipCompareLine(
      label: 'Attack damage',
      kind: dmgKind,
      detail: dmgKind == EquipCompareDeltaKind.unchanged
          ? 'unchanged'
          : '${_signed(dmgMin)} / ${_signed(dmgMax)}',
      before: _fmtRange(dmgBefore),
      after: _fmtRange(dmgAfter),
    ),
  );

  final offBefore = playerOffhandDamageRange(db, before);
  final offAfter = playerOffhandDamageRange(db, after);
  if (offBefore != null || offAfter != null) {
    final beforeLabel = offBefore == null ? 'none' : _fmtRange(offBefore);
    final afterLabel = offAfter == null ? 'none' : _fmtRange(offAfter);
    final kind = beforeLabel == afterLabel
        ? EquipCompareDeltaKind.unchanged
        : offAfter == null
        ? EquipCompareDeltaKind.reduced
        : offBefore == null
        ? EquipCompareDeltaKind.improved
        : (offAfter.min + offAfter.max) >= (offBefore.min + offBefore.max)
        ? EquipCompareDeltaKind.improved
        : EquipCompareDeltaKind.reduced;
    lines.add(
      EquipCompareLine(
        label: 'Off-hand damage',
        kind: kind,
        detail: kind == EquipCompareDeltaKind.unchanged
            ? 'unchanged'
            : '$beforeLabel → $afterLabel',
        before: beforeLabel,
        after: afterLabel,
      ),
    );
  }

  final hpBefore = playerMaxHp(db, before);
  final hpAfter = playerMaxHp(db, after);
  final hpDelta = hpAfter - hpBefore;
  lines.add(
    EquipCompareLine(
      label: 'Health',
      kind: _kindForSigned(hpDelta),
      detail: hpDelta == 0 ? 'unchanged' : _signed(hpDelta),
      before: _fmtNum(hpBefore),
      after: _fmtNum(hpAfter),
    ),
  );

  final drBefore = playerDamageReduction(db, before);
  final drAfter = playerDamageReduction(db, after);
  final drDelta = drAfter - drBefore;
  lines.add(
    EquipCompareLine(
      label: 'Damage reduction',
      kind: _kindForSigned(drDelta),
      detail: drDelta == 0 ? 'unchanged' : _signed(drDelta),
      before: _fmtNum(drBefore),
      after: _fmtNum(drAfter),
    ),
  );

  return lines;
}

List<EquipCompareLine> _diffItemLines(
  GameDatabase db,
  String candidateItemId,
  String? candidateEnchantmentId,
  String? equippedItemId,
  String? equippedEnchantmentId,
) {
  final lines = <EquipCompareLine>[];
  final candidateStats = equipmentTooltipStatLines(equipmentForItemId(db, candidateItemId), db);
  final equippedStats = equippedItemId == null
      ? const <String>[]
      : equipmentTooltipStatLines(equipmentForItemId(db, equippedItemId), db);

  final candidateSet = candidateStats.toSet();
  final equippedSet = equippedStats.toSet();
  for (final line in candidateStats) {
    if (equippedSet.contains(line)) {
      lines.add(
        EquipCompareLine(label: line, kind: EquipCompareDeltaKind.unchanged, detail: 'unchanged'),
      );
    } else {
      lines.add(
        EquipCompareLine(label: line, kind: EquipCompareDeltaKind.improved, detail: 'gained'),
      );
    }
  }
  for (final line in equippedStats) {
    if (!candidateSet.contains(line)) {
      lines.add(EquipCompareLine(label: line, kind: EquipCompareDeltaKind.reduced, detail: 'lost'));
    }
  }

  final candEnch = enchantmentTooltipLines(db, candidateEnchantmentId);
  final eqEnch = enchantmentTooltipLines(db, equippedEnchantmentId);
  for (final line in candEnch) {
    lines.add(
      EquipCompareLine(
        label: line,
        kind: EquipCompareDeltaKind.special,
        detail: 'candidate enchantment',
      ),
    );
  }
  for (final line in eqEnch) {
    if (!candEnch.contains(line)) {
      lines.add(
        EquipCompareLine(
          label: line,
          kind: EquipCompareDeltaKind.special,
          detail: 'equipped enchantment',
        ),
      );
    }
  }

  if (isSpellItem(db, candidateItemId)) {
    final spellLines = spellTooltipLines(
      db,
      db.items.firstWhereOrNull((row) => row.itemId == candidateItemId),
      candidateItemId,
    );
    for (final line in spellLines) {
      lines.add(
        EquipCompareLine(label: line, kind: EquipCompareDeltaKind.special, detail: 'spell'),
      );
    }
  }

  return lines;
}

/// Compares equipping [itemId] against the gear it would replace.
///
/// Uses [playerDamageRange], [playerMaxHp], and [playerDamageReduction] on a
/// preview loadout. Never mutates [save] and never moves inventory stacks.
EquipmentCompareResult compareEquipmentCandidate(
  GameDatabase db,
  PlayerSave save, {
  required String itemId,
  String? enchantmentId,
  String? preferredSlotId,
}) {
  final name = _itemName(db, itemId);
  final resolved = resolveCompareSlot(db, save, itemId, preferredSlotId: preferredSlotId);
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
      lines: const [],
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

  final lines = <EquipCompareLine>[
    EquipCompareLine(
      label: 'Slot',
      kind: EquipCompareDeltaKind.special,
      detail: _slotName(db, slotId),
    ),
    ..._diffCombatTotals(db, save, preview),
    ..._diffItemLines(db, itemId, enchantmentId, current?.itemId, current?.enchantmentId),
  ];

  for (final row in displaced) {
    lines.add(
      EquipCompareLine(
        label: 'Also clears ${_slotName(db, row.slotId)}',
        kind: EquipCompareDeltaKind.special,
        detail: row.name ?? 'Empty',
      ),
    );
  }

  return EquipmentCompareResult(
    ok: true,
    slotId: slotId,
    candidateItemId: itemId,
    candidateName: name,
    candidateEnchantmentId: enchantmentId,
    equippedItemId: current?.itemId,
    equippedName: current == null ? null : _itemName(db, current.itemId),
    equippedEnchantmentId: current?.enchantmentId,
    displaced: displaced,
    lines: lines,
  );
}
