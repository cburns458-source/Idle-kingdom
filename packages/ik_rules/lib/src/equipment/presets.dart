import 'dart:math' as math;

import 'package:ik_content/ik_content.dart';

import '../inventory/add_items.dart';
import '../inventory/capacity.dart';
import '../js_compat.dart';
import '../save/generated/save_models.dart';
import 'loadout.dart';

const int equipmentPresetCount = 4;
const int equipmentPresetNameMax = 24;

const String _bagFullReason = 'Not enough inventory space to switch presets.';
const String _missingReason = 'Missing items needed for that preset.';

EquipmentPresetIcon defaultEquipmentPresetIcon(int index) {
  return EquipmentPresetIcon(kind: 'roman', numeral: index + 1);
}

Map<String, EquippedStack?> emptyPresetSlots(Iterable<String> slotIds) {
  return <String, EquippedStack?>{for (final slotId in slotIds) slotId: null};
}

EquippedStack? cloneEquippedStack(EquippedStack? stack) {
  if (stack == null) return null;
  return EquippedStack(
    itemId: stack.itemId,
    quantity: stack.quantity,
    enchantmentId: stack.enchantmentId,
    favorite: stack.favorite == true ? true : null,
  );
}

Map<String, EquippedStack?> clonePresetSlots(Map<String, EquippedStack?> slots) {
  return <String, EquippedStack?>{
    for (final entry in slots.entries) entry.key: cloneEquippedStack(entry.value),
  };
}

List<EquipmentPreset> createDefaultEquipmentPresets(Iterable<String> slotIds) {
  final empty = emptyPresetSlots(slotIds);
  return <EquipmentPreset>[
    for (var index = 0; index < equipmentPresetCount; index += 1)
      EquipmentPreset(
        name: 'Preset ${index + 1}',
        icon: defaultEquipmentPresetIcon(index),
        slots: clonePresetSlots(empty),
      ),
  ];
}

class _NormalizedPresets {
  const _NormalizedPresets({
    required this.equipmentPresets,
    required this.activeEquipmentPresetIndex,
  });

  final List<EquipmentPreset> equipmentPresets;
  final num activeEquipmentPresetIndex;
}

_NormalizedPresets _normalizeEquipmentPresets(PlayerSave save) {
  final slotIds = save.equipment.slots.keys;
  final defaults = createDefaultEquipmentPresets(slotIds);
  final raw = save.equipmentPresets;
  final presets = <EquipmentPreset>[];
  for (var index = 0; index < equipmentPresetCount; index += 1) {
    final fallback = defaults[index];
    if (index >= raw.length) {
      presets.add(fallback);
      continue;
    }
    final row = raw[index];
    final trimmed = row.name.trim();
    final name = trimmed.isEmpty
        ? fallback.name
        : trimmed.substring(0, math.min(trimmed.length, equipmentPresetNameMax));
    final slots = <String, EquippedStack?>{...fallback.slots};
    for (final slotId in slotIds) {
      slots[slotId] = cloneEquippedStack(row.slots[slotId]);
    }
    presets.add(
      EquipmentPreset(name: name, icon: _normalizePresetIcon(row.icon, index), slots: slots),
    );
  }
  final active = math.max(
    0,
    math.min(equipmentPresetCount - 1, save.activeEquipmentPresetIndex.floor()),
  );
  return _NormalizedPresets(equipmentPresets: presets, activeEquipmentPresetIndex: active);
}

EquipmentPresetIcon _normalizePresetIcon(EquipmentPresetIcon icon, int index) {
  final kind = icon.kind;
  if (kind == 'coin') {
    return const EquipmentPresetIcon(kind: 'coin');
  }
  if (kind == 'skill' && isNotBlank(icon.skillId)) {
    return EquipmentPresetIcon(kind: 'skill', skillId: icon.skillId);
  }
  final numeral = math.max(1, math.min(4, (icon.numeral ?? (index + 1)).floor()));
  return EquipmentPresetIcon(kind: 'roman', numeral: numeral);
}

/// While preset 1 is active, keep its snapshot identical to the live loadout.
PlayerSave trackActiveEquipmentPreset(PlayerSave save) {
  final normalized = _normalizeEquipmentPresets(save);
  if (normalized.activeEquipmentPresetIndex != 0) {
    return save.copyWith(
      equipmentPresets: normalized.equipmentPresets,
      activeEquipmentPresetIndex: normalized.activeEquipmentPresetIndex,
    );
  }
  final next = <EquipmentPreset>[
    for (var index = 0; index < normalized.equipmentPresets.length; index += 1)
      if (index == 0)
        normalized.equipmentPresets[index].copyWith(slots: clonePresetSlots(save.equipment.slots))
      else
        normalized.equipmentPresets[index],
  ];
  return save.copyWith(
    equipmentPresets: next,
    activeEquipmentPresetIndex: normalized.activeEquipmentPresetIndex,
  );
}

PlayerSave saveActiveEquipmentPreset(PlayerSave save) {
  final normalized = _normalizeEquipmentPresets(save);
  final next = <EquipmentPreset>[
    for (var index = 0; index < normalized.equipmentPresets.length; index += 1)
      if (index == normalized.activeEquipmentPresetIndex)
        normalized.equipmentPresets[index].copyWith(slots: clonePresetSlots(save.equipment.slots))
      else
        normalized.equipmentPresets[index],
  ];
  return save.copyWith(
    equipmentPresets: next,
    activeEquipmentPresetIndex: normalized.activeEquipmentPresetIndex,
  );
}

PlayerSave renameEquipmentPreset(PlayerSave save, int index, String name) {
  final normalized = _normalizeEquipmentPresets(save);
  if (index < 0 || index >= equipmentPresetCount) return save;
  final trimmed = name.trim();
  if (trimmed.isEmpty) return save;
  final clipped = trimmed.substring(0, math.min(trimmed.length, equipmentPresetNameMax));
  final next = <EquipmentPreset>[
    for (var i = 0; i < normalized.equipmentPresets.length; i += 1)
      if (i == index)
        normalized.equipmentPresets[i].copyWith(name: clipped)
      else
        normalized.equipmentPresets[i],
  ];
  return save.copyWith(
    equipmentPresets: next,
    activeEquipmentPresetIndex: normalized.activeEquipmentPresetIndex,
  );
}

PlayerSave setEquipmentPresetIcon(PlayerSave save, int index, EquipmentPresetIcon icon) {
  final normalized = _normalizeEquipmentPresets(save);
  if (index < 0 || index >= equipmentPresetCount) return save;
  final next = <EquipmentPreset>[
    for (var i = 0; i < normalized.equipmentPresets.length; i += 1)
      if (i == index)
        normalized.equipmentPresets[i].copyWith(icon: _normalizePresetIcon(icon, index))
      else
        normalized.equipmentPresets[i],
  ];
  return save.copyWith(
    equipmentPresets: next,
    activeEquipmentPresetIndex: normalized.activeEquipmentPresetIndex,
  );
}

class _PoolEntry {
  _PoolEntry({
    required this.itemId,
    required this.quantity,
    required this.enchantmentId,
    required this.favorite,
  });

  final String itemId;
  num quantity;
  final String? enchantmentId;
  final bool favorite;
}

String _stackKey(String itemId, String? enchantmentId, bool favorite) {
  return '$itemId\u0000${enchantmentId ?? ''}\u0000${favorite ? '1' : '0'}';
}

bool _takeFromPool(Map<String, _PoolEntry> pool, EquippedStack need) {
  final key = _stackKey(need.itemId, need.enchantmentId, need.favorite == true);
  final entry = pool[key];
  if (entry == null || entry.quantity < need.quantity) return false;
  entry.quantity -= need.quantity;
  if (entry.quantity <= 0) pool.remove(key);
  return true;
}

/// Instant in-place swap to a stored preset.
EquipResult applyEquipmentPreset(GameDatabase db, PlayerSave save, int index) {
  // db reserved for future requirement checks on apply.
  final _ = db;
  final normalized = _normalizeEquipmentPresets(save);
  if (index < 0 || index >= equipmentPresetCount) {
    return const EquipResult.failed('That preset does not exist.');
  }
  var working = save.copyWith(
    equipmentPresets: normalized.equipmentPresets,
    activeEquipmentPresetIndex: normalized.activeEquipmentPresetIndex,
  );
  if (working.activeEquipmentPresetIndex == 0) {
    working = trackActiveEquipmentPreset(working);
  }
  if (index == working.activeEquipmentPresetIndex) {
    return EquipResult.ok(working);
  }

  final target = clonePresetSlots(working.equipmentPresets[index].slots);
  final slotIds = working.equipment.slots.keys.toList();
  final pool = <String, _PoolEntry>{};

  void addToPool(String itemId, num quantity, String? enchantmentId, bool favorite) {
    final key = _stackKey(itemId, enchantmentId, favorite);
    final existing = pool[key];
    if (existing != null) {
      existing.quantity += quantity;
    } else {
      pool[key] = _PoolEntry(
        itemId: itemId,
        quantity: quantity,
        enchantmentId: enchantmentId,
        favorite: favorite,
      );
    }
  }

  for (final slotId in slotIds) {
    final equipped = working.equipment.slots[slotId];
    if (equipped != null && equipped.quantity > 0) {
      addToPool(
        equipped.itemId,
        equipped.quantity,
        equipped.enchantmentId,
        equipped.favorite == true,
      );
    }
  }
  for (final stack in working.inventory) {
    if (stack.quantity > 0) {
      addToPool(stack.itemId, stack.quantity, stack.enchantmentId, stack.favorite == true);
    }
  }

  for (final slotId in slotIds) {
    final want = target[slotId];
    if (want == null || want.quantity <= 0) continue;
    if (!_takeFromPool(pool, want)) {
      return const EquipResult.failed(_missingReason);
    }
  }

  var bagProbe = working.copyWith(
    equipment: EquipmentLoadout(
      slots: <String, EquippedStack?>{for (final id in slotIds) id: null},
    ),
    inventory: const <InventoryStack>[],
  );
  for (final entry in pool.values) {
    if (!canFitItemQuantity(
      bagProbe,
      entry.itemId,
      entry.quantity,
      entry.enchantmentId,
      entry.favorite,
    )) {
      return const EquipResult.failed(_bagFullReason);
    }
    bagProbe = addItemToInventory(
      bagProbe,
      entry.itemId,
      entry.quantity,
      entry.enchantmentId,
      entry.favorite,
    );
  }

  final presets = index == 0
      ? <EquipmentPreset>[
          for (var i = 0; i < working.equipmentPresets.length; i += 1)
            if (i == 0)
              working.equipmentPresets[i].copyWith(slots: clonePresetSlots(target))
            else
              working.equipmentPresets[i],
        ]
      : working.equipmentPresets;

  return EquipResult.ok(
    working.copyWith(
      equipment: EquipmentLoadout(slots: target),
      inventory: bagProbe.inventory,
      activeEquipmentPresetIndex: index,
      equipmentPresets: presets,
    ),
  );
}
