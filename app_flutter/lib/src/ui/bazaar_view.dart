import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'game_popup.dart';
import 'item_icon.dart';
import 'page_header.dart';
import 'quantity_sheet.dart';
import 'social_bits.dart';

/// The exchange, opened from the hamburger wherever the player is standing.
///
/// The screen is the player's six slots and nothing else. There is no tab bar
/// and no book of everybody's offers: a slot is either empty, in which case it
/// offers to become a buy or a sell, or it holds one order and shows how far
/// through it is. Buying and selling are things a slot does, so they are not
/// also buttons somewhere else.
///
/// Nothing here decides anything. Every read and every write goes through
/// [MultiplayerController] to the server, which is the only thing that knows
/// what a save can afford; a save that comes back from a placement is adopted
/// rather than worked out. The Citadel notice board is a separate screen and
/// stays what it is.
class BazaarView extends StatefulWidget {
  const BazaarView({
    super.key,
    required this.controller,
    required this.multiplayer,
    required this.onClose,
  });

  final GameController controller;
  final MultiplayerController multiplayer;
  final VoidCallback onClose;

  @override
  State<BazaarView> createState() => _BazaarViewState();
}

/// Where the screen is. Null is the six slots; the rest are one deep, never
/// stacked, so closing always lands back on the slots.
sealed class _BazaarRoute {
  const _BazaarRoute();
}

/// Choosing what to trade: the item list for a buy, the bag for a sell.
class _PickRoute extends _BazaarRoute {
  const _PickRoute(this.side);
  final BazaarSide side;
}

/// The chosen item, with a quantity and a price to name.
class _ComposeRoute extends _BazaarRoute {
  const _ComposeRoute(this.side, this.itemId);
  final BazaarSide side;
  final String itemId;
}

class _BazaarViewState extends State<BazaarView> {
  final TextEditingController _search = TextEditingController();
  late final CodexIndex _codex = CodexIndex(controller.db);

  _BazaarRoute? _route;

  /// Group filter on the buy list, the same one the Codex offers.
  int? _group;

  /// What the two sections on the compose page currently say.
  int _quantity = 1;
  int _price = 1;

  GameController get controller => widget.controller;
  MultiplayerController get net => widget.multiplayer;
  PlayerSave get save => controller.save;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Whatever another screen last said is not about the exchange.
      net.announce(null);
      net.refreshMarket();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  ItemRow? _item(String itemId) => controller.indexes.itemsById[itemId];

  String _name(String itemId) => _item(itemId)?.displayName ?? itemId;

  MarketPrice? _guide(String itemId) => net.market.pricesByItem[itemId];

  /// What the exchange would suggest an item is worth: what it has been trading
  /// at, or failing that what a shop would give, which is at least a number a
  /// player recognises.
  int _suggestedPrice(String itemId) {
    final guide = _guide(itemId)?.averagePrice.floor();
    if (guide != null && guide > 0) return guide;
    return baseSellValue(_item(itemId))?.floor().clamp(1, bazaarOfferValueCap) ?? 1;
  }

  void _pick(BazaarSide side) {
    setState(() {
      _route = _PickRoute(side);
      _group = null;
      _search.clear();
    });
  }

  void _compose(BazaarSide side, String itemId) {
    final onHand = bazaarTradableOnHand(save, itemId, controller.db).floor();
    setState(() {
      _route = _ComposeRoute(side, itemId);
      // A sell defaults to the whole stack, because that is usually the intent;
      // a buy has no such number to borrow, so it starts at one.
      _quantity = side == bazaarSell ? onHand.clamp(1, bazaarOfferValueCap) : 1;
      _price = _suggestedPrice(itemId);
    });
  }

  /// Closes one step: the picker or the compose page first, the screen last.
  void _close() {
    if (_route != null) {
      setState(() {
        _route = null;
        _search.clear();
      });
      return;
    }
    widget.onClose();
  }

  Future<void> _place(BazaarSide side, String itemId) async {
    await net.placeMarketOffer(
      side: side,
      itemId: itemId,
      unitPrice: _price,
      quantity: _quantity,
      save: save,
      onSaved: controller.commitLoadout,
    );
    if (!mounted) return;
    // Placed or refused, the slots are where the answer shows.
    setState(() => _route = null);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: net,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: _title,
            onClose: _close,
            trailing: GoldAmount(
              amount: save.gold,
              style: const TextStyle(color: Palette.gold),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: !_tradable ? _closed() : _routed(),
            ),
          ),
        ],
      ),
    );
  }

  String get _title {
    return switch (_route) {
      _PickRoute(:final side) => side == bazaarBuy ? 'Buy' : 'Sell',
      _ComposeRoute(:final itemId) => _name(itemId),
      null => 'Bazaar',
    };
  }

  Widget _routed() {
    return switch (_route) {
      _PickRoute(:final side) => side == bazaarBuy ? _buyList() : _sellList(),
      _ComposeRoute(:final side, :final itemId) => _composePage(side, itemId),
      null => _slots(),
    };
  }

  /// Whether there is an exchange to read at all.
  ///
  /// A local demo has no other players in it, so its slots would never fill
  /// whatever was drawn; saying so beats a screen a player would wait on.
  bool get _tradable => net.isSignedIn && net.mode != MultiplayerMode.local;

  Widget _closed() {
    return GamePanel(
      framed: true,
      child: SignedOutNotice(
        title: 'Bazaar',
        prompt: net.mode == MultiplayerMode.local ? bazaarHostedOnly : bazaarSignInToTrade,
        showTitle: false,
      ),
    );
  }

  // --- The six slots ---------------------------------------------------------

  Widget _slots() {
    final slots = bazaarSlotViews(net.market.orders);
    final box = net.market.collect;
    return _framed(
      children: [
        for (final slot in slots) ...[
          _Slot(
            view: slot,
            name: slot.order == null ? '' : _name(slot.order!.itemId),
            item: slot.order == null ? null : _item(slot.order!.itemId),
            busy: net.busy,
            onBuy: () => _pick(bazaarBuy),
            onSell: () => _pick(bazaarSell),
            onCancel: slot.order == null ? null : () => net.cancelMarketOffer(slot.order!.id),
          ),
          const SizedBox(height: 8),
        ],
        _Heading(
          title: 'Collection box',
          action: box.isEmpty
              ? null
              : GameButton(
                  label: 'Collect',
                  compact: true,
                  onPressed: net.busy
                      ? null
                      : () => net.collectMarketBox(save, controller.commitLoadout),
                ),
        ),
        if (box.isEmpty)
          const MutedText(bazaarEmptyCollection)
        else
          for (final entry in box)
            _Row(
              item: entry.isGold ? null : _item(entry.itemId!),
              title: entry.isGold
                  ? '${formatThousands(entry.gold)} gold'
                  : '${_name(entry.itemId!)} ×${formatThousands(entry.quantity)}',
              lines: <String>[_collectReason(entry.reason)],
              gold: entry.isGold,
            ),
        _Heading(
          title: 'Recent trades',
          action: GameButton(
            key: const Key('bazaar-recent-trades'),
            label: 'Open',
            compact: true,
            onPressed: _openRecentTrades,
          ),
        ),
      ],
    );
  }

  /// The history is a look back, not something to act on, so it sits behind a
  /// button rather than lengthening the slots the screen is actually for.
  Future<void> _openRecentTrades() {
    return showGamePopup<void>(
      context: context,
      origin: popupOrigin(context),
      builder: (dialogContext) {
        return GamePopupCard(
          child: ListenableBuilder(
            listenable: net,
            builder: (context, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Recent trades',
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
                  if (net.market.trades.isEmpty)
                    const MutedText(bazaarEmptyHistory)
                  else
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            for (final trade in net.market.trades) _tradeRow(trade),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _tradeRow(MarketTrade trade) {
    return _Row(
      item: _item(trade.itemId),
      title:
          '${trade.isCancelled ? (trade.isBuy ? 'Cancelled buy' : 'Cancelled sell') : (trade.isBuy ? 'Bought' : 'Sold')} '
          '${_name(trade.itemId)} ×${formatThousands(trade.quantity)}',
      lines: <String>[
        if (trade.isCancelled)
          '${formatThousands(trade.unitPrice)} each · offer cancelled'
        else
          '${formatThousands(trade.unitPrice)} each · '
              '${formatThousands(trade.net)} gold ${trade.isBuy ? 'paid' : 'received'}',
        if (trade.tax > 0) 'Tax ${formatThousands(trade.tax)}',
      ],
    );
  }

  String _collectReason(String reason) {
    switch (reason) {
      case bazaarCollectBought:
        return 'Bought';
      case bazaarCollectSold:
        return 'Sold, after tax';
      case bazaarCollectCancelled:
        return 'Cancelled offer';
      case bazaarCollectRefund:
        return 'Change from a buy offer';
      default:
        return reason;
    }
  }

  // --- Buy: everything the exchange deals in ---------------------------------

  Widget _buyList() {
    final rows = _codex
        .itemsMatching(group: _group, query: _search.text)
        .where((entry) => bazaarItemTradable(controller.db, entry.itemId))
        .toList();

    return _framed(
      search: 'Search for an item',
      // The whole catalogue, not only what is on offer: a buy order is worth
      // placing precisely when nobody is selling yet.
      above: SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _FilterChip(
              label: 'All',
              selected: _group == null,
              onPressed: () => setState(() => _group = null),
            ),
            for (final group in inventoryGroupOrder) ...[
              const SizedBox(width: 6),
              _FilterChip(
                label: inventoryGroupLabel(group),
                selected: _group == group,
                onPressed: () => setState(() => _group = group),
              ),
            ],
          ],
        ),
      ),
      children: [
        if (rows.isEmpty)
          const MutedText('Nothing the Bazaar deals in matches.')
        else
          for (final entry in rows)
            _Row(
              item: _item(entry.itemId),
              title: entry.displayName,
              lines: <String>[_priceLine(entry.itemId)],
              onTap: () => _compose(bazaarBuy, entry.itemId),
            ),
      ],
    );
  }

  /// What an item has been going for, which is the only price worth quoting now
  /// that the screen no longer shows anybody's individual offers.
  String _priceLine(String itemId) {
    final guide = _guide(itemId);
    if (guide != null) {
      return 'Average ${formatThousands(guide.averagePrice)} · '
          'last ${formatThousands(guide.lastPrice)}';
    }
    final base = baseSellValue(_item(itemId));
    return base == null ? 'No trades yet' : 'No trades yet · shop value ${formatThousands(base)}';
  }

  // --- Sell: what the bag can put up -----------------------------------------

  Widget _sellList() {
    final query = _search.text.trim().toLowerCase();
    final held = <String, num>{};
    final blocked = <String, String>{};
    for (final stack in save.inventory) {
      final refusal = bazaarStackRefusal(stack, controller.db);
      if (refusal != null) {
        if (!isGoldCurrencyItem(stack.itemId, controller.db)) {
          blocked.putIfAbsent(stack.itemId, () => refusal);
        }
        continue;
      }
      if (!bazaarItemTradable(controller.db, stack.itemId)) {
        blocked.putIfAbsent(stack.itemId, () => bazaarUntradableItem);
        continue;
      }
      held[stack.itemId] = (held[stack.itemId] ?? 0) + stack.quantity;
    }

    final ids =
        held.keys
            .where(
              (itemId) =>
                  query.isEmpty ||
                  _name(itemId).toLowerCase().contains(query) ||
                  itemId.toLowerCase().contains(query),
            )
            .toList()
          ..sort((a, b) => _name(a).compareTo(_name(b)));

    return _framed(
      blurb: bazaarWithdrawFirst,
      search: 'Search your bag',
      children: [
        if (ids.isEmpty)
          MutedText(
            held.isEmpty ? 'Nothing in your bag can be listed.' : 'Nothing in your bag matches.',
          )
        else
          for (final itemId in ids)
            _Row(
              item: _item(itemId),
              title: _name(itemId),
              lines: <String>['Carrying ${formatThousands(held[itemId]!)}', _priceLine(itemId)],
              onTap: () => _compose(bazaarSell, itemId),
            ),
        if (blocked.isNotEmpty) ...[
          const _Heading(title: 'Staying with you'),
          for (final entry in blocked.entries) MutedText('${_name(entry.key)} — ${entry.value}'),
        ],
      ],
    );
  }

  // --- The item, a quantity, and a price -------------------------------------

  Widget _composePage(BazaarSide side, String itemId) {
    final buying = side == bazaarBuy;
    final guide = _guide(itemId);
    final onHand = bazaarTradableOnHand(save, itemId, controller.db).floor();
    final total = _price * _quantity;

    // Both numbers are capped by what the pair may be worth together rather than
    // by either alone, so each keypad's ceiling depends on the other's value.
    final quantityCap = buying ? (bazaarOfferValueCap / _price).floor() : onHand;
    final priceCap = (bazaarOfferValueCap / _quantity).floor();
    final short = buying && save.gold < total;

    return _framed(
      children: [
        GamePanel(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              ItemIcon(item: _item(itemId), size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _name(itemId),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w400),
                    ),
                    MutedText(
                      guide == null
                          ? 'No average price yet — you are naming it.'
                          : 'Average Bazaar price '
                                '${formatThousands(guide.averagePrice)} · '
                                '${formatThousands(guide.volume)} traded',
                    ),
                    if (!buying) MutedText('Carrying ${formatThousands(onHand)}'),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _Field(
          label: 'Quantity',
          value: formatThousands(_quantity),
          detail: buying ? 'How many to buy' : 'How many to sell',
          onTap: net.busy
              ? null
              : () async {
                  final chosen = await askQuantity(
                    context,
                    title: _name(itemId),
                    subtitle: buying ? 'How many to buy' : 'How many to sell',
                    details: <String>[if (!buying) 'Carrying: ${formatThousands(onHand)}'],
                    confirmLabel: 'Set quantity',
                    initialValue: _quantity.clamp(1, quantityCap < 1 ? 1 : quantityCap),
                    max: quantityCap,
                  );
                  if (chosen == null || !mounted) return;
                  setState(() => _quantity = chosen);
                },
        ),
        const SizedBox(height: 8),
        _Field(
          label: 'Price each',
          value: formatThousands(_price),
          detail: buying ? 'Most you will pay per item' : 'Least you will take per item',
          onTap: net.busy
              ? null
              : () async {
                  final chosen = await askQuantity(
                    context,
                    title: _name(itemId),
                    subtitle: buying ? 'Price per item to pay' : 'Price per item to ask',
                    details: <String>[
                      'Quantity: ${formatThousands(_quantity)}',
                      if (guide case final price?)
                        'Average: ${formatThousands(price.averagePrice)} each',
                      if (!buying) bazaarTaxLine(_price),
                    ],
                    confirmLabel: 'Set price',
                    initialValue: _price.clamp(1, priceCap < 1 ? 1 : priceCap),
                    max: priceCap,
                  );
                  if (chosen == null || !mounted) return;
                  setState(() => _price = chosen);
                },
        ),
        const SizedBox(height: 10),
        MutedText(
          buying
              ? 'Costs ${formatThousands(total)} gold, held until it trades. '
                    'You pay the cheapest offer, not what you name, and the '
                    'difference comes back to you.'
              : 'Worth ${formatThousands(total)} gold, '
                    '${formatThousands(bazaarSellerReceives(_price, _quantity))} after tax. '
                    'You are paid the best offer, not what you ask.',
        ),
        const SizedBox(height: 10),
        if (short)
          MutedText(
            'You have ${formatThousands(save.gold)} gold, and this needs '
            '${formatThousands(total)}.',
          )
        else if (!buying && onHand < 1)
          const MutedText('You are not carrying any. $bazaarWithdrawFirst')
        else
          GameButton(
            label: buying ? 'Place buy order' : 'Place sell order',
            onPressed: net.busy ? null : () => _place(side, itemId),
          ),
      ],
    );
  }

  // --- Shared frame ----------------------------------------------------------

  Widget _framed({String? blurb, String? search, Widget? above, required List<Widget> children}) {
    return GamePanel(
      framed: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (blurb != null) MutedText(blurb),
          if (search != null) ...[
            if (blurb != null) const SizedBox(height: 8),
            TextField(
              controller: _search,
              decoration: InputDecoration(hintText: search, isDense: true),
              onChanged: (_) => setState(() {}),
            ),
          ],
          if (above != null) ...[const SizedBox(height: 8), above],
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ],
      ),
    );
  }
}

/// What a sale at [unitPrice] would be taxed, said the way the rule reads.
String bazaarTaxLine(num unitPrice) {
  if (!bazaarTaxApplies(unitPrice)) {
    return 'Sales at $bazaarTaxThreshold gold an item or less are untaxed.';
  }
  return 'Sales over $bazaarTaxThreshold gold an item pay $bazaarTaxPercent%.';
}

/// A titled break between the parts of a page.
class _Heading extends StatelessWidget {
  const _Heading({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400)),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// One of the two numbers an offer needs, and the keypad that changes it.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    required this.detail,
    required this.onTap,
  });

  final String label;
  final String value;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GamePanel(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w400)),
                MutedText(detail),
              ],
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w400,
              color: Palette.parchmentText,
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.edit_outlined, size: 16, color: Palette.muted),
        ],
      ),
    );
  }
}

/// One line in a list: an icon, a title, and whatever is worth saying under it.
class _Row extends StatelessWidget {
  const _Row({required this.title, required this.lines, this.item, this.onTap, this.gold = false});

  final ItemRow? item;
  final String title;
  final List<String> lines;
  final VoidCallback? onTap;

  /// Draws the coin instead of an item icon, for a gold entry in the box.
  final bool gold;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          if (gold) const GoldCoin() else ItemIcon(item: item, size: 30),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w400)),
                for (final line in lines) MutedText(line),
              ],
            ),
          ),
          if (onTap != null) const Icon(Icons.chevron_right, size: 18, color: Palette.muted),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: onTap == null
          ? GamePanel(padding: EdgeInsets.zero, child: body)
          : GamePanel(padding: EdgeInsets.zero, onTap: onTap, child: body),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onPressed});

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GameButton(
      label: label,
      compact: true,
      dense: true,
      selected: selected,
      tone: selected ? GameButtonTone.primary : GameButtonTone.secondary,
      onPressed: onPressed,
    );
  }
}

/// One of the six offer boxes: empty and offering to become an order, or
/// holding one and showing how far through it is.
class _Slot extends StatelessWidget {
  const _Slot({
    required this.view,
    required this.name,
    required this.item,
    required this.busy,
    required this.onBuy,
    required this.onSell,
    required this.onCancel,
  });

  final MarketSlotView view;
  final String name;
  final ItemRow? item;
  final bool busy;
  final VoidCallback onBuy;
  final VoidCallback onSell;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final order = view.order;
    if (order == null) {
      return GamePanel(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MutedText('Slot ${view.slot + 1} — empty'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: GameButton(
                    label: 'Create a buy order',
                    compact: true,
                    onPressed: busy ? null : onBuy,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GameButton(
                    label: 'Create a sell order',
                    compact: true,
                    onPressed: busy ? null : onSell,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return GamePanel(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ItemIcon(item: item, size: 30),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${order.isBuy ? 'Buying' : 'Selling'} $name '
                      '×${formatThousands(order.quantity)}',
                      style: const TextStyle(fontWeight: FontWeight.w400),
                    ),
                    MutedText(
                      '${formatThousands(order.unitPrice)} each · '
                      '${formatThousands(order.filled)} of '
                      '${formatThousands(order.quantity)} traded',
                    ),
                    if (order.isBuy) MutedText('${formatThousands(order.goldEscrow)} gold held'),
                  ],
                ),
              ),
              GameButton(
                label: 'Cancel',
                tone: GameButtonTone.secondary,
                compact: true,
                onPressed: busy ? null : onCancel,
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: order.progress,
              minHeight: 4,
              backgroundColor: Palette.slot,
              color: Palette.gold,
            ),
          ),
        ],
      ),
    );
  }
}
