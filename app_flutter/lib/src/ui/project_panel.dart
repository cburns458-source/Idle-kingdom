import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'game_popup.dart';
import 'ingredient_chip.dart';
import 'item_icon.dart';
import 'quantity_sheet.dart';
import 'recipe_book_sheet.dart';

/// The station counter as its own floating card, not in the location list.
Future<void> showProjectPicker(
  BuildContext context, {
  required GameController controller,
  required SpecialProductionStation station,
  Rect? origin,
}) {
  return showGamePopup<void>(
    context: context,
    origin: origin,
    builder: (context) => SizedBox(
      width: 360,
      child: SingleChildScrollView(
        child: ProjectPicker(
          controller: controller,
          station: station,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    ),
  );
}

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
    controller.noteProjectCompletion(result);
    controller.announce(receipt.message);
    setState(() {
      _error = null;
      _quantity = 1;
    });
    await showProjectReceipt(context, receipt: receipt);
  }

  void _openBook() {
    showStationRecipeBook(
      context,
      title: widget.station.label,
      rows: recipeLogForEntries(
        recipeBookForProjectStation(controller.save, controller.db, facilityId, skillId),
      ),
    );
  }

  String? _preferredTargetId(ProjectDetail detail) {
    for (final target in detail.enchantTargets) {
      if (target.preferred) return target.id;
    }
    return detail.enchantTargets.isEmpty ? null : detail.enchantTargets.first.id;
  }

  String _emptyCopy(List<ProjectListItem> defined) {
    if (defined.isEmpty) return 'No projects are defined for this station yet.';
    final knowledge = hasProjectKnowledge(controller.db, controller.save, skillId);
    if (!knowledge.ok) {
      if (skillId == smithingSkillId) {
        return 'Locked — find the Master Dwarf to unlock Smithing projects. '
            'The Dwarven Mining Merchant knows where he is today.';
      }
      return 'Locked — speak with the ${knowledge.npcName ?? 'mentor'} to unlock '
          '${widget.station.skillName} projects.';
    }
    return 'No projects you can make right now. Open the recipe book to see what you need.';
  }

  @override
  Widget build(BuildContext context) {
    final defined = projectMenuList(controller.db, controller.save, facilityId, skillId);
    final all = readyProjectMenuList(controller.db, controller.save, facilityId, skillId);
    final selectedId = all.any((row) => row.projectId == _projectId)
        ? _projectId
        : (all.isEmpty ? null : all.first.projectId);
    final detail = selectedId == null
        ? null
        : projectDetail(controller.db, controller.save, selectedId);

    return GamePanel(
      framed: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.station.label,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400),
                ),
              ),
              GameButton(
                label: 'Recipe book',
                tone: GameButtonTone.secondary,
                compact: true,
                onPressed: _openBook,
              ),
              if (widget.onClose != null) ...[
                const SizedBox(width: 6),
                GameIconButton(icon: Icons.close, tooltip: 'Close', onPressed: widget.onClose),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (all.isEmpty)
            MutedText(_emptyCopy(defined))
          else ...[
            GameDropdown<String>(
              label: 'Project',
              value: selectedId,
              items: [
                for (final row in all)
                  GameDropdownItem(
                    value: row.projectId,
                    label: row.locked ? '${row.label} (locked)' : row.label,
                    enabled: !row.locked,
                  ),
              ],
              onChanged: _select,
            ),
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
            GameButton(
              label: formatThousands(quantity),
              tone: GameButtonTone.secondary,
              compact: true,
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
            ),
            const SizedBox(width: 8),
            GameButton(
              label: 'Max',
              tone: GameButtonTone.secondary,
              compact: true,
              onPressed: ceiling < 1 ? null : () => setState(() => _quantity = ceiling),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GameButton(
                label: 'Complete project',
                onPressed: ceiling < 1 ? null : () => _complete(detail, quantity),
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
        GameDropdown<String>(
          label: 'Item to enchant',
          value: selected,
          items: [
            for (final target in detail.enchantTargets)
              GameDropdownItem(value: target.id, label: target.label),
          ],
          onChanged: (value) => setState(() {
            _enchantTargetId = value;
            _error = null;
          }),
        ),
        const SizedBox(height: 8),
        GameButton(label: 'Complete project', onPressed: () => _complete(detail, 1)),
      ],
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
                    style: const TextStyle(fontWeight: FontWeight.w400),
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
                  fontWeight: FontWeight.w400,
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
  return showGamePopup<void>(
    context: context,
    builder: (context) => GamePopupCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const MutedText('Project complete'),
          Text(
            receipt.projectName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400),
          ),
          const SizedBox(height: 8),
          for (final line in receipt.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('· $line', style: const TextStyle(color: Palette.gold)),
            ),
          const SizedBox(height: 10),
          GameButton(label: 'Collect', onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    ),
  );
}
