import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'item_icon.dart';
import 'page_header.dart';
import 'quantity_sheet.dart';
import 'social_bits.dart';

/// The exchange, opened from the hamburger wherever the player is standing.
///
/// Four things a player wants from a market, in the order they want them: what
/// is on offer, what they can put up, what they have open, and what they have
/// already done. The collection box sits under the offers, because that is where
/// a finished offer goes and where a cancelled one comes back.
///
/// Nothing here decides anything. Every read and every write goes through
/// [MultiplayerController] to the server, which is the only thing that knows
/// what a save can afford; a save that comes back from a placement is adopted
/// rather than worked out. The Citadel notice board is a separate screen and
/// stays what it is.
enum BazaarTab { buy, sell, offers, history }

const Map<BazaarTab, String> bazaarTabLabels = <BazaarTab, String>{
  BazaarTab.buy: 'Buy',
  BazaarTab.sell: 'Sell',
  BazaarTab.offers: 'Offers',
  BazaarTab.history: 'History',
};

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

class _BazaarViewState extends State<BazaarView> {
  final TextEditingController _search = TextEditingController();
  BazaarTab _tab = BazaarTab.buy;

  /// The item whose book is open, or null while the list is being browsed.
  String? _looking;

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

  void _look(String? itemId) {
    setState(() => _looking = itemId);
    net.refreshMarket(itemId: itemId);
  }

  void _selectTab(BazaarTab tab) {
    setState(() {
      _tab = tab;
      _looking = null;
      _search.clear();
    });
    net.refreshMarket();
  }

  /// Asks how many and at what price, then places the offer.
  ///
  /// Quantity first so the price keypad can cap itself: an offer may not be
  /// worth more than a save can hold in gold, and that is a limit on the two
  /// numbers together rather than on either of them.
  Future<void> _offer(BazaarSide side, String itemId, {num? onHand}) async {
    final buying = side == bazaarBuy;
    final guide = net.market.pricesByItem[itemId];
    final name = _name(itemId);
    final base = baseSellValue(_item(itemId));

    final maxQuantity = buying
        ? bazaarOfferValueCap
        : (onHand ?? bazaarTradableOnHand(save, itemId, controller.db)).floor();
    if (maxQuantity < 1) {
      net.announce('You are not carrying any $name. $bazaarWithdrawFirst');
      return;
    }

    final quantity = await askQuantity(
      context,
      title: name,
      subtitle: buying ? 'How many to buy' : 'How many to sell',
      details: <String>[
        if (guide case final price?) 'Guide price: ${formatThousands(price.averagePrice)} each',
        if (guide == null && base != null) 'Shop value: ${formatThousands(base)} each',
        if (!buying) 'Carrying: ${formatThousands(maxQuantity)}',
      ],
      confirmLabel: 'Next',
      max: maxQuantity,
    );
    if (quantity == null || !mounted) return;

    final priceCap = (bazaarOfferValueCap / quantity).floor();
    final suggested = guide?.averagePrice.floor() ?? base?.floor() ?? 1;
    final unitPrice = await askQuantity(
      context,
      title: name,
      subtitle: buying ? 'Price per item to pay' : 'Price per item to ask',
      details: <String>[
        'Quantity: ${formatThousands(quantity)}',
        if (guide case final price?) 'Guide price: ${formatThousands(price.averagePrice)} each',
        if (!buying) bazaarTaxLine(suggested),
      ],
      confirmLabel: buying ? 'Buy' : 'Sell',
      initialValue: suggested.clamp(1, priceCap),
      max: priceCap,
    );
    if (unitPrice == null || !mounted) return;

    await net.placeMarketOffer(
      side: side,
      itemId: itemId,
      unitPrice: unitPrice,
      quantity: quantity,
      save: save,
      onSaved: controller.commitLoadout,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: net,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: 'Bazaar',
            onClose: widget.onClose,
            trailing: GoldAmount(
              amount: save.gold,
              style: const TextStyle(color: Palette.gold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tab in BazaarTab.values)
                  GameButton(
                    label: _tabLabel(tab),
                    compact: true,
                    selected: tab == _tab,
                    tone: tab == _tab ? GameButtonTone.primary : GameButtonTone.secondary,
                    onPressed: () => _selectTab(tab),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: net.isSignedIn ? _body() : _signedOut(),
            ),
          ),
        ],
      ),
    );
  }

  /// The Offers tab counts what is waiting, so a filled order is noticed without
  /// the player having to go and look.
  String _tabLabel(BazaarTab tab) {
    final label = bazaarTabLabels[tab]!;
    if (tab != BazaarTab.offers) return label;
    final waiting = net.market.collect.length;
    return waiting == 0 ? label : '$label ($waiting)';
  }

  Widget _signedOut() {
    return GamePanel(
      framed: true,
      child: SignedOutNotice(
        title: 'Bazaar',
        prompt: net.mode == MultiplayerMode.local ? bazaarHostedOnly : bazaarSignInToTrade,
        showTitle: false,
      ),
    );
  }

  Widget _body() {
    switch (_tab) {
      case BazaarTab.buy:
        return _looking == null ? _browse() : _book(_looking!);
      case BazaarTab.sell:
        return _looking == null ? _bag() : _book(_looking!);
      case BazaarTab.offers:
        return _offers();
      case BazaarTab.history:
        return _history();
    }
  }

  // --- Buy: browse what is on offer ------------------------------------------

  Widget _browse() {
    final query = _search.text.trim().toLowerCase();
    final summaries = <String, MarketSummary>{for (final row in net.market.market) row.itemId: row};
    final prices = net.market.pricesByItem;
    final ids =
        <String>{...summaries.keys, ...prices.keys}
            .where((itemId) => bazaarItemTradable(controller.db, itemId))
            .where((itemId) => _matches(itemId, query))
            .toList()
          ..sort((a, b) {
            final sellingA = summaries[a]?.sellQuantity ?? 0;
            final sellingB = summaries[b]?.sellQuantity ?? 0;
            if (sellingA != sellingB) return sellingB.compareTo(sellingA);
            return _name(a).compareTo(_name(b));
          });

    return _framed(
      blurb: bazaarBlurbMarket,
      search: 'Search the Bazaar',
      children: [
        if (ids.isEmpty)
          MutedText(query.isEmpty ? bazaarEmptyBook : 'Nothing on offer matches.')
        else
          for (final itemId in ids)
            _Row(
              item: _item(itemId),
              title: _name(itemId),
              lines: <String>[
                if (summaries[itemId] case final row? when row.bestAsk > 0)
                  'Cheapest: ${formatThousands(row.bestAsk)} · '
                      '${formatThousands(row.sellQuantity)} on offer'
                else
                  'Nobody selling',
                if (prices[itemId] case final price?)
                  'Guide ${formatThousands(price.averagePrice)} · '
                      'last ${formatThousands(price.lastPrice)}',
              ],
              onTap: () => _look(itemId),
            ),
      ],
    );
  }

  bool _matches(String itemId, String query) {
    if (query.isEmpty) return true;
    return _name(itemId).toLowerCase().contains(query) || itemId.toLowerCase().contains(query);
  }

  // --- Sell: what the bag can put up -----------------------------------------

  Widget _bag() {
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

    final ids = held.keys.where((itemId) => _matches(itemId, query)).toList()
      ..sort((a, b) => _name(a).compareTo(_name(b)));
    final prices = net.market.pricesByItem;
    final summaries = <String, MarketSummary>{for (final row in net.market.market) row.itemId: row};

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
              lines: <String>[
                'Carrying ${formatThousands(held[itemId]!)}',
                if (summaries[itemId] case final row? when row.bestBid > 0)
                  'Best offer: ${formatThousands(row.bestBid)} each'
                else if (prices[itemId] case final price?)
                  'Guide ${formatThousands(price.averagePrice)} each'
                else if (baseSellValue(_item(itemId)) case final value?)
                  'Shop value ${formatThousands(value)} each',
              ],
              onTap: () => _look(itemId),
            ),
        if (blocked.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('Staying with you', style: TextStyle(fontWeight: FontWeight.w400)),
          for (final entry in blocked.entries) MutedText('${_name(entry.key)} — ${entry.value}'),
        ],
      ],
    );
  }

  // --- One item's book -------------------------------------------------------

  Widget _book(String itemId) {
    final buying = _tab == BazaarTab.buy;
    final guide = net.market.pricesByItem[itemId];
    final asks = net.market.offers.where((row) => !row.isBuy).toList()
      ..sort((a, b) => a.unitPrice.compareTo(b.unitPrice));
    final bids = net.market.offers.where((row) => row.isBuy).toList()
      ..sort((a, b) => b.unitPrice.compareTo(a.unitPrice));
    final onHand = bazaarTradableOnHand(save, itemId, controller.db);

    return GamePanel(
      framed: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ItemIcon(item: _item(itemId), size: 34),
              const SizedBox(width: 8),
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
                          ? 'No trades yet.'
                          : 'Guide ${formatThousands(guide.averagePrice)} · '
                                'last ${formatThousands(guide.lastPrice)} · '
                                '${formatThousands(guide.volume)} traded',
                    ),
                  ],
                ),
              ),
              GameButton(
                label: 'Back',
                tone: GameButtonTone.secondary,
                compact: true,
                onPressed: () => _look(null),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Depth(
                    heading: 'On offer',
                    empty: 'Nobody is selling.',
                    rows: asks,
                    highlightFirst: buying,
                  ),
                  const SizedBox(height: 10),
                  _Depth(
                    heading: 'Wanted',
                    empty: 'Nobody is buying.',
                    rows: bids,
                    highlightFirst: !buying,
                  ),
                  const SizedBox(height: 10),
                  MutedText(
                    buying
                        ? 'You pay the cheapest offer, not what you name. '
                              'Anything you named above it comes back to you.'
                        : 'You are paid the best offer, not what you ask. '
                              '${bazaarTaxLine(guide?.averagePrice ?? 0)}',
                  ),
                  const SizedBox(height: 8),
                  if (buying)
                    GameButton(
                      label: 'Offer to buy',
                      onPressed: net.busy ? null : () => _offer(bazaarBuy, itemId),
                    )
                  else if (onHand < 1)
                    MutedText('You are not carrying any. $bazaarWithdrawFirst')
                  else
                    GameButton(
                      label: 'Offer to sell',
                      onPressed: net.busy ? null : () => _offer(bazaarSell, itemId, onHand: onHand),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Offers and the collection box -----------------------------------------

  Widget _offers() {
    final slots = bazaarSlotViews(net.market.orders);
    final box = net.market.collect;
    return _framed(
      blurb: 'Three offers at a time. Cancelling returns whatever has not traded.',
      children: [
        for (final slot in slots) ...[
          _Slot(
            view: slot,
            name: slot.order == null ? '' : _name(slot.order!.itemId),
            item: slot.order == null ? null : _item(slot.order!.itemId),
            busy: net.busy,
            onCancel: slot.order == null ? null : () => net.cancelMarketOffer(slot.order!.id),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Collection box',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
              ),
            ),
            if (box.isNotEmpty)
              GameButton(
                label: 'Collect',
                compact: true,
                onPressed: net.busy
                    ? null
                    : () => net.collectMarketBox(save, controller.commitLoadout),
              ),
          ],
        ),
        const SizedBox(height: 6),
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

  // --- History ---------------------------------------------------------------

  Widget _history() {
    final trades = net.market.trades;
    return _framed(
      blurb: 'Your last $bazaarHistoryLength trades.',
      children: [
        if (trades.isEmpty)
          const MutedText(bazaarEmptyHistory)
        else
          for (final trade in trades)
            _Row(
              item: _item(trade.itemId),
              title:
                  '${trade.isBuy ? 'Bought' : 'Sold'} '
                  '${_name(trade.itemId)} ×${formatThousands(trade.quantity)}',
              lines: <String>[
                '${formatThousands(trade.unitPrice)} each · '
                    '${formatThousands(trade.net)} gold ${trade.isBuy ? 'paid' : 'received'}',
                if (trade.tax > 0) 'Tax ${formatThousands(trade.tax)}',
              ],
            ),
      ],
    );
  }

  // --- Shared frame ----------------------------------------------------------

  Widget _framed({required String blurb, String? search, required List<Widget> children}) {
    return GamePanel(
      framed: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MutedText(blurb),
          if (search != null) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _search,
              decoration: InputDecoration(hintText: search, isDense: true),
              onChanged: (_) => setState(() {}),
            ),
          ],
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
          if (gold) const GoldAmount(amount: 0, size: 22) else ItemIcon(item: item, size: 30),
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

/// One side of a book, price by price.
class _Depth extends StatelessWidget {
  const _Depth({
    required this.heading,
    required this.empty,
    required this.rows,
    required this.highlightFirst,
  });

  final String heading;
  final String empty;
  final List<MarketOffer> rows;

  /// Marks the price the player would actually deal at from this side.
  final bool highlightFirst;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(heading, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w400)),
        const SizedBox(height: 4),
        if (rows.isEmpty)
          MutedText(empty)
        else
          for (final (index, row) in rows.take(6).indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${formatThousands(row.unitPrice)} each',
                      style: TextStyle(
                        color: highlightFirst && index == 0 ? Palette.gold : null,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  MutedText('${formatThousands(row.quantity)} on offer'),
                ],
              ),
            ),
      ],
    );
  }
}

/// One of the three offer boxes.
class _Slot extends StatelessWidget {
  const _Slot({
    required this.view,
    required this.name,
    required this.item,
    required this.busy,
    required this.onCancel,
  });

  final MarketSlotView view;
  final String name;
  final ItemRow? item;
  final bool busy;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final order = view.order;
    if (order == null) {
      return GamePanel(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.add, size: 18, color: Palette.muted),
            const SizedBox(width: 8),
            MutedText('Slot ${view.slot + 1} — empty'),
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
          if (order.filled > 0) ...[
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
        ],
      ),
    );
  }
}
