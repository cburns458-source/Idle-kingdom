import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'game_image.dart';
import 'item_icon.dart';
import 'page_header.dart';

enum _TrackerTab { loot, xp }

/// RuneScape-style loot and XP trackers that persist on the save until reset.
class TrackerView extends StatefulWidget {
  const TrackerView({super.key, required this.controller, this.onClose});

  final GameController controller;
  final VoidCallback? onClose;

  @override
  State<TrackerView> createState() => _TrackerViewState();
}

class _TrackerViewState extends State<TrackerView> {
  _TrackerTab _tab = _TrackerTab.loot;
  Timer? _ticker;

  GameController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.onClose != null)
              PageHeader(title: 'Tracker', onClose: widget.onClose!)
            else
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Text(
                  'Tracker',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w400),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Row(
                children: [
                  for (final tab in _TrackerTab.values) ...[
                    if (tab != _TrackerTab.loot) const SizedBox(width: 6),
                    Expanded(
                      child: GameButton(
                        label: tab == _TrackerTab.loot ? 'Loot' : 'XP',
                        compact: true,
                        selected: _tab == tab,
                        tone: _tab == tab
                            ? GameButtonTone.primary
                            : GameButtonTone.secondary,
                        onPressed: () => setState(() => _tab = tab),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(child: _tab == _TrackerTab.loot ? _lootTab() : _xpTab()),
          ],
        );
      },
    );
  }

  Widget _lootTab() {
    final rows = sortedLootTrackers(controller.save);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: GameButton(
                key: const Key('tracker-reset-all-loot'),
                label: 'Reset all',
                compact: true,
                dense: true,
                tone: GameButtonTone.secondary,
                onPressed: () =>
                    controller.commit(resetAllLootTrackers(controller.save)),
              ),
            ),
          ),
        Expanded(
          child: rows.isEmpty
              ? const Center(
                  child: MutedText('Finish an action to start a loot tracker.'),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: rows.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) => _LootCard(
                    entry: rows[index],
                    controller: controller,
                    onReset: () => controller.commit(
                      resetLootTracker(controller.save, rows[index].key),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _xpTab() {
    final rows = sortedXpTrackers(controller.save);
    final nowMs = controller.session.clock();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: GameButton(
                key: const Key('tracker-reset-all-xp'),
                label: 'Reset all',
                compact: true,
                dense: true,
                tone: GameButtonTone.secondary,
                onPressed: () =>
                    controller.commit(resetAllXpTrackers(controller.save)),
              ),
            ),
          ),
        Expanded(
          child: rows.isEmpty
              ? const Center(
                  child: MutedText('Gain XP to start an XP tracker.'),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: rows.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = rows[index];
                    return _XpRow(
                      entry: entry,
                      title: _xpTitle(entry.skillId),
                      nowMs: nowMs,
                      onReset: () => controller.commit(
                        resetXpTracker(controller.save, entry.skillId),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _xpTitle(String skillId) {
    if (skillId == totalXpTrackerId) return 'Total XP';
    return controller.db.skills
            .where((row) => row.skillId == skillId)
            .map((row) => row.displayName)
            .firstOrNull ??
        skillId;
  }
}

class _LootCard extends StatelessWidget {
  const _LootCard({
    required this.entry,
    required this.controller,
    required this.onReset,
  });

  final LootTrackerEntry entry;
  final GameController controller;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final itemsById = controller.indexes.itemsById;
    final itemIds = entry.items.keys.toList()..sort();
    return GamePanel(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _lootLeading(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_lootTitle(), style: const TextStyle(fontSize: 15)),
                    MutedText(_lootDetail()),
                  ],
                ),
              ),
              GameButton(
                key: Key('tracker-reset-loot-${entry.key}'),
                label: 'Reset',
                compact: true,
                dense: true,
                tone: GameButtonTone.secondary,
                onPressed: onReset,
              ),
            ],
          ),
          if (itemIds.isEmpty) ...[
            const SizedBox(height: 8),
            const MutedText('No item drops yet.'),
          ] else ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final itemId in itemIds)
                  _DropChip(
                    item: itemsById[itemId],
                    label:
                        '${itemsById[itemId]?.displayName ?? itemId} ×${formatThousands(entry.items[itemId]!)}',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _lootLeading() {
    if (entry.kind == 'enemy') {
      return GameImage(enemyAssetPath(entry.sourceId), width: 36, height: 36);
    }
    return const SizedBox(width: 36, height: 36);
  }

  String _lootTitle() {
    if (entry.kind == 'enemy') {
      return controller.db.enemies
              .where((row) => row.enemyId == entry.sourceId)
              .map((row) => row.displayName)
              .firstOrNull ??
          entry.sourceId;
    }
    if (entry.kind == 'timer') {
      return _timerTitle(entry.sourceId);
    }
    return controller.db.actions
            .where((row) => row.actionId == entry.sourceId)
            .map((row) => row.displayName)
            .firstOrNull ??
        entry.sourceId;
  }

  String _timerTitle(String sourceId) {
    final parts = sourceId.split(':');
    final kind = parts.isNotEmpty ? parts.first : sourceId;
    final locationId = parts.length > 1 ? parts.sublist(1).join(':') : '';
    final location =
        controller.db.locations
            .where((row) => row.locationId == locationId)
            .map((row) => row.displayName)
            .firstOrNull ??
        locationId;
    final label = switch (kind) {
      'botany' => 'Botany',
      'hunting_trap' => 'Hunting trap',
      'fishing_trap' => 'Fishing trap',
      _ => kind,
    };
    return location.isEmpty ? label : '$label · $location';
  }

  String _lootDetail() {
    final countLabel = switch (entry.kind) {
      'enemy' =>
        entry.completions == 1
            ? '1 kill'
            : '${formatThousands(entry.completions)} kills',
      'timer' =>
        entry.completions == 1
            ? '1 collect'
            : '${formatThousands(entry.completions)} collects',
      _ =>
        entry.completions == 1
            ? '1 action'
            : '${formatThousands(entry.completions)} actions',
    };
    if (entry.gold <= 0) return countLabel;
    return '$countLabel · ${formatThousands(entry.gold)} gold';
  }
}

class _DropChip extends StatelessWidget {
  const _DropChip({required this.item, required this.label});

  final ItemRow? item;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ItemIcon(item: item, size: 24),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}

class _XpRow extends StatelessWidget {
  const _XpRow({
    required this.entry,
    required this.title,
    required this.nowMs,
    required this.onReset,
  });

  final XpTrackerEntry entry;
  final String title;
  final num nowMs;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return GamePanel(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15)),
                MutedText(
                  '${formatThousands(entry.xpGained)} XP · ${formatThousands(xpPerHour(entry, nowMs))} XP/hr',
                ),
              ],
            ),
          ),
          GameButton(
            key: Key('tracker-reset-xp-${entry.skillId}'),
            label: 'Reset',
            compact: true,
            dense: true,
            tone: GameButtonTone.secondary,
            onPressed: onReset,
          ),
        ],
      ),
    );
  }
}
