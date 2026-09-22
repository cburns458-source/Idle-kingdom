import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'game_image.dart';
import 'item_icon.dart';
import 'game_popup.dart';
import 'page_header.dart';

enum TrackerKind { xp, loot }

String? _firstString(Iterable<String> values) {
  final iterator = values.iterator;
  return iterator.moveNext() ? iterator.current : null;
}

Future<void> showTrackerPopup({
  required BuildContext context,
  required GameController controller,
  required TrackerKind kind,
  Rect? origin,
}) {
  return showGamePopup<void>(
    context: context,
    origin: origin,
    maxWidth: 320,
    maxHeight: 420,
    builder: (dialogContext) {
      return SizedBox(
        width: 320,
        height: 420,
        child: TrackerView(controller: controller, kind: kind),
      );
    },
  );
}

/// RuneScape-style loot and XP trackers that persist on the save until reset.
class TrackerView extends StatefulWidget {
  const TrackerView({super.key, required this.controller, required this.kind, this.onClose});

  final GameController controller;
  final TrackerKind kind;
  final VoidCallback? onClose;

  @override
  State<TrackerView> createState() => _TrackerViewState();
}

class _TrackerViewState extends State<TrackerView> {
  Timer? _ticker;

  GameController get controller => widget.controller;
  TrackerKind get kind => widget.kind;

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
        final title = kind == TrackerKind.loot ? 'Loot' : 'XP';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.onClose != null)
              PageHeader(title: title, onClose: widget.onClose!)
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w400),
                ),
              ),
            Expanded(child: kind == TrackerKind.xp ? _xpTab() : _lootTab()),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: _TrackerToolbar(
            loot: true,
            paused: lootTrackersPaused(controller.save),
            onOff: () =>
                controller.commit(pauseLootTrackers(controller.save, controller.session.clock())),
            onOn: () =>
                controller.commit(resumeLootTrackers(controller.save, controller.session.clock())),
            onResetAll: () => controller.commit(resetAllLootTrackers(controller.save)),
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: MutedText('Finish an action to start a loot tracker.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: rows.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _LootCard(
                    entry: rows[index],
                    controller: controller,
                    onReset: () =>
                        controller.commit(resetLootTracker(controller.save, rows[index].key)),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: _TrackerToolbar(
            loot: false,
            paused: xpTrackersPaused(controller.save),
            onOff: () =>
                controller.commit(pauseXpTrackers(controller.save, controller.session.clock())),
            onOn: () =>
                controller.commit(resumeXpTrackers(controller.save, controller.session.clock())),
            onResetAll: () => controller.commit(resetAllXpTrackers(controller.save)),
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: MutedText('Gain XP to start an XP tracker.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: rows.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = rows[index];
                    return _XpRow(
                      entry: entry,
                      title: _xpTitle(entry.skillId),
                      iconPath: entry.skillId == totalXpTrackerId
                          ? null
                          : skillIconPath(_skillById(entry.skillId)),
                      nowMs: nowMs,
                      save: controller.save,
                      onReset: () =>
                          controller.commit(resetXpTracker(controller.save, entry.skillId)),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _xpTitle(String skillId) {
    if (skillId == totalXpTrackerId) return 'Total XP';
    return _skillById(skillId)?.displayName ?? skillId;
  }

  SkillRow? _skillById(String skillId) {
    return _firstWhere(controller.db.skills, (row) => row.skillId == skillId);
  }
}

T? _firstWhere<T>(Iterable<T> values, bool Function(T value) test) {
  for (final value in values) {
    if (test(value)) return value;
  }
  return null;
}

String? _timerSkillId(String sourceId) {
  final kind = sourceId.split(':').first;
  return switch (kind) {
    'botany' => 'SKL-0014',
    'fishing_pot' => 'SKL-0003',
    _ => null,
  };
}

class _LootCard extends StatelessWidget {
  const _LootCard({required this.entry, required this.controller, required this.onReset});

  final LootTrackerEntry entry;
  final GameController controller;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final itemsById = controller.indexes.itemsById;
    final itemIds = entry.items.keys.toList()..sort();
    final goldId = currencyItemId(controller.db);
    final goldItem = itemsById[goldId];
    final hasGold = entry.gold > 0;
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
          if (itemIds.isEmpty && !hasGold) ...[
            const SizedBox(height: 8),
            const MutedText('No item drops yet.'),
          ] else ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (hasGold)
                  _DropChip(
                    item: goldItem,
                    label: '${goldItem?.displayName ?? 'Gold'} ×${formatThousands(entry.gold)}',
                  ),
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
    if (entry.kind == 'timer') {
      final skillId = _timerSkillId(entry.sourceId);
      final skill = skillId == null
          ? null
          : _firstWhere(controller.db.skills, (row) => row.skillId == skillId);
      return GameImage(skillIconPath(skill), width: 36, height: 36);
    }
    return GameImage(actionAssetPath(entry.sourceId), width: 36, height: 36);
  }

  String _lootTitle() {
    if (entry.kind == 'enemy') {
      return _firstString(
            controller.db.enemies
                .where((row) => row.enemyId == entry.sourceId)
                .map((row) => row.displayName),
          ) ??
          entry.sourceId;
    }
    if (entry.kind == 'timer') {
      return _timerTitle(entry.sourceId);
    }
    return _firstString(
          controller.db.actions
              .where((row) => row.actionId == entry.sourceId)
              .map((row) => row.displayName),
        ) ??
        entry.sourceId;
  }

  String _timerTitle(String sourceId) {
    final parts = sourceId.split(':');
    final kind = parts.isNotEmpty ? parts.first : sourceId;
    final locationId = parts.length > 1 ? parts.sublist(1).join(':') : '';
    final location =
        _firstString(
          controller.db.locations
              .where((row) => row.locationId == locationId)
              .map((row) => row.displayName),
        ) ??
        locationId;
    final label = switch (kind) {
      'botany' => 'Botany',
      'fishing_pot' => 'Fishing pot',
      _ => kind,
    };
    return location.isEmpty ? label : '$label · $location';
  }

  String _lootDetail() {
    final countLabel = switch (entry.kind) {
      'enemy' => entry.completions == 1 ? '1 kill' : '${formatThousands(entry.completions)} kills',
      'timer' =>
        entry.completions == 1 ? '1 collect' : '${formatThousands(entry.completions)} collects',
      _ => entry.completions == 1 ? '1 action' : '${formatThousands(entry.completions)} actions',
    };
    return countLabel;
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

class _TrackerToolbar extends StatelessWidget {
  const _TrackerToolbar({
    required this.loot,
    required this.paused,
    required this.onOff,
    required this.onOn,
    required this.onResetAll,
  });

  final bool loot;
  final bool paused;
  final VoidCallback onOff;
  final VoidCallback onOn;
  final VoidCallback onResetAll;

  @override
  Widget build(BuildContext context) {
    final suffix = loot ? 'loot' : 'xp';
    return Row(
      children: [
        const Spacer(),
        GameButton(
          key: Key('tracker-off-$suffix'),
          label: 'Off',
          compact: true,
          dense: true,
          tone: GameButtonTone.secondary,
          onPressed: paused ? null : onOff,
        ),
        const SizedBox(width: 6),
        GameButton(
          key: Key('tracker-on-$suffix'),
          label: 'On',
          compact: true,
          dense: true,
          tone: GameButtonTone.secondary,
          onPressed: paused ? onOn : null,
        ),
        const SizedBox(width: 6),
        GameButton(
          key: Key('tracker-reset-all-$suffix'),
          label: 'Reset all',
          compact: true,
          dense: true,
          tone: GameButtonTone.secondary,
          onPressed: onResetAll,
        ),
      ],
    );
  }
}

class _XpRow extends StatelessWidget {
  const _XpRow({
    required this.entry,
    required this.title,
    required this.iconPath,
    required this.nowMs,
    required this.save,
    required this.onReset,
  });

  final XpTrackerEntry entry;
  final String title;
  final String? iconPath;
  final num nowMs;
  final PlayerSave save;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return GamePanel(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          if (iconPath != null) ...[
            GameImage(iconPath!, width: 30, height: 30),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15)),
                MutedText(
                  '${formatThousands(entry.xpGained)} XP · ${formatThousands(xpPerHour(entry, nowMs, save))} XP/hr',
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
