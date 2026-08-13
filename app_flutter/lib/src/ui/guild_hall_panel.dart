import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'item_icon.dart';
import 'quantity_sheet.dart';

enum _HallTab { storehouse, debt, boxing }

/// Per-guild hall: item chest, debt ledger, boxing ring.
class GuildHallPanel extends StatefulWidget {
  const GuildHallPanel({
    super.key,
    required this.controller,
    required this.multiplayer,
    this.onClose,
  });

  final GameController controller;
  final MultiplayerController multiplayer;
  final VoidCallback? onClose;

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

  String _itemName(InventoryStack stack) =>
      controller.indexes.itemsById[stack.itemId]?.displayName ?? stack.itemId;

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
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Good job!'),
          content: const Text('The hall debt is paid.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
    }
  }

  Future<void> _deposit(int index, InventoryStack stack) async {
    final quantity = await askQuantity(
      context,
      title: _itemName(stack),
      subtitle: 'Into the guild storehouse',
      confirmLabel: 'Contribute',
      max: stack.quantity.floor(),
    );
    if (quantity == null || !mounted) return;
    await _apply(await net.service.contributeHallItem(save, index, quantity));
  }

  Future<void> _withdraw(int index, InventoryStack stack) async {
    final quantity = await askQuantity(
      context,
      title: _itemName(stack),
      subtitle: 'From the guild storehouse',
      confirmLabel: 'Withdraw',
      max: stack.quantity.floor(),
    );
    if (quantity == null || !mounted) return;
    await _apply(await net.service.withdrawHallItem(save, index, quantity));
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
              for (final tab in _HallTab.values) ...[
                if (tab != _HallTab.values.first) const SizedBox(width: 6),
                Expanded(
                  child: GameButton(
                    label: switch (tab) {
                      _HallTab.storehouse => 'Storehouse',
                      _HallTab.debt => 'Debt',
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
              _HallTab.boxing => _boxing(),
            },
        ],
      ),
    );
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
        MutedText(
          'Item contributions unlock hall features — not levels. '
          'Boxing ring: ${formatThousands(hall.itemsContributed)} / ${formatThousands(boxingRingUnlockItems)}.',
        ),
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
                trailing: GameButton(label: 'In', onPressed: () => _deposit(entry.$1, entry.$2)),
              ),
            ),
        const SizedBox(height: 8),
        const Text('Storehouse', style: TextStyle(fontWeight: FontWeight.w700)),
        if (hall.storehouse.isEmpty)
          const MutedText('Empty.')
        else
          for (final entry in hall.storehouse.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: DockRow(
                title: _itemName(entry.$2),
                lines: [MutedText('×${formatThousands(entry.$2.quantity)}')],
                trailing: GameButton(label: 'Out', onPressed: () => _withdraw(entry.$1, entry.$2)),
              ),
            ),
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
    final hall = _hall!;
    if (!hall.boxingUnlocked) {
      return MutedText(
        'Contribute ${formatThousands(boxingRingUnlockItems)} items to raise the boxing ring. '
        'Progress: ${formatThousands(hall.itemsContributed)}.',
      );
    }
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
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(fight.outcome == 'win' ? 'Victory' : 'Defeat'),
        content: Text(
          fight.outcome == 'win'
              ? 'You beat ${opponent.username} in the ring.'
              : '${opponent.username} won the bout. No gold changes hands.',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }
}
