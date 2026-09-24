import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'floating_slot.dart';
import 'format.dart';
import 'item_icon.dart';
import 'quantity_sheet.dart';

/// Hide-to-leather counter: pick quantities on the pin pad, then confirm once.
class TannerPanel extends StatefulWidget {
  const TannerPanel({super.key, required this.controller, required this.npc, this.onClose});

  final GameController controller;
  final NpcRow npc;
  final VoidCallback? onClose;

  @override
  State<TannerPanel> createState() => _TannerPanelState();
}

class _TannerPanelState extends State<TannerPanel> {
  final Map<String, num> _quantities = <String, num>{};
  String? _error;
  String? _receipt;

  GameController get controller => widget.controller;
  GameDatabase get db => controller.db;
  PlayerSave get save => controller.save;

  TannerOffer get _offer => tannerOffer(db, save);

  Map<String, num> get _selected {
    return <String, num>{
      for (final entry in _quantities.entries)
        if (entry.value > 0) entry.key: entry.value,
    };
  }

  Future<void> _pickHide(TannerHideOption hide) async {
    final already = _quantities[hide.itemId] ?? 0;
    final editing = already > 0;
    final quantity = await askQuantity(
      context,
      subtitle: 'Tan',
      title: hide.displayName,
      details: [
        '${formatThousands(hide.leatherEach)} leather each',
        '${formatThousands(_offer.feeEach)} gold per leather',
        'You have ${formatThousands(hide.owned)}',
      ],
      confirmLabel: editing ? 'Update offer' : 'Add to offer',
      initialValue: editing ? already.floor() : 1,
      max: hide.owned.floor(),
      removeLabel: editing ? 'Remove from offer' : null,
    );
    if (!mounted) return;
    if (quantity == quantityRemoveSentinel) {
      setState(() {
        _error = null;
        _quantities.remove(hide.itemId);
      });
      return;
    }
    if (quantity == null) return;
    setState(() {
      _error = null;
      _quantities[hide.itemId] = quantity;
    });
  }

  void _confirm() {
    final reason = controller.tanHidesWithTanner(widget.npc.npcId, _selected);
    if (reason != null) {
      setState(() => _error = reason);
      return;
    }
    setState(() {
      _error = null;
      _receipt = controller.message;
      _quantities.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final hides = _offer.hides;
    final quote = quoteTannerJob(db, save, _selected);
    final canAfford = save.gold >= quote.gold;
    final hasOffer = quote.leather > 0;

    return GamePanel(
      framed: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Tanner', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w400)),
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
          Text(
            'Offer — ${formatThousands(quote.leather)} leather / '
            '${formatThousands(quote.gold)} gold',
            style: const TextStyle(fontWeight: FontWeight.w400),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              GameButton(
                label: 'Clear offer',
                tone: GameButtonTone.secondary,
                compact: true,
                onPressed: _quantities.isEmpty
                    ? null
                    : () => setState(() {
                        _quantities.clear();
                        _error = null;
                      }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GameButton(
                  label: !hasOffer
                      ? 'Select hides'
                      : !canAfford
                      ? 'Need gold'
                      : 'Confirm tan',
                  onPressed: hasOffer && canAfford ? _confirm : null,
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
          const Text('Hides', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w400)),
          const SizedBox(height: 5),
          Expanded(
            child: FloatingItemWell(
              child: hides.isEmpty
                  ? const Align(
                      alignment: Alignment.topLeft,
                      child: MutedText('You have no hides to tan.', color: Palette.muted),
                    )
                  : GridView.builder(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 78,
                        mainAxisSpacing: 5,
                        crossAxisSpacing: 5,
                        childAspectRatio: 1,
                      ),
                      itemCount: hides.length,
                      itemBuilder: (context, index) => _hideTile(hides[index]),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hideTile(TannerHideOption hide) {
    final item = controller.indexes.itemsById[hide.itemId];
    final offered = _quantities[hide.itemId];
    final enabled = hide.owned > 0;
    return FloatingItemSlot(
      tooltip: hide.displayName,
      selected: offered != null,
      enabled: enabled,
      padding: const EdgeInsets.fromLTRB(3, 5, 3, 4),
      onTap: enabled ? () => _pickHide(hide) : null,
      child: Stack(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ItemIcon(item: item, size: 36),
              const SizedBox(height: 2),
              Text(
                '${formatThousands(hide.leatherEach)} leather · '
                '${formatThousands(hide.owned)}',
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
    );
  }
}
