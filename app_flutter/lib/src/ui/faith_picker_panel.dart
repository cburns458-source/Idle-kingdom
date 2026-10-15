import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'floating_slot.dart';
import 'item_icon.dart';

/// Temple overlay: the seven faiths, then a confirm step.
class FaithPickerPanel extends StatefulWidget {
  const FaithPickerPanel({super.key, required this.controller, this.onClose});

  final GameController controller;
  final VoidCallback? onClose;

  @override
  State<FaithPickerPanel> createState() => _FaithPickerPanelState();
}

class _FaithPickerPanelState extends State<FaithPickerPanel> {
  String? _pendingId;
  String? _error;
  bool _busy = false;

  GameController get controller => widget.controller;
  GameDatabase get db => controller.db;
  PlayerSave get save => controller.save;

  num get _nowMs => controller.session.clock();

  num get _cost => religionChangeGoldCost(db, save);

  String? get _cooldown {
    final readyAt = religionChangeReadyAt(db, save);
    if (readyAt == null || _nowMs >= readyAt) return null;
    return formatDurationRemaining(readyAt - _nowMs);
  }

  bool get _cooldownBlocks => _cooldown != null;

  Future<void> _confirm() async {
    final religionId = _pendingId;
    if (religionId == null || _busy) return;
    if (_cooldownBlocks || save.gold < _cost || save.religionId == religionId) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final reason = await controller.chooseReligionAtTemple(religionId);
    if (!mounted) return;
    if (reason != null) {
      setState(() {
        _busy = false;
        _error = reason;
      });
      return;
    }
    widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final faiths = religions(db);
        final pending = religionById(db, _pendingId);
        return SizedBox.expand(
          child: GamePanel(
            framed: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Faith',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: GameFont.l, fontWeight: FontWeight.w400),
                      ),
                    ),
                    if (widget.onClose != null) GameCloseButton(onPressed: widget.onClose!),
                  ],
                ),
                const SizedBox(height: 8),
                _FaithCost(cost: _cost),
                if (_cooldown case final cooldown?) Text(cooldown),
                if (_error case final error?)
                  Text(
                    error,
                    style: const TextStyle(color: Palette.danger, fontSize: GameFont.s),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: pending == null
                      ? SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final faith in faiths)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _FaithRow(
                                    faith: faith,
                                    bonusLines: religionBonusSummaryLines(db, faith.religionId),
                                    current: save.religionId == faith.religionId,
                                    onTap: save.religionId == faith.religionId
                                        ? null
                                        : () => setState(() {
                                            _pendingId = faith.religionId;
                                            _error = null;
                                          }),
                                  ),
                                ),
                            ],
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                child: _FaithRow(
                                  faith: pending,
                                  bonusLines: religionBonusSummaryLines(db, pending.religionId),
                                  current: save.religionId == pending.religionId,
                                  onTap: null,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    key: const Key('faith-back'),
                                    height: minItemTapExtent,
                                    child: GameButton(
                                      label: 'Back',
                                      tone: GameButtonTone.secondary,
                                      onPressed: _busy
                                          ? null
                                          : () => setState(() {
                                              _pendingId = null;
                                              _error = null;
                                            }),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: SizedBox(
                                    key: const Key('faith-confirm'),
                                    height: minItemTapExtent,
                                    child: GameButton(
                                      label: 'Confirm',
                                      waiting: _busy,
                                      onPressed:
                                          _busy ||
                                              _cooldownBlocks ||
                                              save.gold < _cost ||
                                              save.religionId == pending.religionId
                                          ? null
                                          : _confirm,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FaithCost extends StatelessWidget {
  const _FaithCost({required this.cost});

  final num cost;

  @override
  Widget build(BuildContext context) {
    if (cost <= 0) return const Text('Free');
    return GoldAmount(amount: cost);
  }
}

/// God name from the Religions `God` column.
String? faithGodName(ReligionRow faith) {
  final name = faith.god?.trim();
  if (name == null || name.isEmpty) return null;
  return name;
}

class _FaithRow extends StatelessWidget {
  const _FaithRow({
    required this.faith,
    required this.bonusLines,
    required this.current,
    required this.onTap,
  });

  final ReligionRow faith;
  final List<String> bonusLines;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final god = faithGodName(faith);
    return KeyedSubtree(
      key: Key('faith-${faith.religionId}'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minItemTapExtent),
        child: GamePanel(
          highlight: current,
          onTap: onTap,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                faith.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w400),
              ),
              if (god != null && god.isNotEmpty)
                Text(
                  god,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: GameFont.s, color: UiChrome.of(context).panelInk),
                ),
              for (final line in bonusLines) MutedText(line),
            ],
          ),
        ),
      ),
    );
  }
}
