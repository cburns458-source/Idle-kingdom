import 'package:ik_rules/ik_rules.dart';

/// Gear commands that wait a moment and leave as one [set_loadout].
const hostedLoadoutCommands = <String>{'equip_index', 'unequip_slot', 'equipment_preset_apply'};

/// The worn slots the server should match, named by item rather than bag index.
Map<String, Object?> loadoutCommandArgs(PlayerSave save) {
  final slots = <Map<String, Object?>>[];
  for (final entry in save.equipment.slots.entries) {
    final stack = entry.value;
    if (stack == null || stack.quantity <= 0) continue;
    final enchantment = stack.enchantmentId;
    slots.add(<String, Object?>{
      'slotId': entry.key,
      'itemId': stack.itemId,
      'quantity': stack.quantity,
      if (enchantment != null && enchantment.isNotEmpty) 'enchantmentId': enchantment,
      if (stack.favorite == true) 'favorite': true,
    });
  }
  return <String, Object?>{
    'slots': slots,
    'activeEquipmentPresetIndex': save.activeEquipmentPresetIndex,
  };
}
