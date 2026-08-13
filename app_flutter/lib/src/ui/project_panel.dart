import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'ingredient_chip.dart';
import 'item_icon.dart';
import 'quantity_sheet.dart';

/// A Special Production station: pick a project, then complete it on the spot.
///
/// Projects are instant, so there is no queue here — only what a project asks
/// for, what it gives back, and (for an enchantment) which item receives it.
class ProjectPicker extends StatefulWidget {
  const ProjectPicker({super.key, required this.controller, required this.station, this.onClose});

  final GameController controller;
  final SpecialProductionStation station;
  final VoidCallback? onClose;

  @override
  State<ProjectPicker> createState() => _ProjectPickerState();
}

class _ProjectPickerState extends State<ProjectPicker> {
  String _search = '';
  String? _projectId;
  String? _enchantTargetId;
  num _quantity = 1;
  String? _error;

  GameController get controller => widget.controller;
  String get facilityId => widget.station.facility.facilityId;
  String get skillId => widget.station.skillId;

  @override
  void initState() {
    super.initState();
    _projectId = defaultProjectId(controller.db, controller.save, facilityId, skillId);
  }

  void _select(String projectId) {
    setState(() {
      _projectId = projectId;
      _quantity = 1;
      _enchantTargetId = null;
      _error = null;
    });
  }

  Future<void> _complete(ProjectDetail detail, num quantity) async {
    final result = completeSpecialProject(
      controller.db,
      controller.save,
      detail.projectId,
      quantity,
      enchantTargetId: detail.isEnchantment
          ? (_enchantTargetId ?? _preferredTargetId(detail))
          : null,
      nowMs: controller.session.clock(),
    );
    if (!result.ok) {
      setState(() => _error = result.reason);
      return;
    }
    final receipt = describeProjectCompletion(controller.db, detail.projectId, quantity, result);
    // Enchanting changes worn gear, so vitals are recalculated with the save.
    controller.commitLoadout(result.save!);
    controller.announce(receipt.message);
    setState(() {
      _error = null;
      _quantity = 1;
    });
    await showProjectReceipt(context, receipt: receipt);
  }

  String? _preferredTargetId(ProjectDetail detail) {
    for (final target in detail.enchantTargets) {
      if (target.preferred) return target.id;
    }
    return detail.enchantTargets.isEmpty ? null : detail.enchantTargets.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final all = projectMenuList(controller.db, controller.save, facilityId, skillId);
    final listed = projectMenuList(controller.db, controller.save, facilityId, skillId, _search);
    final selectedId = listed.any((row) => row.projectId == _projectId)
        ? _projectId
        : (listed.isEmpty ? null : listed.first.projectId);
    final detail = selectedId == null
        ? null
        : projectDetail(controller.db, controller.save, selectedId);

    return GamePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.station.label,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              if (widget.onClose != null)
                IconButton(
                  onPressed: widget.onClose,
                  tooltip: 'Close',
                  icon: const Icon(Icons.close, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (all.isEmpty)
            const MutedText('No projects are defined for this station yet.')
          else ...[
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search projects',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              textInputAction: TextInputAction.search,
              onChanged: (value) => setState(() => _search = value),
            ),
            const SizedBox(height: 8),
            MutedText(
              _search.trim().isEmpty
                  ? pluralize(listed.length, 'project')
                  : '${listed.length} of ${all.length} projects',
            ),
            const SizedBox(height: 6),
            if (listed.isEmpty)
              const MutedText('No projects match that search.')
            else
              _ProjectList(items: listed, selectedId: selectedId, onSelect: _select),
            if (detail != null) ...[
              const SizedBox(height: 10),
              _ProjectDetails(controller: controller, detail: detail),
              const SizedBox(height: 10),
              if (detail.lockedReason case final reason?)
                Text(reason, style: const TextStyle(color: Palette.danger, fontSize: 12))
              else if (detail.isEnchantment)
                _enchantRow(detail)
              else
                _quantityRow(detail),
            ],
          ],
          if (_error case final error?) ...[
            const SizedBox(height: 6),
            Text(error, style: const TextStyle(color: Palette.danger, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _quantityRow(ProjectDetail detail) {
    final ceiling = detail.maxQuantity;
    final quantity = _quantity.clamp(1, ceiling < 1 ? 1 : ceiling);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MutedText(
          ceiling < 1
              ? 'Not enough materials for one.'
              : 'Materials allow ${formatThousands(ceiling)}',
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            OutlinedButton(
              onPressed: ceiling < 1
                  ? null
                  : () async {
                      final chosen = await askQuantity(
                        context,
                        subtitle: 'Project quantity',
                        title: detail.name,
                        details: ['Materials allow ${formatThousands(ceiling)}'],
                        confirmLabel: 'Set quantity',
                        initialValue: quantity.toInt(),
                        max: ceiling.toInt(),
                      );
                      if (chosen == null || !mounted) return;
                      setState(() => _quantity = chosen);
                    },
              child: Text(formatThousands(quantity)),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: ceiling < 1 ? null : () => setState(() => _quantity = ceiling),
              child: const Text('Max'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: ceiling < 1 ? null : () => _complete(detail, quantity),
                child: const Text('Complete project'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _enchantRow(ProjectDetail detail) {
    if (detail.enchantTargets.isEmpty) {
      return const Text(
        'Equip or keep a valid unenchanted item in the bag.',
        style: TextStyle(color: Palette.danger, fontSize: 12),
      );
    }
    final selected = detail.enchantTargets.any((target) => target.id == _enchantTargetId)
        ? _enchantTargetId
        : _preferredTargetId(detail);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Item to enchant',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final target in detail.enchantTargets)
              DropdownMenuItem(
                value: target.id,
                child: Text(target.label, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) => setState(() {
            _enchantTargetId = value;
            _error = null;
          }),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: () => _complete(detail, 1), child: const Text('Complete project')),
      ],
    );
  }
}

/// The station's projects, scrollable so a long list cannot push out the detail.
class _ProjectList extends StatelessWidget {
  const _ProjectList({required this.items, required this.selectedId, required this.onSelect});

  final List<ProjectListItem> items;
  final String? selectedId;
  final void Function(String projectId) onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: const Color(0x66231710),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Palette.edge),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final chosen = item.projectId == selectedId;
          return InkWell(
            onTap: () => onSelect(item.projectId),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              color: chosen ? const Color(0x33D4AF37) : null,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: chosen ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (item.locked) const MutedText('locked'),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProjectDetails extends StatelessWidget {
  const _ProjectDetails({required this.controller, required this.detail});

  final GameController controller;
  final ProjectDetail detail;

  @override
  Widget build(BuildContext context) {
    final output = detail.outputItemId == null
        ? null
        : controller.indexes.itemsById[detail.outputItemId!];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ItemIcon(item: output, size: 30),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${detail.outputName} ×${formatThousands(detail.outputQuantity)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  MutedText(detail.summaryLine),
                  if (detail.effectLine case final effect?) MutedText(effect),
                ],
              ),
            ),
          ],
        ),
        if (detail.skillLine case final skills?) ...[const SizedBox(height: 4), MutedText(skills)],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final line in detail.ingredients)
              IngredientChip(
                item: controller.indexes.itemsById[line.itemId],
                need: line.need,
                owned: line.owned,
              ),
            if (detail.goldCost > 0)
              GoldAmount(
                amount: detail.goldCost,
                style: TextStyle(
                  color: detail.goldOwned < detail.goldCost ? Palette.danger : Palette.gold,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Shows what a finished project produced.
Future<void> showProjectReceipt(BuildContext context, {required ProjectReceipt receipt}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: GamePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const MutedText('Project complete'),
              Text(
                receipt.projectName,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final line in receipt.lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('· $line', style: const TextStyle(color: Palette.gold)),
                ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Collect'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
