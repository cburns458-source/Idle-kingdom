import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../theme.dart';
import 'game_image.dart';
import 'game_popup.dart';

const _roman = <String>['I', 'II', 'III', 'IV'];

/// Four preset buttons plus Save; used above the paper doll and on location art.
class EquipmentPresetsBar extends StatelessWidget {
  const EquipmentPresetsBar({
    super.key,
    required this.controller,
    this.axis = Axis.horizontal,
    this.compact = false,
    this.onMessage,
  });

  final GameController controller;
  final Axis axis;
  final bool compact;
  final ValueChanged<String>? onMessage;

  @override
  Widget build(BuildContext context) {
    final save = controller.save;
    final presets = save.equipmentPresets;
    final active = save.activeEquipmentPresetIndex.floor().clamp(0, equipmentPresetCount - 1);
    final buttons = <Widget>[
      for (var i = 0; i < equipmentPresetCount; i += 1)
        _PresetButton(
          preset: i < presets.length ? presets[i] : null,
          index: i,
          selected: i == active,
          compact: compact,
          skillsById: controller.indexes.skillsById,
          onTap: () {
            final result = applyEquipmentPreset(controller.db, controller.save, i);
            if (!result.ok) {
              onMessage?.call(result.reason ?? 'Could not switch presets.');
              return;
            }
            controller.commitLoadout(result.save!);
          },
          onLongPress: () => _editPreset(context, i),
        ),
      _SaveChip(
        compact: compact,
        onPressed: () {
          controller.commitLoadout(saveActiveEquipmentPreset(controller.save));
          onMessage?.call('Preset saved.');
        },
      ),
    ];
    if (axis == Axis.vertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < buttons.length; i += 1) ...[
            if (i > 0) SizedBox(height: compact ? 4 : 6),
            buttons[i],
          ],
        ],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < buttons.length; i += 1) ...[
          if (i > 0) SizedBox(width: compact ? 4 : 6),
          Expanded(child: buttons[i]),
        ],
      ],
    );
  }

  Future<void> _editPreset(BuildContext context, int index) async {
    final save = controller.save;
    if (index < 0 || index >= save.equipmentPresets.length) return;
    final preset = save.equipmentPresets[index];
    final nameController = TextEditingController(text: preset.name);
    var icon = preset.icon;
    final skills = controller.db.skills
        .where((row) => row.raw['Release Phase'] == 'Launch')
        .toList();

    final confirmed = await showGamePopup<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return SizedBox(
              width: 340,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Preset ${index + 1}', style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameController,
                      maxLength: equipmentPresetNameMax,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const MutedText('Icon'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var n = 1; n <= 4; n += 1)
                          _IconChoice(
                            selected: icon.kind == 'roman' && icon.numeral == n,
                            onTap: () => setLocal(() {
                              icon = EquipmentPresetIcon(kind: 'roman', numeral: n);
                            }),
                            child: Text(
                              _roman[n - 1],
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        _IconChoice(
                          selected: icon.kind == 'coin',
                          onTap: () => setLocal(() {
                            icon = const EquipmentPresetIcon(kind: 'coin');
                          }),
                          child: GameImage(goldIconPath(), width: 18, height: 18),
                        ),
                        for (final skill in skills)
                          _IconChoice(
                            selected: icon.kind == 'skill' && icon.skillId == skill.skillId,
                            onTap: () => setLocal(() {
                              icon = EquipmentPresetIcon(kind: 'skill', skillId: skill.skillId);
                            }),
                            child: GameImage(skillIconPath(skill), width: 18, height: 18),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: GameButton(
                            label: 'Cancel',
                            tone: GameButtonTone.secondary,
                            onPressed: () => Navigator.of(context).pop(false),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GameButton(
                            label: 'Save',
                            onPressed: () => Navigator.of(context).pop(true),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (confirmed != true) {
      nameController.dispose();
      return;
    }
    var next = renameEquipmentPreset(controller.save, index, nameController.text);
    next = setEquipmentPresetIcon(next, index, icon);
    nameController.dispose();
    controller.commit(next);
  }
}

class _SaveChip extends StatelessWidget {
  const _SaveChip({required this.onPressed, required this.compact});

  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Palette.panel,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: compact ? 28 : 34,
          child: const Center(
            child: Text('Save', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}

class _PresetButton extends StatelessWidget {
  const _PresetButton({
    required this.preset,
    required this.index,
    required this.selected,
    required this.compact,
    required this.skillsById,
    required this.onTap,
    required this.onLongPress,
  });

  final EquipmentPreset? preset;
  final int index;
  final bool selected;
  final bool compact;
  final Map<String, SkillRow> skillsById;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final icon = preset?.icon ?? defaultEquipmentPresetIcon(index);
    return Tooltip(
      message: '${preset?.name ?? 'Preset ${index + 1}'}\nLong-press to edit',
      child: Material(
        color: selected ? Palette.gold.withValues(alpha: 0.22) : Palette.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: selected ? Palette.gold : Palette.edge,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: compact ? 28 : 34,
            child: Center(
              child: _PresetIcon(icon: icon, skillsById: skillsById, size: compact ? 14 : 16),
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetIcon extends StatelessWidget {
  const _PresetIcon({required this.icon, required this.skillsById, required this.size});

  final EquipmentPresetIcon icon;
  final Map<String, SkillRow> skillsById;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (icon.kind == 'coin') {
      return GameImage(goldIconPath(), width: size, height: size);
    }
    if (icon.kind == 'skill' && icon.skillId != null) {
      return GameImage(skillIconPath(skillsById[icon.skillId!]), width: size, height: size);
    }
    final n = (icon.numeral ?? 1).floor().clamp(1, 4);
    return Text(
      _roman[n - 1],
      style: TextStyle(fontSize: size - 1, fontWeight: FontWeight.w700, color: Palette.ink),
    );
  }
}

class _IconChoice extends StatelessWidget {
  const _IconChoice({required this.selected, required this.onTap, required this.child});

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Palette.gold.withValues(alpha: 0.25) : Palette.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: selected ? Palette.gold : Palette.edge),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(width: 32, height: 32, child: Center(child: child)),
      ),
    );
  }
}
