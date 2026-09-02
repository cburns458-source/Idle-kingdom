import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'item_icon.dart';
import 'quantity_sheet.dart';

/// A shop counter: pick what to buy, pick what to sell, then confirm once.
///
/// Nothing is committed until Confirm, so a trade can pay for its purchases out
/// of its own sales — which is why the buy budget counts the offered sells.
class ShopPanel extends StatefulWidget {
  const ShopPanel({super.key, required this.controller, required this.shopId, this.onClose});

  final GameController controller;
  final String shopId;
  final VoidCallback? onClose;

  @override
  State<ShopPanel> createState() => _ShopPanelState();
}

class _ShopPanelState extends State<ShopPanel> {
  final Map<String, num> _buys = <String, num>{};
  final Map<String, num> _sells = <String, num>{};
  String? _error;
  String? _receipt;

  GameController get controller => widget.controller;
  GameDatabase get db => controller.db;
  PlayerSave get save => controller.save;

  List<ShopOfferLine> _lines(Map<String, num> from) {
    return from.entries
        .map((entry) => ShopOfferLine(itemId: entry.key, quantity: entry.value))
        .toList();
  }

  num _total(Map<String, num> from, num? Function(String itemId) unitPrice) {
    return from.entries.fold<num>(0, (sum, entry) {
      return sum + (unitPrice(entry.key) ?? 0) * entry.value;
    });
  }

  /// What this shop will take off the player, ignoring what cannot be traded.
  List<({String itemId, num owned, num unit})> _sellable(ShopRow shop) {
    final byItem = <String, ({String itemId, num owned, num unit})>{};
    for (final stack in save.inventory) {
      if (stack.enchantmentId != null || isFavoriteStack(stack)) continue;
      final unit = playerSellPrice(db, shop, stack.itemId);
      if (unit == null) continue;
      final existing = byItem[stack.itemId];
      byItem[stack.itemId] = (
        itemId: stack.itemId,
        owned: (existing?.owned ?? 0) + stack.quantity,
        unit: unit,
      );
    }
    return byItem.values.toList();
  }

  Future<void> _addBuy(ShopRow shop, String itemId, num unit, String name) async {
    final item = controller.indexes.itemsById[itemId];
    final nowMs = controller.session.clock();
    final remaining = shopRemainingToday(save, shop, itemId, nowMs);
    final already = _buys[itemId] ?? 0;
    // A cosmetic is a one-time unlock, so it is in the offer or it is not.
    if (item?.category == 'Cosmetic') {
      if (remaining != null && remaining < 1) {
        setState(() => _error = 'That item is sold out for today.');
        return;
      }
      setState(() {
        _error = null;
        if (_buys.remove(itemId) == null) _buys[itemId] = 1;
      });
      return;
    }

    final editing = already > 0;
    final budget =
        save.gold +
        _total(_sells, (id) => playerSellPrice(db, shop, id)) -
        _total(_buys, (id) => playerBuyPrice(db, shop, id));
    final available = budget + already * unit;
    final affordable = unit <= 0 ? null : (available / unit).floor();
    num? max;
    if (affordable != null && affordable >= 1) max = affordable;
    if (remaining != null) {
      max = max == null ? remaining : (max < remaining ? max : remaining);
    }
    if (max != null && max < 1) {
      setState(() => _error = 'That item is sold out for today.');
      return;
    }
    final quantity = await askQuantity(
      context,
      subtitle: 'Buy',
      title: name,
      details: [
        '${formatThousands(unit)} gold each',
        if (affordable != null)
          _sells.isEmpty
              ? 'Afford up to ${formatThousands(affordable)} with current gold'
              : 'Afford up to ${formatThousands(affordable)} counting the sells on offer',
        if (remaining != null) '${formatThousands(remaining)} left in today\'s stock',
      ],
      confirmLabel: editing ? 'Update offer' : 'Add to offer',
      initialValue: editing ? already.floor() : 1,
      max: max?.floor(),
      removeLabel: editing ? 'Remove from offer' : null,
    );
    if (!mounted) return;
    if (quantity == quantityRemoveSentinel) {
      setState(() {
        _error = null;
        _buys.remove(itemId);
      });
      return;
    }
    if (quantity == null) return;
    setState(() {
      _error = null;
      _buys[itemId] = editing ? quantity : already + quantity;
    });
  }

  /// Offers [itemId], or opens the pad again to change or take it off the counter.
  Future<void> _toggleSell(String itemId, num unit, String name, num owned) async {
    final already = _sells[itemId];
    final editing = already != null;
    final quantity = await askQuantity(
      context,
      subtitle: 'Sell',
      title: name,
      details: ['${formatThousands(unit)} gold each', 'You have ${formatThousands(owned)}'],
      confirmLabel: editing ? 'Update offer' : 'Add to offer',
      initialValue: editing ? already.floor() : 1,
      max: owned.floor(),
      removeLabel: editing ? 'Remove from offer' : null,
    );
    if (!mounted) return;
    if (quantity == quantityRemoveSentinel) {
      setState(() {
        _error = null;
        _sells.remove(itemId);
      });
      return;
    }
    if (quantity == null) return;
    setState(() {
      _error = null;
      _sells[itemId] = quantity;
    });
  }

  void _confirm() {
    final result = confirmShopOffer(
      db,
      save,
      widget.shopId,
      ShopOffer(buys: _lines(_buys), sells: _lines(_sells)),
      nowMs: controller.session.clock(),
    );
    if (!result.ok) {
      setState(() => _error = result.reason);
      return;
    }
    controller.commitLoadout(result.save!);
    controller.noteCosmeticUnlocks(result.cosmeticsGranted);
    setState(() {
      _error = null;
      _receipt = result.message;
      _buys.clear();
      _sells.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final shop = getShop(db, widget.shopId);
    if (shop == null) {
      return _frame(title: 'Shop unavailable', child: const MutedText('This counter is closed.'));
    }
    final access = canAccessShop(db, save, shop);
    final title = shop.raw['Display Name'] as String? ?? widget.shopId;
    if (!access.ok) {
      return _frame(
        title: title,
        child: Text(
          access.reason ?? 'You cannot trade here.',
          style: const TextStyle(color: Palette.danger),
        ),
      );
    }

    final buyTotal = _total(_buys, (id) => playerBuyPrice(db, shop, id));
    final sellTotal = _total(_sells, (id) => playerSellPrice(db, shop, id));
    final net = sellTotal - buyTotal;
    final nowMs = controller.session.clock();
    final stock = shopStockForPlayer(db, save, shop);
    final sellable = _sellable(shop);

    return _frame(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Offer — buy ${formatThousands(buyTotal)} / sell ${formatThousands(sellTotal)} · '
            'net ${net >= 0 ? '+' : ''}${formatThousands(net)} gold',
            style: const TextStyle(fontWeight: FontWeight.w400),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              GameButton(
                label: 'Clear offer',
                tone: GameButtonTone.secondary,
                compact: true,
                onPressed: _buys.isEmpty && _sells.isEmpty
                    ? null
                    : () => setState(() {
                        _buys.clear();
                        _sells.clear();
                        _error = null;
                      }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GameButton(
                  label: 'Confirm trade',
                  onPressed: _buys.isEmpty && _sells.isEmpty ? null : _confirm,
                ),
              ),
            ],
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 6),
            Text(error, style: const TextStyle(color: Palette.danger, fontSize: 12)),
          ],
          if (_receipt case final receipt?) ...[
            const SizedBox(height: 6),
            Text(receipt, style: const TextStyle(color: Palette.gold, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          // Stock on the left, the bag on the right, so a trade is one glance.
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Column(
                    heading: 'Buy',
                    empty: 'No stock listed.',
                    tiles: [
                      for (final entry in stock)
                        _tileFor(
                          itemId: entry.itemId,
                          unit: playerBuyPrice(db, shop, entry.itemId),
                          offered: _buys[entry.itemId],
                          remaining: shopRemainingToday(save, shop, entry.itemId, nowMs),
                          onTap: (unit, name) => _addBuy(shop, entry.itemId, unit, name),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _Column(
                    heading: 'Sell',
                    empty: 'Nothing here that this shop will buy.',
                    tiles: [
                      for (final row in sellable)
                        _tileFor(
                          itemId: row.itemId,
                          unit: row.unit,
                          owned: row.owned,
                          offered: _sells[row.itemId],
                          onTap: (unit, name) => _toggleSell(row.itemId, unit, name, row.owned),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _frame({required String title, required Widget child}) {
    return GamePanel(
      framed: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400),
                ),
              ),
              GoldAmount(
                amount: save.gold,
                style: const TextStyle(color: Palette.gold),
              ),
              if (widget.onClose != null)
                GameIconButton(icon: Icons.close, tooltip: 'Close', onPressed: widget.onClose),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(child: child),
        ],
      ),
    );
  }

  /// One stock or sell tile. [owned] is only shown on the sell side.
  Widget _tileFor({
    required String itemId,
    required num? unit,
    required void Function(num unit, String name) onTap,
    num? owned,
    num? offered,
    num? remaining,
  }) {
    final item = controller.indexes.itemsById[itemId];
    final name = item?.displayName ?? itemId;
    final soldOut = remaining != null && remaining <= 0;
    final enabled = unit != null && (owned == null || owned > 0) && !soldOut;

    return Tooltip(
      message: name,
      child: PixelInkPlate(
        onTap: enabled ? () => onTap(unit, name) : null,
        step: PixelChrome.stepTight,
        fillColor: offered != null
            ? Color.lerp(UiChrome.of(context).slot, UiChrome.of(context).embossFace, 0.18)!
            : UiChrome.of(context).slot,
        material: PixelPlateMaterial.none,
        strokeWidth: offered != null ? 2.5 : 2,
        selected: offered != null,
        shadow: false,
        padding: const EdgeInsets.fromLTRB(3, 5, 3, 4),
        child: Opacity(
          opacity: enabled ? 1 : 0.45,
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: Palette.parchmentText),
            child: Stack(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ItemIcon(item: item, size: 36),
                    const SizedBox(height: 2),
                    Text(
                      unit == null
                          ? '—'
                          : owned != null
                          ? '${formatThousands(unit)}g · ${formatThousands(owned)}'
                          : remaining == null
                          ? '${formatThousands(unit)}g'
                          : soldOut
                          ? 'sold out'
                          : '${formatThousands(unit)}g · ${formatThousands(remaining)} left',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, color: Palette.muted, height: 1.1),
                    ),
                  ],
                ),
                if (offered != null)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: const BoxDecoration(color: Color(0xE69A7B32)),
                      child: Text(
                        '×${formatThousands(offered)}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w400,
                          color: Color(0xFF1A1208),
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One side of the counter: a heading over a tight grid of items.
///
/// The grid fills leftover height under the offer so extra stock scrolls
/// inside the inventory instead of stretching the location page.
class _Column extends StatelessWidget {
  const _Column({required this.heading, required this.empty, required this.tiles});

  final String heading;
  final String empty;
  final List<Widget> tiles;

  static const double _tileExtent = 78;
  static const double _gap = 5;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(heading, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w400)),
        const SizedBox(height: 5),
        if (tiles.isEmpty)
          MutedText(empty)
        else
          Expanded(
            child: GridView.extent(
              maxCrossAxisExtent: _tileExtent,
              padding: EdgeInsets.zero,
              mainAxisSpacing: _gap,
              crossAxisSpacing: _gap,
              childAspectRatio: 1,
              children: tiles,
            ),
          ),
      ],
    );
  }
}
