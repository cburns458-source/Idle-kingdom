import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'game_popup.dart';
import 'guild_bank_view.dart';
import 'guild_hall_gold_bar.dart';
import 'item_icon.dart';
import 'quantity_sheet.dart';

enum _HallTab { hall, bank }

/// Per-guild hall: storehouse, running gold, room tiers, and the guild bank.
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
  _HallTab _tab = _HallTab.hall;
  GuildHallState? _hall;
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
    if (!mounted) return;
    setState(() {
      _hall = hall;
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
    for (final tierId in result.tiersFinishedNow) {
      if (!mounted) return;
      final line = guildHallTierFinishLine(tierId);
      final tier = guildHallTiers.where((row) => row.id == tierId);
      await showGameAlert(
        context: context,
        title: tier.isEmpty ? 'Finished' : '${tier.first.name} finished',
        message: line ?? '',
        confirmLabel: 'OK',
        placement: GamePopupPlacement.center,
      );
    }
  }

  Future<void> _deposit(int index, InventoryStack stack) async {
    final hall = _hall;
    if (hall == null) return;
    if (bazaarItemBound(controller.db, stack.itemId)) {
      await showGameAlert(context: context, message: bazaarBoundItem);
      return;
    }
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
      confirmLabel: 'Contribute',
      max: math.min(stack.quantity.floor(), remaining.floor()),
    );
    if (quantity == null || !mounted) return;
    await _apply(await net.service.contributeHallItem(save, index, quantity));
  }

  Future<void> _chipIn() async {
    final hall = _hall;
    if (hall == null) return;
    final remaining = guildHallGoldChipInCap(hall.goldContributed).floor();
    final maxPay = remaining.clamp(0, save.gold.floor());
    final quantity = await askQuantity(
      context,
      title: 'Chip in',
      confirmLabel: 'Chip in',
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: GameFont.l, fontWeight: FontWeight.w400),
                ),
              ),
              GoldAmount(
                amount: save.gold,
                style: const TextStyle(color: Palette.gold),
              ),
              if (widget.onClose != null) GameCloseButton(onPressed: widget.onClose),
            ],
          ),
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
                      _HallTab.hall => 'Hall',
                      _HallTab.bank => 'Bank',
                    },
                    tone: _tab == tab ? GameButtonTone.primary : GameButtonTone.secondary,
                    onPressed: () => setState(() => _tab = tab),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _loading
                ? const SizedBox.shrink()
                : _hall == null
                ? const SizedBox.shrink()
                : switch (_tab) {
                    _HallTab.hall => SingleChildScrollView(child: _storehouse()),
                    _HallTab.bank => GuildBankView(
                      controller: controller,
                      multiplayer: net,
                      hall: _hall!,
                      onHallChanged: (hall) => setState(() => _hall = hall),
                    ),
                  },
          ),
        ],
      ),
    );
  }

  List<_HallTab> get _tabs {
    final hall = _hall;
    return <_HallTab>[_HallTab.hall, if (hall != null && hall.bankUnlocked) _HallTab.bank];
  }

  Widget _storehouse() {
    final hall = _hall!;
    final bag = <(int, InventoryStack)>[
      for (final entry in save.inventory.indexed)
        if (!stackIsUnbankableGold(entry.$2) &&
            guildHallDonationCap(hall.completedTiers, hall.storehouse, entry.$2.itemId) > 0)
          (entry.$1, entry.$2),
    ];
    final role = _role;
    final remaining = guildHallGoldChipInCap(hall.goldContributed);
    final canChip = role != null && canChipInGuildGold(role) && remaining > 0 && save.gold > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GuildHallGoldBar(contributed: hall.goldContributed),
        const SizedBox(height: 8),
        GameButton(label: 'Chip in', onPressed: canChip ? _chipIn : null),
        const SizedBox(height: 12),
        for (final tier in guildHallTiers) _tierBlock(hall, tier),
        const SizedBox(height: 8),
        const Text('Bag', style: TextStyle(fontWeight: FontWeight.w400)),
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
        const Text('Store House', style: TextStyle(fontWeight: FontWeight.w400)),
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

  Widget _tierBlock(GuildHallState hall, GuildHallTier tier) {
    final next = nextGuildHallTier(hall.completedTiers);
    final finished = hall.completedTiers.contains(tier.id);
    final active = !finished && next?.id == tier.id;
    final color = finished
        ? Palette.gold
        : active
        ? null
        : Palette.muted;
    final needs = guildHallTierNeeds(tier, hall.storehouse);
    return Opacity(
      opacity: finished || active ? 1 : 0.45,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tier.name,
              style: TextStyle(fontWeight: FontWeight.w400, color: color),
            ),
            for (final need in needs)
              Text(
                '${_itemNameFor(need.itemId)} '
                '${formatThousands(finished ? need.needed : need.counted)} / '
                '${formatThousands(need.needed)}',
                style: TextStyle(color: color ?? Palette.muted, fontSize: GameFont.s),
              ),
          ],
        ),
      ),
    );
  }
}
