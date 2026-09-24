import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'floating_slot.dart';
import 'format.dart';
import 'equipment_presets_bar.dart';
import 'game_popup.dart';
import 'item_detail_sheet.dart';
import 'item_icon.dart';
import 'overlay_notice.dart';
import 'page_header.dart';
import 'quantity_sheet.dart';

/// Paper-doll order: 4 columns × 4 rows, spells down the right-hand column.
const List<String> equipmentGridOrder = <String>[
  'SLOT-0008', // Neck
  'SLOT-0003', // Helmet
  'SLOT-0010', // Back
  'SLOT-0013', // Spell 1
  'SLOT-0001', // Weapon / Tool
  'SLOT-0004', // Chest
  'SLOT-0002', // Off-hand / Shield
  'SLOT-0014', // Spell 2
  'SLOT-0009', // Ring
  'SLOT-0005', // Legs
  'SLOT-0007', // Gloves
  'SLOT-0015', // Spell 3
  'SLOT-0011', // Food
  'SLOT-0006', // Boots
  'SLOT-0012', // Potion
  'SLOT-0016', // Spell 4
];

/// Bag tiles aim for 6–8 per row in the playable column.
const double inventoryBagTileExtent = 52;
const double inventoryBagTileSpacing = 4;
const double inventoryBagIconSize = 24;

/// Item / glyph size inside a paper-doll well. The well stays full-size.
double paperDollArtSize(double side) => ((side - 6).clamp(20.0, 48.0) * 0.9);

/// The bag and the worn gear, with the combat numbers they add up to.
class InventoryView extends StatefulWidget {
  const InventoryView({
    super.key,
    required this.controller,
    this.onClose,
    this.showHeader = true,
    this.onOpenCodexItem,
  });

  final GameController controller;
  final VoidCallback? onClose;
  final bool showHeader;
  final ValueChanged<String>? onOpenCodexItem;

  @override
  State<InventoryView> createState() => _InventoryViewState();
}

class _InventoryViewState extends State<InventoryView> {
  String? _message;
  InventorySortMode _sortMode = InventorySortMode.group;
  final TextEditingController _search = TextEditingController();
  late InventorySorter _sorter = InventorySorter(widget.controller.db);

  /// Cached bag order; invalidated when inventory, sort, or search change.
  List<int>? _cachedBagIndexes;
  int? _bagCacheInventoryIdentity;
  int? _bagCacheInventoryLength;
  InventorySortMode? _bagCacheSortMode;
  String? _bagCacheSearch;

  /// Equippable lookup per item id for this database.
  final Map<String, bool> _equippableByItemId = <String, bool>{};

  @override
  void didUpdateWidget(InventoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _sorter = InventorySorter(widget.controller.db);
      _equippableByItemId.clear();
      _invalidateBagCache();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _invalidateBagCache() {
    _cachedBagIndexes = null;
    _bagCacheInventoryIdentity = null;
    _bagCacheInventoryLength = null;
    _bagCacheSortMode = null;
    _bagCacheSearch = null;
  }

  List<int> _bagIndexes(PlayerSave save) {
    final identity = identityHashCode(save.inventory);
    final length = save.inventory.length;
    final search = _search.text;
    if (_cachedBagIndexes != null &&
        _bagCacheInventoryIdentity == identity &&
        _bagCacheInventoryLength == length &&
        _bagCacheSortMode == _sortMode &&
        _bagCacheSearch == search) {
      return _cachedBagIndexes!;
    }
    final indexes = _sorter.displayIndexes(save.inventory, _sortMode, search);
    _cachedBagIndexes = indexes;
    _bagCacheInventoryIdentity = identity;
    _bagCacheInventoryLength = length;
    _bagCacheSortMode = _sortMode;
    _bagCacheSearch = search;
    return indexes;
  }

  bool _isEquippable(String itemId) {
    return _equippableByItemId.putIfAbsent(
      itemId,
      () => equipmentForItemId(db, itemId)?.slotId != null,
    );
  }

  /// Non-null while picking stacks to sell; values are chosen quantities.
  Map<int, int>? _selling;

  GameController get controller => widget.controller;
  GameDatabase get db => controller.db;
  PlayerSave get save => controller.save;

  void _exitSellMode() {
    setState(() {
      _selling = null;
      _message = null;
    });
  }

  bool get _eatVisible => controller.showEatButton;

  void _eatAt({int? inventoryIndex}) {
    final reason = controller.eatFood(inventoryIndex: inventoryIndex);
    if (!mounted) return;
    setState(() => _message = reason);
  }

  void _equipAt(int index, {String? preferredSlotId}) {
    final result = equipInventoryIndex(db, save, index, preferredSlotId: preferredSlotId);
    if (!result.ok) {
      setState(() => _message = result.reason);
      return;
    }
    setState(() => _message = null);
    controller.commitLoadout(result.save!);
  }

  void _unequip(String slotId) {
    final result = unequipSlot(save, slotId);
    if (!result.ok) {
      setState(() => _message = result.reason);
      return;
    }
    setState(() => _message = null);
    controller.commitLoadout(result.save!);
  }

  void _toggleFavorite(int index) {
    final next = toggleInventoryFavorite(save, index);
    if (next == null) return;
    setState(() {
      _message = null;
      // Favorites sort to the front, so any sell selection now points elsewhere.
      if (_selling != null) _selling = <int, int>{};
    });
    controller.commitLoadout(next);
  }

  Future<void> _toggleSelection(int index) async {
    final stack = save.inventory[index];
    if (isFavoriteStack(stack)) {
      setState(() => _message = 'Favorited items cannot be sold. Unfavorite them first.');
      return;
    }
    final selling = _selling;
    if (selling == null) return;
    if (selling.containsKey(index)) {
      setState(() {
        final next = Map<int, int>.from(selling)..remove(index);
        _selling = next;
      });
      return;
    }
    final priced = sellPriceAtLocation(db, save, stack.itemId);
    if (priced == null) {
      setState(() => _message = 'That item cannot be sold.');
      return;
    }
    final name =
        db.items.firstWhere((item) => item.raw['Item ID'] == stack.itemId).raw['Display Name']
            as String? ??
        'Item';
    final quantity = await askQuantity(
      context,
      title: 'Sell $name',
      details: <String>[
        '${formatThousands(priced.unitPrice)} gold each',
        '${formatThousands(stack.quantity)} in bag',
      ],
      confirmLabel: 'Select',
      initialValue: stack.quantity.toInt(),
      min: 1,
      max: stack.quantity.toInt(),
    );
    if (!mounted || quantity == null) return;
    setState(() {
      _message = null;
      _selling = <int, int>{...selling, index: quantity};
    });
  }

  /// What the current selection is worth, skipping what cannot be sold.
  num get _selectedGold {
    final selling = _selling;
    if (selling == null) return 0;
    return selling.entries.fold<num>(0, (sum, entry) {
      if (entry.key >= save.inventory.length) return sum;
      final stack = save.inventory[entry.key];
      if (stack.enchantmentId != null || isFavoriteStack(stack)) return sum;
      final priced = sellPriceAtLocation(db, save, stack.itemId);
      if (priced == null) return sum;
      return sum + priced.unitPrice * entry.value;
    });
  }

  Future<void> _confirmSell() async {
    final selected = _selling;
    if (selected == null || selected.isEmpty) return;
    final gold = _selectedGold;
    final confirmed = await showGameAlert(
      context: context,
      title: 'Sell items?',
      message: 'Sell ${pluralize(selected.length, 'stack')} for ${formatThousands(gold)} gold.',
      confirmLabel: 'Confirm sell',
      cancelLabel: 'Keep items',
      placement: GamePopupPlacement.center,
    );
    if (!confirmed || !mounted) return;

    final result = sellInventoryQuantities(db, save, selected);
    if (!result.ok) {
      setState(() {
        _message = result.reason;
        _selling = <int, int>{};
      });
      return;
    }
    controller.commitLoadout(result.save!);
    setState(() {
      _message = result.message;
      _selling = null;
    });
  }

  void _showDetail({
    InventoryStack? stack,
    EquippedStack? equipped,
    String? slotId,
    int? inventoryIndex,
  }) {
    final itemId = stack?.itemId ?? equipped?.itemId;
    final canEquip =
        inventoryIndex != null && itemId != null && equipmentForItemId(db, itemId)?.slotId != null;
    final canEat =
        _eatVisible &&
        itemId != null &&
        isEdibleItem(db, itemId) &&
        (inventoryIndex != null || slotId == foodSlotId);
    showGamePopup<void>(
      context: context,
      origin: popupOrigin(context),
      builder: (context) => ItemDetailSheet(
        controller: controller,
        itemId: itemId,
        quantity: stack?.quantity ?? equipped?.quantity ?? 0,
        enchantmentId: stack?.enchantmentId ?? equipped?.enchantmentId,
        slotId: slotId,
        eatEnabled: !isInCombat(save),
        onEat: canEat
            ? () {
                if (!mounted) return;
                _eatAt(inventoryIndex: inventoryIndex);
              }
            : null,
        onEquip: canEquip
            ? () {
                if (!mounted) return;
                _equipAt(inventoryIndex);
              }
            : null,
        onOpenCodex: itemId != null && widget.onOpenCodexItem != null
            ? () => widget.onOpenCodexItem!(itemId)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: GamePanel(
              framed: true,
              padding: EdgeInsets.zero,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _body(),
                  if (_message case final message?)
                    Positioned(
                      top: 8,
                      left: 12,
                      right: 12,
                      child: OverlayNotice(
                        key: ValueKey(message),
                        text: message,
                        tone: Palette.danger,
                        onDismissed: () => setState(() => _message = null),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _header() {
    if (!widget.showHeader) return const SizedBox.shrink();
    if (widget.onClose != null) {
      return PageHeader(
        title: 'Inventory',
        onClose: widget.onClose!,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      );
    }
    return const Padding(
      padding: EdgeInsets.fromLTRB(10, 8, 10, 4),
      child: Text('Inventory', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400)),
    );
  }

  /// Sell, slot count, and sort sit on the bag — not above the paper doll.
  Widget _bagToolbar() {
    final selling = _selling;
    return KeyedSubtree(
      key: const Key('inventory-bag-toolbar'),
      child: selling != null
          ? Row(
              children: [
                GameButton(
                  label: 'Cancel',
                  tone: GameButtonTone.secondary,
                  compact: true,
                  onPressed: _exitSellMode,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GameButton(
                    label: selling.isEmpty
                        ? 'Sell selected'
                        : 'Sell selected (${formatThousands(_selectedGold)}g)',
                    onPressed: selling.isEmpty ? null : _confirmSell,
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    GameButton(
                      label: 'Sell items',
                      tone: GameButtonTone.secondary,
                      compact: true,
                      dense: true,
                      onPressed: save.inventory.isEmpty
                          ? null
                          : () => setState(() {
                              _selling = <int, int>{};
                              _message = null;
                            }),
                    ),
                    Expanded(
                      child: Center(
                        child: MutedText('${inventorySlotCount(save)} / $inventorySlotLimit slots'),
                      ),
                    ),
                    _SortMenu(
                      mode: _sortMode,
                      onSelected: (mode) => setState(() {
                        _sortMode = mode;
                        if (mode != InventorySortMode.search) _search.clear();
                        _message = null;
                      }),
                    ),
                  ],
                ),
                if (_sortMode == InventorySortMode.search) ...[
                  const SizedBox(height: 6),
                  TextField(
                    controller: _search,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'Search by name', isDense: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _body() {
    // Doll + toolbar stay fixed; the bag owns its own scroll viewport so only
    // on-screen tiles layout/paint (look unchanged, scroll work drops a lot).
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RepaintBoundary(child: _dollRow()),
          const SizedBox(height: 8),
          _bagToolbar(),
          const SizedBox(height: 8),
          Expanded(child: RepaintBoundary(child: _bag())),
        ],
      ),
    );
  }

  /// Presets left of the doll, Attributes and Eat on the right. The sheet is
  /// as wide as the playable column so the side chips do not crush the slots.
  Widget _dollRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EquipmentPresetsBar(
          controller: controller,
          axis: Axis.vertical,
          compact: true,
          showSettingsButton: true,
          onMessage: (message) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
          },
        ),
        const SizedBox(width: 6),
        Expanded(
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: [for (final slotId in equipmentGridOrder) _slotTile(slotId)],
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 96,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GameButton(
                key: const Key('inventory-attributes'),
                label: 'Attributes',
                tone: GameButtonTone.secondary,
                compact: true,
                dense: true,
                onPressed: _openAttributes,
              ),
              const SizedBox(height: 8),
              GameButton(
                key: const Key('inventory-stance'),
                label: 'Stance',
                tone: GameButtonTone.secondary,
                compact: true,
                dense: true,
                onPressed: _openStanceMenu,
              ),
              const SizedBox(height: 8),
              GameButton(
                key: const Key('inventory-eat'),
                label: 'Eat',
                tone: GameButtonTone.secondary,
                compact: true,
                dense: true,
                onPressed: _openEatMenu,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openAttributes() {
    return showGamePopup<void>(
      context: context,
      origin: popupOrigin(context),
      builder: (dialogContext) {
        var showBonuses = false;
        var showSources = false;
        return StatefulBuilder(
          builder: (context, setOverlay) {
            return GamePopupCard(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Attributes',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
                          ),
                        ),
                        GameButton(
                          label: 'Close',
                          tone: GameButtonTone.secondary,
                          compact: true,
                          dense: true,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _combatStats(
                      showBonuses: showBonuses,
                      showSources: showSources,
                      onToggleBonuses: () => setOverlay(() => showBonuses = !showBonuses),
                      onToggleSources: () => setOverlay(() => showSources = !showSources),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openStanceMenu() {
    return showGamePopup<void>(
      context: context,
      origin: popupOrigin(context),
      builder: (dialogContext) {
        return GamePopupCard(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final style = normalizeAttackStyle(save.attackStyle);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Stance',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
                        ),
                      ),
                      GameButton(
                        label: 'Close',
                        tone: GameButtonTone.secondary,
                        compact: true,
                        dense: true,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final entry in const <(String, String)>[
                    ('offensive', 'Offensive'),
                    ('balanced', 'Balanced'),
                    ('defensive', 'Defensive'),
                  ]) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: GameButton(
                        label: entry.$2,
                        selected: style == entry.$1,
                        tone: style == entry.$1 ? GameButtonTone.primary : GameButtonTone.secondary,
                        onPressed: () => controller.setAttackStyle(entry.$1),
                      ),
                    ),
                  ],
                  MutedText(_attackStyleHint(style)),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _openEatMenu() {
    return showGamePopup<void>(
      context: context,
      origin: popupOrigin(context),
      builder: (dialogContext) {
        return GamePopupCard(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Eat',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
                        ),
                      ),
                      GameButton(
                        label: 'Close',
                        tone: GameButtonTone.secondary,
                        compact: true,
                        dense: true,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _eatAtHealth(),
                  const SizedBox(height: 10),
                  GameButton(
                    key: const Key('auto-eat'),
                    label: controller.autoEat ? 'Auto-eat on' : 'Auto-eat off',
                    selected: controller.autoEat,
                    tone: controller.autoEat ? GameButtonTone.primary : GameButtonTone.secondary,
                    onPressed: () => controller.setAutoEat(!controller.autoEat),
                  ),
                  const SizedBox(height: 6),
                  const MutedText(
                    'Eats after a finished gather, thievery, or combat round when HP is at the threshold. Off also stops combat and thievery auto-eat. Manual Eat still works outside combat.',
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _bag() {
    if (save.inventory.isEmpty) {
      return const Padding(
        key: Key('inventory-bag'),
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: MutedText('No items yet. Fight or gather to fill this grid.')),
      );
    }
    final selling = _selling;
    final indexes = _bagIndexes(save);
    if (indexes.isEmpty) {
      return const Padding(
        key: Key('inventory-bag'),
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: MutedText('Nothing in the bag matches.')),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: GridView.builder(
            key: const Key('inventory-bag'),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: inventoryBagTileExtent,
              mainAxisSpacing: inventoryBagTileSpacing,
              crossAxisSpacing: inventoryBagTileSpacing,
            ),
            itemCount: indexes.length,
            itemBuilder: (context, visible) {
              final index = indexes[visible];
              final stack = save.inventory[index];
              final item = controller.indexes.itemsById[stack.itemId];
              final equippable = _isEquippable(stack.itemId);
              return _ItemTile(
                item: item,
                quantity: stack.quantity,
                enchanted: stack.enchantmentId != null,
                favorite: isFavoriteStack(stack),
                selected: selling?.containsKey(index) ?? false,
                selecting: selling != null,
                iconSize: inventoryBagIconSize,
                onTap: () {
                  if (selling != null) {
                    _toggleSelection(index);
                  } else if (equippable) {
                    _equipAt(index);
                  } else {
                    _showDetail(stack: stack, inventoryIndex: index);
                  }
                },
                onLongPress: () => _showDetail(stack: stack, inventoryIndex: index),
                onToggleFavorite: () => _toggleFavorite(index),
              );
            },
          ),
        ),
        if (selling != null) ...[
          const SizedBox(height: 8),
          const MutedText(
            'Tap items to choose how many to sell, then confirm. Favorited items cannot be sold. '
            'Shops pay full value; selling in the field pays half.',
          ),
        ],
      ],
    );
  }

  Widget _eatAtHealth() {
    final maxHp = playerMaxHp(db, save);
    final cap = maxHp <= 0 ? 1.0 : maxHp.toDouble();
    final percent = clampEatHealthThresholdPercent(save.settings.eatHealthThresholdPercent);
    final asPercent = save.settings.eatHealthThresholdAsPercent;
    final hpValue = eatHealthThresholdHp(cap, percent);
    final sliderMax = asPercent ? 100.0 : cap;
    final sliderValue = asPercent ? percent.toDouble() : hpValue.toDouble();
    final divisions = asPercent ? 99 : (cap > 1 ? cap.round() - 1 : 1);
    final label = asPercent ? '${percent.round()}%' : '${hpValue.round()} HP';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: MutedText('Eat at $label')),
            GameButton(
              label: asPercent ? '%' : 'HP',
              tone: GameButtonTone.secondary,
              compact: true,
              dense: true,
              onPressed: () => controller.setEatHealthThresholdAsPercent(!asPercent),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Palette.gold,
            inactiveTrackColor: Palette.edge,
            thumbColor: Palette.gold,
            overlayShape: SliderComponentShape.noOverlay,
            trackHeight: 4,
          ),
          child: Slider(
            value: sliderValue.clamp(1, sliderMax).toDouble(),
            min: 1,
            max: sliderMax < 1 ? 1 : sliderMax,
            divisions: divisions < 1 ? 1 : divisions,
            label: label,
            onChanged: (value) {
              if (asPercent) {
                controller.setEatHealthThresholdPercent(value.round());
              } else {
                controller.setEatHealthThresholdHp(value.round(), cap);
              }
            },
          ),
        ),
      ],
    );
  }

  bool _itemFitsSlot(String itemId, String slotId) => itemFitsEquipmentSlot(db, itemId, slotId);

  Future<void> _openSlotEquipPicker(String slotId) async {
    final slot = db.equipmentSlots.where((row) => row.slotId == slotId).firstOrNull;
    final candidates = <({int? index, EquippedStack stack})>[
      for (var i = 0; i < save.inventory.length; i += 1)
        if (_itemFitsSlot(save.inventory[i].itemId, slotId))
          (
            index: i,
            stack: EquippedStack(
              itemId: save.inventory[i].itemId,
              quantity: save.inventory[i].quantity,
              enchantmentId: save.inventory[i].enchantmentId,
              favorite: save.inventory[i].favorite == true ? true : null,
            ),
          ),
    ];
    if (candidates.isEmpty) {
      setState(() => _message = 'No items in your bag fit that slot.');
      return;
    }
    final chosen = await showGamePopup<({int? index, EquippedStack stack})>(
      context: context,
      builder: (context) {
        return GamePopupCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Equip — ${slot?.displayName ?? slotId}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final entry = candidates[i];
                    final item = controller.indexes.itemsById[entry.stack.itemId];
                    final name = item?.displayName ?? entry.stack.itemId;
                    final qty = entry.stack.quantity;
                    return GamePanel(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      onTap: () => Navigator.of(context).pop(entry),
                      child: Row(
                        children: [
                          ItemIcon(item: item, size: 28),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              qty > 1 ? '$name ×$qty' : name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || chosen == null) return;
    if (chosen.index != null) {
      _equipAt(chosen.index!, preferredSlotId: slotId);
    }
  }

  Widget _slotTile(String slotId) {
    final stack = save.equipment.slots[slotId];
    final slot = db.equipmentSlots.where((row) => row.slotId == slotId).firstOrNull;
    return KeyedSubtree(
      key: Key('equipment-slot-$slotId'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.maxWidth < constraints.maxHeight
              ? constraints.maxWidth
              : constraints.maxHeight;
          final iconSize = paperDollArtSize(side);
          if (stack == null) {
            return Tooltip(
              message: slot?.displayName ?? slotId,
              child: PixelInkPlate(
                onTap: () => _openSlotEquipPicker(slotId),
                step: PixelChrome.stepTight,
                fillColor: UiChrome.of(context).slot,
                material: PixelPlateMaterial.grain,
                strokeWidth: 2,
                shadow: false,
                padding: const EdgeInsets.all(2),
                child: Center(
                  child: SlotGlyph(slotId: slotId, size: iconSize),
                ),
              ),
            );
          }

          return _ItemTile(
            item: controller.indexes.itemsById[stack.itemId],
            quantity: stack.quantity,
            enchanted: stack.enchantmentId != null,
            favorite: false,
            selected: false,
            selecting: false,
            framedWell: true,
            iconSize: iconSize,
            onTap: () => _unequip(slotId),
            onLongPress: () => _showDetail(equipped: stack, slotId: slotId),
            onToggleFavorite: null,
          );
        },
      ),
    );
  }

  Widget _combatStats({
    required bool showBonuses,
    required bool showSources,
    required VoidCallback onToggleBonuses,
    required VoidCallback onToggleSources,
  }) {
    final summary = playerCombatStatSummary(db, save);
    final damage = summary.damage;
    final offhand = summary.offhandDamage;
    return GamePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Stat(
                label: 'Damage',
                value: offhand == null
                    ? '${damage.min}–${damage.max}'
                    : '${damage.min}–${damage.max} · OH ${offhand.min}–${offhand.max}',
              ),
              _Stat(label: 'Health', value: '${summary.maxHp}'),
              _Stat(label: 'DR', value: '${summary.damageReduction}'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Flexible(
                child: GameButton(
                  label: showBonuses ? 'Hide bonuses' : 'Show bonuses',
                  tone: GameButtonTone.secondary,
                  compact: true,
                  dense: true,
                  onPressed: onToggleBonuses,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: GameButton(
                  label: showSources ? 'Hide sources' : 'Show sources',
                  tone: GameButtonTone.secondary,
                  compact: true,
                  dense: true,
                  onPressed: onToggleSources,
                ),
              ),
            ],
          ),
          if (showBonuses && summary.activeBonuses.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 4), child: MutedText('No active bonuses.')),
          if (showBonuses)
            for (final bonus in summary.activeBonuses)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: bonus.name,
                        style: const TextStyle(fontWeight: FontWeight.w400),
                      ),
                      TextSpan(text: ' — ${bonus.effect}'),
                    ],
                  ),
                  style: const TextStyle(fontSize: 12, height: 1.3),
                ),
              ),
          if (showSources) ...[
            _breakdownSection('Main-hand', summary.mainhandBreakdown),
            if (summary.offhandBreakdown.isNotEmpty)
              _breakdownSection('Off-hand', summary.offhandBreakdown),
            _breakdownSection('Health', summary.healthBreakdown),
            _breakdownSection('Damage reduction', summary.reductionBreakdown),
          ],
        ],
      ),
    );
  }

  String _attackStyleHint(String style) {
    return switch (style) {
      'offensive' => '+1% damage · kill XP to Might',
      'defensive' => '+1 DR · kill XP to Vitality',
      _ => 'No stance bonus · kill XP split 50/50',
    };
  }

  Widget _breakdownSection(String title, List<CombatStatContribution> lines) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Expanded(child: MutedText(line.label)),
                  Text(
                    line.detail,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.mode, required this.onSelected});

  final InventorySortMode mode;
  final ValueChanged<InventorySortMode> onSelected;

  static String _label(InventorySortMode mode) {
    return switch (mode) {
      InventorySortMode.group => 'Group',
      InventorySortMode.az => 'A–Z',
      InventorySortMode.search => 'Search',
    };
  }

  @override
  Widget build(BuildContext context) {
    final chrome = UiChrome.of(context);
    return PopupMenuButton<InventorySortMode>(
      tooltip: 'Sort',
      initialValue: mode,
      color: chrome.board,
      position: PopupMenuPosition.under,
      offset: const Offset(-80, 4),
      constraints: const BoxConstraints(minWidth: 148, maxWidth: 180),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final option in InventorySortMode.values)
          CheckedPopupMenuItem<InventorySortMode>(
            value: option,
            checked: option == mode,
            child: Text(
              _label(option),
              style: TextStyle(
                fontFamily: gameFontFamily,
                fontWeight: FontWeight.w400,
                color: chrome.primaryLabel,
              ),
            ),
          ),
      ],
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: chrome.secondaryFill,
          borderRadius: BorderRadius.zero /* pixel step 3 */,
          border: Border.all(
            color: mode == InventorySortMode.group ? chrome.embossFace : chrome.embossFaceSelected,
          ),
          boxShadow: const [BoxShadow(offset: Offset(0, 2), color: Color(0x40000000))],
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            'Sort',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: Color(0xFFFFF4D4)),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MutedText(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w400)),
        ],
      ),
    );
  }
}

/// One bag tile: art, count, and the marks for enchanted and favorite.
/// The name lives on a tooltip so the icon can fill the cell.
///
/// Paper-doll equipment wells stay bordered ([framedWell]); bag cells float.
class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.item,
    required this.quantity,
    required this.enchanted,
    required this.favorite,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleFavorite,
    this.iconSize = inventoryBagIconSize,
    this.framedWell = false,
  });

  final ItemRow? item;
  final num quantity;
  final bool enchanted;
  final bool favorite;
  final bool selected;
  final bool selecting;
  final double iconSize;
  final bool framedWell;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final name = item?.displayName ?? '?';
    final marks = Stack(
      children: [
        Center(
          child: ItemIcon(item: item, size: iconSize),
        ),
        if (!enchanted && quantity > 1)
          Positioned(
            right: 0,
            bottom: 0,
            child: Text(
              '${quantity.round()}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w400,
                color: framedWell ? Palette.parchmentText : Palette.panelInk,
              ),
            ),
          ),
        if (enchanted || (onToggleFavorite != null && !selecting))
          Positioned(
            right: 0,
            top: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (enchanted)
                  Text(
                    '★',
                    style: TextStyle(
                      fontSize: 11,
                      color: framedWell ? Palette.softGreen : Palette.softGreenShade,
                    ),
                  ),
                if (onToggleFavorite != null && !selecting)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onToggleFavorite,
                    child: Tooltip(
                      message: favorite ? 'Unfavorite' : 'Favorite',
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          favorite ? Icons.favorite : Icons.favorite_border,
                          size: 14,
                          color: favorite
                              ? Palette.gold
                              : framedWell
                              ? const Color(0x80F4E7C8)
                              : const Color(0x806B5338),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );

    if (framedWell) {
      final slot = UiChrome.of(context).slot;
      final fill = selected
          ? Color.lerp(slot, Palette.gold, 0.18)!
          : enchanted
          ? const Color(0xFF2F3A24)
          : slot;
      return Tooltip(
        message: name,
        onTriggered: onLongPress,
        child: PixelInkPlate(
          onTap: onTap,
          step: PixelChrome.stepTight,
          fillColor: fill,
          material: PixelPlateMaterial.grain,
          strokeWidth: selected ? 2.5 : 2,
          selected: selected || enchanted,
          shadow: false,
          padding: const EdgeInsets.all(2),
          child: GestureDetector(
            onLongPress: onLongPress,
            onSecondaryTap: onLongPress,
            behavior: HitTestBehavior.deferToChild,
            child: DefaultTextStyle.merge(
              style: const TextStyle(color: Palette.parchmentText),
              child: marks,
            ),
          ),
        ),
      );
    }

    return FloatingItemSlot(
      tooltip: name,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTap: onLongPress,
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Palette.panelInk),
        child: marks,
      ),
    );
  }
}
