import '../inventory/add_items.dart';
import '../inventory/bank.dart';
import '../inventory/capacity.dart';
import '../json_support.dart';
import '../save/generated/save_models.dart';

const String guildBankSectionMain = 'main';
const String guildBankSectionUpForGrabs = 'up_for_grabs';

class GuildBankItem {
  const GuildBankItem({
    required this.id,
    required this.itemId,
    required this.quantity,
    required this.section,
    this.enchantmentId,
  });

  factory GuildBankItem.fromJson(Map<String, Object?> json) => GuildBankItem(
    id: json['id'] as String? ?? '',
    itemId: json['itemId'] as String? ?? '',
    quantity: json['quantity'] is num ? json['quantity']! as num : 0,
    section: json['section'] as String? ?? guildBankSectionMain,
    enchantmentId: json['enchantmentId'] as String?,
  );

  final String id;
  final String itemId;
  final num quantity;
  final String? enchantmentId;
  final String section;

  GuildBankItem copyWith({num? quantity, String? section}) => GuildBankItem(
    id: id,
    itemId: itemId,
    quantity: quantity ?? this.quantity,
    enchantmentId: enchantmentId,
    section: section ?? this.section,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'itemId': itemId,
    'quantity': quantity,
    if (enchantmentId != null) 'enchantmentId': enchantmentId,
    'section': section,
  };
}

class GuildBankState {
  const GuildBankState({this.items = const <GuildBankItem>[]});

  factory GuildBankState.fromJson(Map<String, Object?> json) => GuildBankState(
    items: json['items'] is List
        ? (json['items']! as List)
              .where((row) => row is Map)
              .map((row) => GuildBankItem.fromJson(asJsonMap(row)))
              .toList()
        : const <GuildBankItem>[],
  );

  final List<GuildBankItem> items;

  List<GuildBankItem> section(String name) => items.where((row) => row.section == name).toList();

  Map<String, Object?> toJson() => <String, Object?>{
    'items': items.map((row) => row.toJson()).toList(),
  };
}

class GuildBankActionResult {
  const GuildBankActionResult.ok({required this.save, required this.bank}) : reason = null;

  const GuildBankActionResult.failed(this.reason) : save = null, bank = null;

  final PlayerSave? save;
  final GuildBankState? bank;
  final String? reason;

  bool get ok => reason == null;
}

const String guildBankFullRefusal = 'The guild bank is full ($bankSlotLimit slots).';
const String guildBankUntradeableRefusal = "That stays with you; it can't be traded.";
const String guildBankGoldRefusal = 'Gold stays on you.';
const String guildBankEmptyRefusal = 'That stack is not there.';

GuildBankState emptyGuildBank() => const GuildBankState();

bool _sameStack(GuildBankItem row, String itemId, String? enchantmentId) =>
    row.itemId == itemId && row.enchantmentId == enchantmentId;

class _SectionAdd {
  const _SectionAdd.ok(this.items) : reason = null;
  const _SectionAdd.failed(this.reason) : items = null;
  final List<GuildBankItem>? items;
  final String? reason;
  bool get ok => reason == null;
}

class _SectionTake {
  const _SectionTake.ok(this.items, this.taken) : reason = null;
  const _SectionTake.failed(this.reason) : items = null, taken = 0;
  final List<GuildBankItem>? items;
  final num taken;
  final String? reason;
  bool get ok => reason == null;
}

_SectionAdd _addToSection(
  List<GuildBankItem> items,
  String section,
  String itemId,
  num quantity,
  String? enchantmentId,
  String Function() nextId,
) {
  final sectionRows = items.where((row) => row.section == section).toList();
  final others = items.where((row) => row.section != section).toList();
  if (enchantmentId != null && enchantmentId.isNotEmpty) {
    if (sectionRows.length >= bankSlotLimit) return const _SectionAdd.failed(guildBankFullRefusal);
    return _SectionAdd.ok(<GuildBankItem>[
      ...others,
      ...sectionRows,
      GuildBankItem(
        id: nextId(),
        itemId: itemId,
        quantity: quantity,
        enchantmentId: enchantmentId,
        section: section,
      ),
    ]);
  }
  final at = sectionRows.indexWhere((row) => _sameStack(row, itemId, null));
  if (at >= 0) {
    final next = [...sectionRows];
    final combined = next[at].quantity + quantity;
    next[at] = next[at].copyWith(
      quantity: combined > inventoryStackMax ? inventoryStackMax : combined,
    );
    return _SectionAdd.ok(<GuildBankItem>[...others, ...next]);
  }
  if (sectionRows.length >= bankSlotLimit) return const _SectionAdd.failed(guildBankFullRefusal);
  return _SectionAdd.ok(<GuildBankItem>[
    ...others,
    ...sectionRows,
    GuildBankItem(id: nextId(), itemId: itemId, quantity: quantity, section: section),
  ]);
}

_SectionTake _takeFromSection(
  List<GuildBankItem> items,
  String section,
  String itemId,
  num quantity,
  String? enchantmentId,
) {
  final sectionRows = items.where((row) => row.section == section).toList();
  final others = items.where((row) => row.section != section).toList();
  final at = sectionRows.indexWhere((row) => _sameStack(row, itemId, enchantmentId));
  if (at < 0) return const _SectionTake.failed(guildBankEmptyRefusal);
  final stack = sectionRows[at];
  final want = quantity.floor();
  if (want <= 0) return const _SectionTake.failed('Choose a quantity.');
  final taken = want < stack.quantity.floor() ? want : stack.quantity.floor();
  final next = [...sectionRows];
  if (taken >= stack.quantity) {
    next.removeAt(at);
  } else {
    next[at] = stack.copyWith(quantity: stack.quantity - taken);
  }
  return _SectionTake.ok(<GuildBankItem>[...others, ...next], taken);
}

GuildBankActionResult depositToGuildBank(
  GuildBankState bank,
  PlayerSave save,
  int inventoryIndex,
  num quantity,
  String Function() nextId,
) {
  if (inventoryIndex < 0 || inventoryIndex >= save.inventory.length) {
    return const GuildBankActionResult.failed(guildBankEmptyRefusal);
  }
  final stack = save.inventory[inventoryIndex];
  if (stackIsUnbankableGold(stack)) {
    return const GuildBankActionResult.failed(guildBankGoldRefusal);
  }
  final want = quantity.floor();
  if (want <= 0) return const GuildBankActionResult.failed('Choose a quantity.');
  final takenQty = want < stack.quantity.floor() ? want : stack.quantity.floor();
  final added = _addToSection(
    bank.items,
    guildBankSectionMain,
    stack.itemId,
    takenQty,
    stack.enchantmentId,
    nextId,
  );
  if (!added.ok) return GuildBankActionResult.failed(added.reason!);
  final nextInventory = [...save.inventory];
  if (takenQty >= stack.quantity) {
    nextInventory.removeAt(inventoryIndex);
  } else {
    nextInventory[inventoryIndex] = stack.copyWith(quantity: stack.quantity - takenQty);
  }
  return GuildBankActionResult.ok(
    save: save.copyWith(inventory: nextInventory),
    bank: GuildBankState(items: added.items!),
  );
}

GuildBankActionResult _giveToPlayer(
  GuildBankState bank,
  PlayerSave save,
  String section,
  String itemId,
  num quantity,
  String? enchantmentId,
) {
  final taken = _takeFromSection(bank.items, section, itemId, quantity, enchantmentId);
  if (!taken.ok) return GuildBankActionResult.failed(taken.reason!);
  final added = addItemToInventoryExact(save, itemId, taken.taken, enchantmentId);
  if (!added.ok) return GuildBankActionResult.failed(added.reason ?? 'The bag is full.');
  return GuildBankActionResult.ok(
    save: added.save!,
    bank: GuildBankState(items: taken.items!),
  );
}

GuildBankActionResult withdrawFromGuildBank(
  GuildBankState bank,
  PlayerSave save,
  String itemId,
  num quantity, [
  String? enchantmentId,
]) {
  return _giveToPlayer(bank, save, guildBankSectionMain, itemId, quantity, enchantmentId);
}

GuildBankActionResult takeGuildBankUpForGrabs(
  GuildBankState bank,
  PlayerSave save,
  String itemId,
  num quantity, [
  String? enchantmentId,
]) {
  return _giveToPlayer(bank, save, guildBankSectionUpForGrabs, itemId, quantity, enchantmentId);
}

GuildBankActionResult moveGuildBankToUpForGrabs(
  GuildBankState bank,
  PlayerSave save,
  String itemId,
  num quantity,
  String? enchantmentId,
  String Function() nextId,
) {
  final taken = _takeFromSection(bank.items, guildBankSectionMain, itemId, quantity, enchantmentId);
  if (!taken.ok) return GuildBankActionResult.failed(taken.reason!);
  final added = _addToSection(
    taken.items!,
    guildBankSectionUpForGrabs,
    itemId,
    taken.taken,
    enchantmentId,
    nextId,
  );
  if (!added.ok) return GuildBankActionResult.failed(added.reason!);
  return GuildBankActionResult.ok(
    save: save,
    bank: GuildBankState(items: added.items!),
  );
}
