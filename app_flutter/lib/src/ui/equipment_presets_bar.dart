import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../theme.dart';
import 'game_image.dart';
import 'game_popup.dart';

const _roman = <String>['I', 'II', 'III', 'IV'];

/// Square side on the location stage: room for III or a skill icon, not a sliver.
const double _stageSquare = 32;

/// Preset buttons (optional Current / Save chips); used above the paper doll and on location art.
class EquipmentPresetsBar extends StatelessWidget {
  const EquipmentPresetsBar({
    super.key,
    required this.controller,
    this.axis = Axis.horizontal,
    this.compact = false,
    this.showSaveButton = true,
    this.showSettingsButton = false,
    this.showCurrentButton = false,
    this.allowLongPressEdit = true,
    this.selectedPresetIndex,
    this.onSelectCurrent,
    this.onSelectPreset,
    this.onMessage,
  });

  final GameController controller;
  final Axis axis;
  final bool compact;
  final bool showSaveButton;
  final bool showSettingsButton;

  /// Equipment page only: current worn gear, shown before the four presets.
  final bool showCurrentButton;

  /// When false (location stage), taps only switch presets.
  final bool allowLongPressEdit;

  /// Equipment-page selection: which preset the paper doll is editing.
  final int? selectedPresetIndex;
  final VoidCallback? onSelectCurrent;
  final ValueChanged<int>? onSelectPreset;
  final ValueChanged<String>? onMessage;

  @override
  Widget build(BuildContext context) {
    final save = controller.save;
    final presets = save.equipmentPresets;
    final buttons = <Widget>[
      if (showCurrentButton)
        _LabelChip(
          compact: compact,
          square: compact && axis == Axis.vertical,
          label: 'Current',
          semanticsLabel: 'Current loadout',
          selected: true,
          onPressed: () => onSelectCurrent?.call(),
        ),
      for (var i = 0; i < equipmentPresetCount; i += 1)
        _PresetButton(
          preset: i < presets.length ? presets[i] : null,
          index: i,
          selected: shouldHighlightEquipmentPreset(save, i) || i == selectedPresetIndex,
          compact: compact,
          square: compact && axis == Axis.vertical,
          skillsById: controller.indexes.skillsById,
          tooltipHint: allowLongPressEdit ? 'Long-press to edit name' : 'Tap to switch preset',
          onTap: () {
            final result = applyEquipmentPreset(controller.db, controller.save, i);
            if (!result.ok) {
              onMessage?.call(result.reason ?? 'Could not switch presets.');
              return;
            }
            controller.commitLoadout(result.save!);
            if (result.warning != null) onMessage?.call(result.warning!);
            onSelectPreset?.call(i);
          },
          onLongPress: allowLongPressEdit ? () => _editPreset(context, i) : null,
        ),
      if (showSaveButton)
        _SaveChip(
          compact: compact,
          square: compact && axis == Axis.vertical,
          onPressed: () {
            controller.commitLoadout(saveActiveEquipmentPreset(controller.save));
            onMessage?.call('Preset saved.');
          },
        ),
      if (showSettingsButton)
        _SettingsChip(
          compact: compact,
          square: compact && axis == Axis.vertical,
          onPressed: () => _openPresetSettings(context),
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

  Future<void> _openPresetSettings(BuildContext context) async {
    final save = controller.save;
    final skills = controller.db.skills
        .where((row) => row.raw['Release Phase'] == 'Launch')
        .toList();
    final presets = [
      for (var i = 0; i < equipmentPresetCount; i += 1)
        i < save.equipmentPresets.length
            ? save.equipmentPresets[i]
            : EquipmentPreset(
                name: 'Preset ${i + 1}',
                icon: defaultEquipmentPresetIcon(i),
                slots: const {},
              ),
    ];

    final result = await showGamePopup<List<EquipmentPreset>?>(
      context: context,
      builder: (context) {
        return _AllPresetsSettingsDialog(
          presets: presets,
          skills: skills,
          skillsById: controller.indexes.skillsById,
        );
      },
    );

    if (result == null) return;
    var next = controller.save;
    for (var i = 0; i < result.length; i += 1) {
      next = renameEquipmentPreset(next, i, result[i].name);
      next = setEquipmentPresetIcon(next, i, result[i].icon);
    }
    controller.commit(next);
    onMessage?.call('Preset settings saved.');
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
                    _PresetIconPicker(
                      icon: icon,
                      skills: skills,
                      onChanged: (next) => setLocal(() => icon = next),
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
  const _SaveChip({required this.onPressed, required this.compact, required this.square});

  final VoidCallback onPressed;
  final bool compact;
  final bool square;

  @override
  Widget build(BuildContext context) {
    return _LabelChip(
      compact: compact,
      square: square,
      label: 'Save',
      semanticsLabel: 'Save preset',
      onPressed: onPressed,
    );
  }
}

class _LabelChip extends StatelessWidget {
  const _LabelChip({
    required this.onPressed,
    required this.compact,
    required this.square,
    required this.label,
    required this.semanticsLabel,
    this.selected = false,
  });

  final VoidCallback onPressed;
  final bool compact;
  final bool square;
  final String label;
  final String semanticsLabel;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final step = square ? 2.0 : 2.0;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel,
      child: Material(
        color: selected ? Palette.gold.withValues(alpha: 0.22) : Palette.slot,
        shape: PixelSteppedBorder(
          step: step,
          side: BorderSide(
            color: selected ? Palette.gold : Palette.edge,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onPressed,
          customBorder: PixelSteppedBorder(step: step),
          child: SizedBox(
            width: square ? _stageSquare : null,
            height: square ? _stageSquare : (compact ? 28 : 34),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: gameFontFamily,
                  fontSize: square ? 10 : 11,
                  fontWeight: FontWeight.w400,
                  color: Palette.heading,
                  height: 1,
                  shadows: square ? overlayShadow : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsChip extends StatelessWidget {
  const _SettingsChip({required this.onPressed, required this.compact, required this.square});

  final VoidCallback onPressed;
  final bool compact;
  final bool square;

  @override
  Widget build(BuildContext context) {
    final step = square ? 2.0 : 2.0;
    return Tooltip(
      message: 'Preset settings',
      child: Semantics(
        button: true,
        label: 'Preset settings',
        child: Material(
          color: Palette.slot,
          shape: PixelSteppedBorder(step: step),
          child: InkWell(
            onTap: onPressed,
            customBorder: PixelSteppedBorder(step: step),
            child: SizedBox(
              width: square ? _stageSquare : null,
              height: square ? _stageSquare : (compact ? 28 : 34),
              child: Center(
                child: Icon(
                  Icons.settings,
                  size: square ? 16 : 15,
                  color: Palette.heading,
                  shadows: square ? overlayShadow : null,
                ),
              ),
            ),
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
    required this.square,
    required this.skillsById,
    required this.onTap,
    this.onLongPress,
    this.tooltipHint = 'Long-press to edit name',
  });

  final EquipmentPreset? preset;
  final int index;
  final bool selected;
  final bool compact;
  final bool square;
  final Map<String, SkillRow> skillsById;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String tooltipHint;

  @override
  Widget build(BuildContext context) {
    final icon = preset?.icon ?? defaultEquipmentPresetIcon(index);
    final label = preset?.name ?? 'Preset ${index + 1}';
    final step = square ? 2.0 : 2.0;
    return Tooltip(
      message: '$label\n$tooltipHint',
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Material(
          color: selected ? Palette.gold.withValues(alpha: 0.22) : Palette.slot,
          shape: PixelSteppedBorder(
            step: step,
            side: BorderSide(
              color: selected ? Palette.gold : Palette.edge,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            customBorder: PixelSteppedBorder(step: step),
            child: SizedBox(
              width: square ? _stageSquare : null,
              height: square ? _stageSquare : (compact ? 28 : 34),
              child: Center(
                child: _PresetIcon(
                  icon: icon,
                  skillsById: skillsById,
                  size: square ? 18 : (compact ? 14 : 16),
                ),
              ),
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
      style: TextStyle(
        fontFamily: gameFontFamily,
        fontSize: size - 1,
        fontWeight: FontWeight.w400,
        color: Palette.heading,
        height: 1,
        shadows: overlayShadow,
      ),
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
      color: selected ? Palette.gold.withValues(alpha: 0.25) : Palette.slot,
      shape: PixelSteppedBorder(
        step: 2,
        side: BorderSide(color: selected ? Palette.gold : Palette.edge),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.zero /* pixel step 2 */,
        child: SizedBox(width: 32, height: 32, child: Center(child: child)),
      ),
    );
  }
}

class _AllPresetsSettingsDialog extends StatefulWidget {
  const _AllPresetsSettingsDialog({
    required this.presets,
    required this.skills,
    required this.skillsById,
  });

  final List<EquipmentPreset> presets;
  final List<SkillRow> skills;
  final Map<String, SkillRow> skillsById;

  @override
  State<_AllPresetsSettingsDialog> createState() => _AllPresetsSettingsDialogState();
}

class _AllPresetsSettingsDialogState extends State<_AllPresetsSettingsDialog> {
  late final List<TextEditingController> _nameControllers;
  late final List<EquipmentPresetIcon> _icons;

  @override
  void initState() {
    super.initState();
    _nameControllers = [
      for (final preset in widget.presets) TextEditingController(text: preset.name),
    ];
    _icons = [for (final preset in widget.presets) preset.icon];
  }

  @override
  void dispose() {
    for (final controller in _nameControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    final next = <EquipmentPreset>[
      for (var i = 0; i < widget.presets.length; i += 1)
        widget.presets[i].copyWith(name: _nameControllers[i].text, icon: _icons[i]),
    ];
    Navigator.of(context).pop(next);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Preset settings', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.6),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var i = 0; i < widget.presets.length; i += 1) ...[
                      if (i > 0) const SizedBox(height: 12),
                      _PresetSettingsRow(
                        index: i,
                        nameController: _nameControllers[i],
                        icon: _icons[i],
                        skills: widget.skills,
                        skillsById: widget.skillsById,
                        onIconChanged: (icon) => setState(() => _icons[i] = icon),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GameButton(
                    label: 'Cancel',
                    tone: GameButtonTone.secondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GameButton(label: 'Save', onPressed: _save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetSettingsRow extends StatelessWidget {
  const _PresetSettingsRow({
    required this.index,
    required this.nameController,
    required this.icon,
    required this.skills,
    required this.skillsById,
    required this.onIconChanged,
  });

  final int index;
  final TextEditingController nameController;
  final EquipmentPresetIcon icon;
  final List<SkillRow> skills;
  final Map<String, SkillRow> skillsById;
  final ValueChanged<EquipmentPresetIcon> onIconChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Palette.slot,
        borderRadius: BorderRadius.zero /* pixel step 2 */,
        border: Border.all(color: Palette.edge),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _PresetIcon(icon: icon, skillsById: skillsById, size: 18),
                const SizedBox(width: 8),
                Text('Preset ${index + 1}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
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
            _PresetIconPicker(icon: icon, skills: skills, onChanged: onIconChanged),
          ],
        ),
      ),
    );
  }
}

class _PresetIconPicker extends StatelessWidget {
  const _PresetIconPicker({required this.icon, required this.skills, required this.onChanged});

  final EquipmentPresetIcon icon;
  final List<SkillRow> skills;
  final ValueChanged<EquipmentPresetIcon> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MutedText('Icon'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var n = 1; n <= 4; n += 1)
              _IconChoice(
                selected: icon.kind == 'roman' && icon.numeral == n,
                onTap: () => onChanged(EquipmentPresetIcon(kind: 'roman', numeral: n)),
                child: Text(_roman[n - 1], style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            _IconChoice(
              selected: icon.kind == 'coin',
              onTap: () => onChanged(const EquipmentPresetIcon(kind: 'coin')),
              child: GameImage(goldIconPath(), width: 18, height: 18),
            ),
            for (final skill in skills)
              _IconChoice(
                selected: icon.kind == 'skill' && icon.skillId == skill.skillId,
                onTap: () => onChanged(EquipmentPresetIcon(kind: 'skill', skillId: skill.skillId)),
                child: GameImage(skillIconPath(skill), width: 18, height: 18),
              ),
          ],
        ),
      ],
    );
  }
}
