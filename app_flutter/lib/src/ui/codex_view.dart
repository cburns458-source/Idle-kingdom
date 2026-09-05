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

enum _CodexTab { items, bestiary }

/// Item Codex and Bestiary. Detail pages stack so taps can walk the links.
class CodexView extends StatefulWidget {
  const CodexView({
    super.key,
    required this.controller,
    this.onClose,
    this.initialItemId,
    this.initialEnemyId,
  });

  final GameController controller;
  final VoidCallback? onClose;
  final String? initialItemId;
  final String? initialEnemyId;

  @override
  State<CodexView> createState() => _CodexViewState();
}

class _CodexViewState extends State<CodexView> {
  late final CodexIndex _codex = CodexIndex(widget.controller.db);
  final TextEditingController _search = TextEditingController();
  final List<_CodexRoute> _stack = <_CodexRoute>[];
  _CodexTab _tab = _CodexTab.items;
  int? _group;

  @override
  void initState() {
    super.initState();
    final itemId = widget.initialItemId;
    final enemyId = widget.initialEnemyId;
    if (itemId != null && _codex.item(itemId) != null) {
      _stack.add(_CodexItemRoute(itemId));
    } else if (enemyId != null && _codex.enemy(enemyId) != null) {
      _stack.add(_CodexEnemyRoute(enemyId));
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _pushItem(String itemId) {
    if (_codex.item(itemId) == null) return;
    setState(() => _stack.add(_CodexItemRoute(itemId)));
  }

  void _pushEnemy(String enemyId) {
    if (_codex.enemy(enemyId) == null) return;
    setState(() => _stack.add(_CodexEnemyRoute(enemyId)));
  }

  void _close() {
    if (_stack.isNotEmpty) {
      setState(() => _stack.removeLast());
      return;
    }
    widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    final route = _stack.isEmpty ? null : _stack.last;
    final title = switch (route) {
      _CodexItemRoute(:final itemId) => _codex.item(itemId)?.displayName ?? 'Codex',
      _CodexEnemyRoute(:final enemyId) => _codex.enemy(enemyId)?.displayName ?? 'Codex',
      null => 'Codex',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.onClose != null || _stack.isNotEmpty)
          PageHeader(title: title, onClose: _close)
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w400)),
          ),
        Expanded(
          child: switch (route) {
            _CodexItemRoute(:final itemId) => _ItemPage(
              entry: _codex.item(itemId)!,
              item: widget.controller.indexes.itemsById[itemId],
              onOpenItem: _pushItem,
              onOpenEnemy: _pushEnemy,
            ),
            _CodexEnemyRoute(:final enemyId) => _EnemyPage(
              entry: _codex.enemy(enemyId)!,
              itemsById: widget.controller.indexes.itemsById,
              onOpenItem: _pushItem,
            ),
            null => _catalog(),
          },
        ),
      ],
    );
  }

  Widget _catalog() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Row(
            children: [
              for (final tab in _CodexTab.values) ...[
                if (tab != _CodexTab.items) const SizedBox(width: 6),
                Expanded(
                  child: GameButton(
                    label: tab == _CodexTab.items ? 'Items' : 'Bestiary',
                    compact: true,
                    selected: _tab == tab,
                    tone: _tab == tab ? GameButtonTone.primary : GameButtonTone.secondary,
                    onPressed: () => setState(() => _tab = tab),
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(hintText: 'Search by name', isDense: true),
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (_tab == _CodexTab.items)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              children: [
                _FilterChip(
                  key: const Key('codex-filter-all'),
                  label: 'All',
                  selected: _group == null,
                  onPressed: () => setState(() => _group = null),
                ),
                for (final group in inventoryGroupOrder) ...[
                  const SizedBox(width: 6),
                  _FilterChip(
                    key: Key('codex-filter-$group'),
                    label: inventoryGroupLabel(group),
                    selected: _group == group,
                    onPressed: () => setState(() => _group = group),
                  ),
                ],
              ],
            ),
          ),
        Expanded(child: _tab == _CodexTab.items ? _itemGrid() : _enemyList()),
      ],
    );
  }

  Widget _itemGrid() {
    final rows = _codex.itemsMatching(group: _group, query: _search.text);
    if (rows.isEmpty) {
      return const Center(child: MutedText('Nothing in the Codex matches.'));
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 84,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final entry = rows[index];
        final item = widget.controller.indexes.itemsById[entry.itemId];
        return Tooltip(
          message: entry.displayName,
          child: PixelInkPlate(
            key: Key('codex-item-${entry.itemId}'),
            onTap: () => _pushItem(entry.itemId),
            step: PixelChrome.stepTight,
            fillColor: UiChrome.of(context).slot,
            material: PixelPlateMaterial.none,
            shadow: false,
            padding: const EdgeInsets.all(4),
            child: Center(child: ItemIcon(item: item, size: 36)),
          ),
        );
      },
    );
  }

  Widget _enemyList() {
    final rows = _codex.enemiesMatching(_search.text);
    if (rows.isEmpty) {
      return const Center(child: MutedText('Nothing in the Bestiary matches.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: rows.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final entry = rows[index];
        final level = entry.combatLevel == null
            ? null
            : 'Level ${formatThousands(entry.combatLevel!)}';
        final places = entry.locations.map((row) => row.displayName).join(', ');
        return _LinkRow(
          key: Key('codex-enemy-${entry.enemyId}'),
          leading: GameImage(enemyAssetPath(entry.enemyId), width: 36, height: 36),
          title: entry.displayName,
          detail: [?level, if (places.isNotEmpty) places].join(' · '),
          onTap: () => _pushEnemy(entry.enemyId),
        );
      },
    );
  }
}

sealed class _CodexRoute {
  const _CodexRoute();
}

class _CodexItemRoute extends _CodexRoute {
  const _CodexItemRoute(this.itemId);
  final String itemId;
}

class _CodexEnemyRoute extends _CodexRoute {
  const _CodexEnemyRoute(this.enemyId);
  final String enemyId;
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

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

class _ItemPage extends StatelessWidget {
  const _ItemPage({
    required this.entry,
    required this.item,
    required this.onOpenItem,
    required this.onOpenEnemy,
  });

  final CodexItemEntry entry;
  final ItemRow? item;
  final ValueChanged<String> onOpenItem;
  final ValueChanged<String> onOpenEnemy;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        Row(
          children: [
            ItemIcon(item: item, size: 48),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.displayName, style: const TextStyle(fontSize: 16)),
                  MutedText([entry.groupLabel, ?entry.category, ?entry.subtype].join(' · ')),
                ],
              ),
            ),
          ],
        ),
        if (entry.description case final description? when description.isNotEmpty) ...[
          const SizedBox(height: 10),
          MutedText(description),
        ],
        if (entry.statLines.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final line in entry.statLines)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(line, style: const TextStyle(fontSize: 13)),
            ),
        ],
        _Section(
          title: 'Obtained from',
          empty: 'No known source yet.',
          children: [
            for (final source in entry.obtainedFrom)
              _LinkRow(
                title: source.title,
                detail: _obtainDetail(source),
                onTap: source.enemyId != null ? () => onOpenEnemy(source.enemyId!) : null,
              ),
          ],
        ),
        _Section(
          title: 'Crafted by',
          empty: 'Not crafted.',
          children: [
            for (final craft in entry.craftedBy) _CraftBlock(craft: craft, onOpenItem: onOpenItem),
          ],
        ),
        _Section(
          title: 'Used in',
          empty: 'Not used in any recipe.',
          children: [
            for (final craft in entry.usedIn) _CraftBlock(craft: craft, onOpenItem: onOpenItem),
          ],
        ),
      ],
    );
  }

  String? _obtainDetail(CodexObtainSource source) {
    final drop = source.dropChance == null ? null : '${formatThousands(source.dropChance!)}% drop';
    final parts = <String>[
      ?source.detail,
      if (source.locations.isNotEmpty) source.locations.map((row) => row.displayName).join(', '),
      ?drop,
      ?_qty(source.minQuantity, source.maxQuantity),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

class _EnemyPage extends StatelessWidget {
  const _EnemyPage({required this.entry, required this.itemsById, required this.onOpenItem});

  final CodexEnemyEntry entry;
  final Map<String, ItemRow> itemsById;
  final ValueChanged<String> onOpenItem;

  @override
  Widget build(BuildContext context) {
    final places = entry.locations.map((row) => row.displayName).join(', ');
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        Row(
          children: [
            GameImage(enemyAssetPath(entry.enemyId), width: 56, height: 56),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.displayName, style: const TextStyle(fontSize: 16)),
                  if (entry.combatLevel != null)
                    MutedText('Level ${formatThousands(entry.combatLevel!)}'),
                  if (places.isNotEmpty) MutedText(places),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Health ${formatThousands(entry.maximumHp)} · '
          'Damage ${formatThousands(entry.minDamage)}–${formatThousands(entry.maxDamage)}',
          style: const TextStyle(fontSize: 13),
        ),
        if (entry.combatXp != null)
          Text(
            'Combat XP ${formatThousands(entry.combatXp!)}',
            style: const TextStyle(fontSize: 13),
          ),
        if (entry.minimumGold != null || entry.maximumGold != null)
          Text(
            'Gold ${_range(entry.minimumGold, entry.maximumGold)}',
            style: const TextStyle(fontSize: 13),
          ),
        if (entry.dropChance != null)
          Text('${formatThousands(entry.dropChance!)}% drop', style: const TextStyle(fontSize: 13)),
        _Section(
          title: 'Drops',
          empty: 'No item drops.',
          children: [
            for (final drop in entry.drops)
              _LinkRow(
                key: Key('codex-drop-${drop.itemId}'),
                leading: ItemIcon(item: itemsById[drop.itemId], size: 28),
                title: drop.displayName,
                detail: [
                  ?_qty(drop.minQuantity, drop.maxQuantity),
                  if (drop.weight != null) 'Weight ${formatThousands(drop.weight!)}',
                ].join(' · '),
                onTap: () => onOpenItem(drop.itemId),
              ),
          ],
        ),
      ],
    );
  }
}

class _CraftBlock extends StatelessWidget {
  const _CraftBlock({required this.craft, required this.onOpenItem});

  final CodexCraft craft;
  final ValueChanged<String> onOpenItem;

  @override
  Widget build(BuildContext context) {
    final level = craft.level == null
        ? null
        : '${craft.skillName} ${formatThousands(craft.level!)}';
    final header = [craft.displayName, ?level, ?craft.facilityName].join(' · ');
    return GamePanel(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(header, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final ingredient in craft.ingredients)
                _ItemChip(
                  itemId: ingredient.itemId,
                  label:
                      '${ingredient.displayName}'
                      '${_qtySuffix(ingredient.minQuantity, ingredient.maxQuantity)}',
                  onTap: () => onOpenItem(ingredient.itemId),
                ),
              if (craft.output.itemId.isNotEmpty)
                _ItemChip(
                  itemId: craft.output.itemId,
                  label: 'Makes ${craft.output.displayName}',
                  onTap: () => onOpenItem(craft.output.itemId),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ItemChip extends StatelessWidget {
  const _ItemChip({required this.itemId, required this.label, required this.onTap});

  final String itemId;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GameButton(
      key: Key('codex-link-$itemId'),
      label: label,
      compact: true,
      dense: true,
      tone: GameButtonTone.secondary,
      onPressed: onTap,
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.empty, required this.children});

  final String title;
  final String empty;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 8),
          if (children.isEmpty)
            MutedText(empty)
          else
            for (final child in children)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: child),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({super.key, required this.title, this.detail, this.leading, this.onTap});

  final String title;
  final String? detail;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PixelInkPlate(
      onTap: onTap,
      step: PixelChrome.stepTight,
      fillColor: UiChrome.of(context).panel,
      shadow: false,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          if (leading case final leading?) ...[leading, const SizedBox(width: 10)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14)),
                if (detail case final detail? when detail.isNotEmpty) MutedText(detail),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String? _qty(num? min, num? max) {
  if (min == null && max == null) return null;
  if (min != null && max != null && min != max) {
    return '×${formatThousands(min)}–${formatThousands(max)}';
  }
  return '×${formatThousands(min ?? max!)}';
}

String _qtySuffix(num? min, num? max) {
  final qty = _qty(min, max);
  return qty == null ? '' : ' $qty';
}

String _range(num? min, num? max) {
  if (min != null && max != null && min != max) {
    return '${formatThousands(min)}–${formatThousands(max)}';
  }
  return formatThousands(min ?? max ?? 0);
}
