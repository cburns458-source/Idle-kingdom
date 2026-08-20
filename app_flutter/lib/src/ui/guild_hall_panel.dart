import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'game_popup.dart';
import 'item_icon.dart';
import 'quantity_sheet.dart';

enum _HallTab { storehouse, debt, bank, boxing }

/// Per-guild hall: the storehouse the guild builds out of, and its debt ledger.
///
/// A hall opens with those two. The bank and the boxing ring are added by the
/// tiers that pay for them.
class GuildHallPanel extends StatefulWidget {
  const GuildHallPanel({
    super.key,
    required this.controller,
    required this.multiplayer,
    this.onClose,
    this.onOpenBank,
  });

  final GameController controller;
  final MultiplayerController multiplayer;
  final VoidCallback? onClose;

  /// Opens the bank screen, which the hall borrows once the tier is paid for.
  final VoidCallback? onOpenBank;

  @override
  State<GuildHallPanel> createState() => _GuildHallPanelState();
}

class _GuildHallPanelState extends State<GuildHallPanel> {
  _HallTab _tab = _HallTab.storehouse;
  GuildHallState? _hall;
  List<ArenaOpponent> _boxers = const <ArenaOpponent>[];
  String? _error;
  bool _loading = true;

  GameController get controller => widget.controller;
  MultiplayerController get net => widget.multiplayer;
  PlayerSave get save => controller.save;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final guildId = net.guildId;
    if (guildId == null) {
      setState(() {
        _loading = false;
        _error = 'Join a guild to use this hall.';
      });
      return;
    }
    final hall = await net.service.guildHall(guildId);
    final boxers = await net.service.hallBoxingOpponents();
    if (!mounted) return;
    setState(() {
      _hall = hall;
      _boxers = boxers;
      _loading = false;
      if (hall == null) _error = 'Join a guild to use this hall.';
    });
  }

  String _itemName(InventoryStack stack) => _itemNameFor(stack.itemId);

  String _itemNameFor(String itemId) => controller.indexes.itemsById[itemId]?.displayName ?? itemId;

  String? get _role {
    final userId = net.session?.userId;
    if (userId == null) return null;
    for (final row in net.members) {
      if (row.userId == userId) return row.role;
    }
    return null;
  }

  Future<void> _apply(GuildHallActionResult result) async {
    if (!result.ok) {
      setState(() => _error = result.reason);
      return;
    }
    if (result.save != null) controller.commit(result.save!);
    setState(() {
      _hall = result.hall;
      _error = null;
    });
    if (result.paidOffJustNow && mounted) {
      await showGameAlert(
        context: context,
        title: 'Good job!',
        message: 'The hall debt is paid.',
        confirmLabel: 'OK',
        placement: GamePopupPlacement.center,
      );
    }
    for (final tierId in result.tiersFinishedNow) {
      if (!mounted) return;
      final tier = guildHallTiers.firstWhere((row) => row.id == tierId);
      await showGameAlert(
        context: context,
        title: '${tier.name} finished',
        message: 'The guild spent the materials. ${tier.blurb}',
        confirmLabel: 'OK',
        placement: GamePopupPlacement.center,
      );
    }
  }

  Future<void> _deposit(int index, InventoryStack stack) async {
    final hall = _hall;
    if (hall == null) return;
    final remaining = guildHallDonationCap(hall.completedTiers, hall.storehouse, stack.itemId);
    if (remaining <= 0) {
      setState(
        () => _error = nextGuildHallTier(hall.completedTiers) == null
            ? guildHallFinishedRefusal
            : guildHallUnneededRefusal,
      );
      return;
    }
    final quantity = await askQuantity(
      context,
      title: _itemName(stack),
      subtitle: 'Into the guild storehouse',
      confirmLabel: 'Contribute',
      max: math.min(stack.quantity.floor(), remaining.floor()),
    );
    if (quantity == null || !mounted) return;
    await _apply(await net.service.contributeHallItem(save, index, quantity));
  }

  Future<void> _payDebt() async {
    final hall = _hall;
    if (hall == null) return;
    final maxPay = hall.debtRemaining.floor().clamp(0, save.gold.floor());
    final quantity = await askQuantity(
      context,
      title: 'Hall debt',
      subtitle: 'Remaining: ${formatThousands(hall.debtRemaining)}',
      confirmLabel: 'Pay',
      max: maxPay,
    );
    if (quantity == null || !mounted) return;
    await _apply(await net.service.payGuildDebt(save, quantity));
  }

  @override
  Widget build(BuildContext context) {
    return GamePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Guild Hall',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              GoldAmount(
                amount: save.gold,
                style: const TextStyle(color: Palette.gold),
              ),
              if (widget.onClose != null)
                IconButton(
                  onPressed: widget.onClose,
                  tooltip: 'Close',
                  icon: const Icon(Icons.close, size: 18),
                ),
            ],
          ),
          const MutedText('This instance belongs to your guild.'),
          if (_error case final error?) ...[
            const SizedBox(height: 6),
            Text(error, style: warningStyle),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              for (final tab in _tabs) ...[
                if (tab != _tabs.first) const SizedBox(width: 6),
                Expanded(
                  child: GameButton(
                    label: switch (tab) {
                      _HallTab.storehouse => 'Store House',
                      _HallTab.debt => 'Debt',
                      _HallTab.bank => 'Bank',
                      _HallTab.boxing => 'Boxing',
                    },
                    tone: _tab == tab ? GameButtonTone.primary : GameButtonTone.secondary,
                    onPressed: () => setState(() => _tab = tab),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (_loading)
            const MutedText('Loading hall…')
          else if (_hall == null)
            const MutedText('Join a guild to use this hall.')
          else
            switch (_tab) {
              _HallTab.storehouse => _storehouse(),
              _HallTab.debt => _debt(),
              _HallTab.bank => _bank(),
              _HallTab.boxing => _boxing(),
            },
        ],
      ),
    );
  }

  /// A hall offers the Store House and the Debt. The rest is built into it.
  List<_HallTab> get _tabs {
    final hall = _hall;
    return <_HallTab>[
      _HallTab.storehouse,
      _HallTab.debt,
      if (hall != null && hall.bankUnlocked) _HallTab.bank,
      if (hall != null && hall.boxingUnlocked) _HallTab.boxing,
    ];
  }

  Widget _storehouse() {
    final hall = _hall!;
    final bag = <(int, InventoryStack)>[
      for (final entry in save.inventory.indexed)
        if (!stackIsUnbankableGold(entry.$2)) (entry.$1, entry.$2),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tierCard(hall),
        const SizedBox(height: 8),
        const Text('Bag', style: TextStyle(fontWeight: FontWeight.w700)),
        if (bag.isEmpty)
          const MutedText('Nothing to contribute.')
        else
          for (final entry in bag)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: DockRow(
                title: _itemName(entry.$2),
                lines: [MutedText('×${formatThousands(entry.$2.quantity)}')],
                trailing:
                    guildHallDonationCap(hall.completedTiers, hall.storehouse, entry.$2.itemId) > 0
                    ? GameButton(label: 'In', onPressed: () => _deposit(entry.$1, entry.$2))
                    : const SizedBox.shrink(),
              ),
            ),
        const SizedBox(height: 8),
        const Text('Store House', style: TextStyle(fontWeight: FontWeight.w700)),
        if (hall.storehouse.isEmpty)
          const MutedText('Empty.')
        else
          for (final stack in hall.storehouse)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: DockRow(
                title: _itemName(stack),
                trailing: MutedText('×${formatThousands(stack.quantity)}'),
              ),
            ),
      ],
    );
  }

  /// What the guild is building, and what it still owes for it.
  Widget _tierCard(GuildHallState hall) {
    final tier = nextGuildHallTier(hall.completedTiers);
    if (tier == null) {
      return const MutedText('The hall is finished.');
    }
    final needs = guildHallTierNeeds(tier, hall.storehouse);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tier.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        MutedText('${tier.blurb} Donations are spent when it is finished.'),
        for (final need in needs)
          MutedText(
            '${_itemNameFor(need.itemId)} '
            '${formatThousands(need.counted)} / ${formatThousands(need.needed)}',
          ),
      ],
    );
  }

  Widget _bank() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MutedText('The counting room holds your own bank, same chest as in town.'),
        const SizedBox(height: 8),
        GameButton(label: 'Open the bank', onPressed: widget.onOpenBank),
      ],
    );
  }

  Widget _debt() {
    final hall = _hall!;
    final role = _role;
    final canPay = role != null && canPayGuildDebt(role);
    final mine = hall.debtPaidBy[net.session?.userId] ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          hall.debtPaidOff
              ? 'Paid in full.'
              : 'Remaining: ${formatThousands(hall.debtRemaining)} / ${formatThousands(guildHallDebtGold)}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        MutedText(
          'Your payments: ${formatThousands(mine)} gold. Member and above can pay. No extra reward.',
        ),
        const SizedBox(height: 8),
        GameButton(
          label: hall.debtPaidOff ? 'Settled' : 'Pay',
          onPressed: !hall.debtPaidOff && canPay ? _payDebt : null,
        ),
        if (!canPay) const MutedText('Recruits cannot pay the hall debt.'),
      ],
    );
  }

  Widget _boxing() {
    if (_boxers.isEmpty) {
      return const MutedText('No guildmates with a stored character to challenge.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MutedText('Challenge a guildmate. Snapshot fight, no betting, no gold.'),
        const SizedBox(height: 8),
        for (final row in _boxers)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DockRow(
              title: row.username,
              lines: [MutedText('Combat ${formatThousands(row.combatLevel)}')],
              trailing: GameButton(label: 'Fight', onPressed: () => _box(row)),
            ),
          ),
      ],
    );
  }

  Future<void> _box(ArenaOpponent opponent) async {
    final them = await net.service.readOpponentSave(opponent.userId);
    if (!mounted) return;
    if (them == null) {
      setState(() => _error = 'That player has no character to fight.');
      return;
    }
    final fight = simulatePvpFight(controller.db, save, them, controller.session.random);
    if (!mounted) return;
    await showGameAlert(
      context: context,
      title: fight.outcome == 'win' ? 'Victory' : 'Defeat',
      message: fight.outcome == 'win'
          ? 'You beat ${opponent.username} in the ring.'
          : '${opponent.username} won the bout. No gold changes hands.',
      confirmLabel: 'OK',
      placement: GamePopupPlacement.center,
    );
  }
}
