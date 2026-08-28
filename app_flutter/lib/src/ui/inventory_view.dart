import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';
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

enum _InventoryTab { items, equipment }

/// Which pane [InventoryView] should open on, and whether the other is offered.
enum InventoryPane { items, equipment }

/// The bag and the worn gear, with the combat numbers they add up to.
class InventoryView extends StatefulWidget {
  const InventoryView({
    super.key,
    required this.controller,
    this.onClose,
    this.pane,
    this.showHeader = true,
  });

  final GameController controller;
  final VoidCallback? onClose;

  /// When set, only this pane is shown and the Items / Equipment toggle is hidden.
  final InventoryPane? pane;
  final bool showHeader;

  @override
  State<InventoryView> createState() => _InventoryViewState();
}

class _InventoryViewState extends State<InventoryView> {
  late _InventoryTab _tab = _paneTab(widget.pane);
  String? _message;
  bool _showSources = false;
  bool _showBonuses = false;
  InventorySortMode _sortMode = InventorySortMode.group;
  final TextEditingController _search = TextEditingController();
  late InventorySorter _sorter = InventorySorter(widget.controller.db);
  bool get _lockedPane => widget.pane != null;

  /// Character locks this to one pane. Prefer that over leftover inner-tab state
  /// so Equipment cannot keep showing the bag after Inventory.
  _InventoryTab get _activeTab => _lockedPane ? _paneTab(widget.pane) : _tab;

  static _InventoryTab _paneTab(InventoryPane? pane) =>
      pane == InventoryPane.equipment ? _InventoryTab.equipment : _InventoryTab.items;

  @override
  void didUpdateWidget(InventoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _sorter = InventorySorter(widget.controller.db);
    }
    if (oldWidget.pane != widget.pane) {
      _tab = _paneTab(widget.pane);
      _selling = null;
      _message = null;
      _showSources = false;
      _showBonuses = false;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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

  void _equipAt(int index) {
    final result = equipInventoryIndex(db, save, index);
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          children: [
            _header(),
            Expanded(child: _activeTab == _InventoryTab.items ? _bag() : _paperDoll()),
          ],
        ),
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
    );
  }

  Widget _header() {
    final selling = _selling;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showHeader)
            if (widget.onClose != null)
              PageHeader(title: 'Inventory', onClose: widget.onClose!)
            else
              const Text('Inventory', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w400)),
          if (_activeTab == _InventoryTab.items)
            Align(
              alignment: Alignment.centerRight,
              child: MutedText('${inventorySlotCount(save)} / $inventorySlotLimit slots'),
            ),
          if (!_lockedPane) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: GameButton(
                    label: 'Items',
                    compact: true,
                    selected: _activeTab == _InventoryTab.items,
                    tone: _activeTab == _InventoryTab.items
                        ? GameButtonTone.primary
                        : GameButtonTone.secondary,
                    onPressed: () => setState(() {
                      _tab = _InventoryTab.items;
                      _selling = null;
                      _message = null;
                      _showSources = false;
                      _showBonuses = false;
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GameButton(
                    label: 'Equipment',
                    compact: true,
                    selected: _activeTab == _InventoryTab.equipment,
                    tone: _activeTab == _InventoryTab.equipment
                        ? GameButtonTone.primary
                        : GameButtonTone.secondary,
                    onPressed: () => setState(() {
                      _tab = _InventoryTab.equipment;
                      _selling = null;
                      _message = null;
                    }),
                  ),
                ),
              ],
            ),
          ],
          if (selling != null) ...[
            const SizedBox(height: 8),
            Row(
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
            ),
          ] else if (_activeTab == _InventoryTab.items) ...[
            const SizedBox(height: 8),
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
                const Spacer(),
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
              const SizedBox(height: 8),
              TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Search by name', isDense: true),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _bag() {
    if (save.inventory.isEmpty) {
      return const Center(child: MutedText('No items yet. Fight or gather to fill this grid.'));
    }
    final selling = _selling;
    final indexes = _sorter.displayIndexes(save.inventory, _sortMode, _search.text);
    if (indexes.isEmpty) {
      return const Center(child: MutedText('Nothing in the bag matches.'));
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 84,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: indexes.length,
          itemBuilder: (context, visible) {
            final index = indexes[visible];
            final stack = save.inventory[index];
            final item = controller.indexes.itemsById[stack.itemId];
            final equippable = equipmentForItemId(db, stack.itemId)?.slotId != null;
            final canEat = _eatVisible && selling == null && isEdibleItem(db, stack.itemId);
            return _ItemTile(
              item: item,
              quantity: stack.quantity,
              enchanted: stack.enchantmentId != null,
              favorite: isFavoriteStack(stack),
              selected: selling?.containsKey(index) ?? false,
              selecting: selling != null,
              onEat: canEat ? () => _eatAt(inventoryIndex: index) : null,
              eatEnabled: !isInCombat(save),
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
        const SizedBox(height: 8),
        MutedText(
          selling != null
              ? 'Tap items to choose how many to sell, then confirm. Favorited items cannot be sold. '
                    'Shops pay full value; selling in the field pays half.'
              : 'Tap the heart to keep an item safe from selling. Tap gear to equip it, '
                    'and hold anything for its details.',
        ),
      ],
    );
  }

  Widget _paperDoll() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _combatStats(),
        const SizedBox(height: 10),
        // Four columns keep the paper-doll arrangement, but the whole doll is
        // capped so the slots stay tile-sized instead of filling the screen.
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [for (final slotId in equipmentGridOrder) _slotTile(slotId)],
            ),
          ),
        ),
        const SizedBox(height: 10),
        const MutedText(
          'Equipped spells are always active, and duplicates stack. Tap worn gear to take it '
          'off, or hold a slot for what it does.',
        ),
      ],
    );
  }

  Widget _slotTile(String slotId) {
    final stack = save.equipment.slots[slotId];
    final slot = db.equipmentSlots.where((row) => row.slotId == slotId).firstOrNull;
    if (stack == null) {
      return GamePanel(
        padding: const EdgeInsets.all(3),
        onTap: () => _showDetail(slotId: slotId),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SlotGlyph(slotId: slotId, size: 26),
            const SizedBox(height: 2),
            Flexible(
              child: Text(
                slot?.displayName ?? slotId,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 8.5, height: 1.1, color: Color(0x80F4E7C8)),
              ),
            ),
          ],
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
      onEat: _eatVisible && slotId == foodSlotId && isEdibleItem(db, stack.itemId)
          ? () => _eatAt()
          : null,
      eatEnabled: !isInCombat(save),
      onTap: () => _unequip(slotId),
      onLongPress: () => _showDetail(equipped: stack, slotId: slotId),
      onToggleFavorite: null,
    );
  }

  Widget _combatStats() {
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
                  label: _showBonuses ? 'Hide bonuses' : 'Show bonuses',
                  tone: GameButtonTone.secondary,
                  compact: true,
                  dense: true,
                  onPressed: () => setState(() => _showBonuses = !_showBonuses),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: GameButton(
                  label: _showSources ? 'Hide sources' : 'Show sources',
                  tone: GameButtonTone.secondary,
                  compact: true,
                  dense: true,
                  onPressed: () => setState(() => _showSources = !_showSources),
                ),
              ),
            ],
          ),
          if (_showBonuses && summary.activeBonuses.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 4), child: MutedText('No active bonuses.')),
          if (_showBonuses)
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
          if (_showSources) ...[
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
    return PopupMenuButton<InventorySortMode>(
      tooltip: 'Sort',
      initialValue: mode,
      color: Palette.parchmentDeep,
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
                color: Palette.parchmentText,
              ),
            ),
          ),
      ],
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF6A4A30), Color(0xFF45301F)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: mode == InventorySortMode.group ? const Color(0x73D4AF37) : Palette.gold,
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

/// One bag or slot tile: art, count, and the marks for enchanted and favorite.
/// The name lives on a tooltip so the icon can fill the cell.
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
    this.onEat,
    this.eatEnabled = true,
  });

  final ItemRow? item;
  final num quantity;
  final bool enchanted;
  final bool favorite;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onEat;
  final bool eatEnabled;

  @override
  Widget build(BuildContext context) {
    final name = item?.displayName ?? '?';
    return Tooltip(
      message: name,
      onTriggered: onLongPress,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: selected ? const Color(0x33D4AF37) : Palette.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? Palette.gold
                  : enchanted
                  ? Palette.softGreen
                  : Palette.edge,
              width: selected ? 2 : 1,
            ),
          ),
          child: Stack(
            children: [
              Center(child: ItemIcon(item: item, size: 36)),
              if (!enchanted && quantity > 1)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Text(
                    '${quantity.round()}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
                  ),
                ),
              if (onEat != null)
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: eatEnabled ? onEat : null,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Text(
                        'Eat',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w400,
                          color: eatEnabled ? Palette.gold : const Color(0x80F4E7C8),
                        ),
                      ),
                    ),
                  ),
                ),
              if (selected)
                const Positioned(
                  left: 0,
                  top: 0,
                  child: Icon(Icons.check, size: 14, color: Palette.gold),
                ),
              if (enchanted || (onToggleFavorite != null && !selecting))
                Positioned(
                  right: 0,
                  top: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (enchanted)
                        const Text('★', style: TextStyle(fontSize: 11, color: Palette.softGreen)),
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
                                color: favorite ? Palette.gold : const Color(0x80F4E7C8),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
