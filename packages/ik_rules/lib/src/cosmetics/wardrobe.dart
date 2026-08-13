import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../save/generated/save_models.dart';
import 'appearance.dart';
import 'cosmetics.dart';

String? _itemName(GameDatabase db, String itemId) {
  final displayName = db.items
      .firstWhereOrNull((row) => row.raw['Item ID'] == itemId)
      ?.raw['Display Name'];
  return displayName is String ? displayName : null;
}

String _slotLabel(CosmeticSlotRow slot) {
  final label = slot.raw['Display Name'];
  return label is String ? label : slot.raw['Cosmetic Slot ID'] as String;
}

/// One tab of the wardrobe, in table order.
class WardrobeSlotTab {
  const WardrobeSlotTab({required this.slotId, required this.label});

  final String slotId;
  final String label;

  Map<String, Object?> toJson() => <String, Object?>{'slotId': slotId, 'label': label};
}

List<WardrobeSlotTab> wardrobeSlotTabs(GameDatabase db) {
  return cosmeticSlots(db)
      .map(
        (slot) => WardrobeSlotTab(
          slotId: slot.raw['Cosmetic Slot ID'] as String,
          label: _slotLabel(slot),
        ),
      )
      .toList();
}

/// One owned cosmetic, as its tile reads.
class WardrobeTile {
  const WardrobeTile({
    required this.cosmeticId,
    required this.itemId,
    required this.name,
    required this.equipped,
  });

  final String cosmeticId;
  final String itemId;
  final String name;
  final bool equipped;

  Map<String, Object?> toJson() => <String, Object?>{
    'cosmeticId': cosmeticId,
    'itemId': itemId,
    'name': name,
    'equipped': equipped,
  };
}

/// The wardrobe's lower half for one slot: what is owned and what is worn.
class WardrobeSlotView {
  const WardrobeSlotView({
    required this.slotId,
    required this.label,
    required this.equippedCosmeticId,
    required this.tiles,
    required this.emptyNote,
  });

  final String slotId;
  final String label;
  final String? equippedCosmeticId;

  /// Only what the player owns — a wardrobe is not a catalogue.
  final List<WardrobeTile> tiles;

  /// What to say instead of tiles when the slot has nothing in it yet.
  final String emptyNote;

  Map<String, Object?> toJson() => <String, Object?>{
    'slotId': slotId,
    'label': label,
    'equippedCosmeticId': equippedCosmeticId,
    'tiles': tiles.map((tile) => tile.toJson()).toList(),
    'emptyNote': emptyNote,
  };
}

/// The wardrobe's view of one slot.
///
/// Falls back to the first slot when [slotId] names none, so a client can open
/// on a remembered tab without checking whether it still exists.
WardrobeSlotView? wardrobeSlotView(GameDatabase db, PlayerSave save, String slotId) {
  final slot = cosmeticSlotById(db, slotId) ?? cosmeticSlots(db).firstOrNull;
  if (slot == null) return null;
  final resolvedId = slot.raw['Cosmetic Slot ID'] as String;
  final equipped = equippedCosmeticId(save, resolvedId);

  return WardrobeSlotView(
    slotId: resolvedId,
    label: _slotLabel(slot),
    equippedCosmeticId: equipped,
    tiles: cosmeticsForSlot(db, resolvedId)
        .where((cosmetic) => isCosmeticUnlocked(save, cosmetic.raw['Cosmetic ID'] as String))
        .map((cosmetic) {
          final cosmeticId = cosmetic.raw['Cosmetic ID'] as String;
          final itemId = cosmetic.raw['Item ID'] as String;
          return WardrobeTile(
            cosmeticId: cosmeticId,
            itemId: itemId,
            name: _itemName(db, itemId) ?? cosmeticId,
            equipped: cosmeticId == equipped,
          );
        })
        .toList(),
    emptyNote: 'No ${_slotLabel(slot)} unlocked yet.',
  );
}

/// One appearance row: a label and the stops its slider can land on.
class AppearanceSlider {
  const AppearanceSlider({
    required this.category,
    required this.label,
    required this.optionIds,
    required this.selectedIndex,
  });

  final AppearanceCategory category;
  final String label;
  final List<String> optionIds;

  /// Index into [optionIds]; 0 when the save holds an option the table dropped.
  final int selectedIndex;

  Map<String, Object?> toJson() => <String, Object?>{
    'category': category.key,
    'label': label,
    'optionIds': optionIds,
    'selectedIndex': selectedIndex,
  };
}

/// The appearance rows, in category order, skipping any the content has no
/// options for.
///
/// Takes the appearance rather than the save because character creation picks a
/// look before there is a save to put it in.
List<AppearanceSlider> appearanceSliders(GameDatabase db, PlayerAppearance appearance) {
  final sliders = <AppearanceSlider>[];
  for (final category in AppearanceCategory.values) {
    final optionIds = appearanceOptions(
      db,
      category,
    ).map((row) => row.raw['Appearance Option ID'] as String).toList();
    if (optionIds.isEmpty) continue;
    final index = optionIds.indexOf(appearanceSelection(appearance, category));
    sliders.add(
      AppearanceSlider(
        category: category,
        label: appearanceCategoryLabel(category),
        optionIds: optionIds,
        selectedIndex: index < 0 ? 0 : index,
      ),
    );
  }
  return sliders;
}

/// What the popup says when a cosmetic is unlocked.
class CosmeticUnlockNotice {
  const CosmeticUnlockNotice({
    required this.cosmeticId,
    required this.itemId,
    required this.name,
    required this.hint,
  });

  final String cosmeticId;

  /// Null when the cosmetic has no item behind it, which only bad data causes.
  final String? itemId;
  final String name;

  /// The one-time "tap your portrait" line, for the player's first cosmetic.
  final String? hint;

  Map<String, Object?> toJson() => <String, Object?>{
    'cosmeticId': cosmeticId,
    'itemId': itemId,
    'name': name,
    'hint': hint,
  };
}

const String _wardrobeHint =
    'Tap your portrait in the top-left corner anytime to open the Wardrobe and equip it.';

CosmeticUnlockNotice? cosmeticUnlockNotice(GameDatabase db, String cosmeticId, bool isFirstEver) {
  final cosmetic = cosmeticById(db, cosmeticId);
  if (cosmetic == null) return null;
  final itemId = cosmetic.raw['Item ID'];
  return CosmeticUnlockNotice(
    cosmeticId: cosmeticId,
    itemId: itemId is String ? itemId : null,
    name: (itemId is String ? _itemName(db, itemId) : null) ?? cosmeticId,
    hint: isFirstEver ? _wardrobeHint : null,
  );
}
