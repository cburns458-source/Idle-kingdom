import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../theme.dart';
import 'game_image.dart';
import 'game_popup.dart';

const _roman = <String>['I', 'II', 'III', 'IV'];

enum _PresetTapChoice { apply, edit }

/// Square side on the location stage: room for III or a skill icon, not a sliver.
const double _stageSquare = 32;

/// Equipment-page chips match the bar height so settings and presets stay square.
const double _pageSquare = 34;

double _chipSide({required bool compact}) => compact ? _stageSquare : _pageSquare;

double _chipHeight({required bool compact, required bool square}) {
  if (square) return _chipSide(compact: compact);
  return compact ? 28 : _pageSquare;
}

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
    this.onEditPreset,
    this.onSaveEditingPreset,
    this.onMessage,
  });

  final GameController controller;
  final Axis axis;
  final bool compact;
  final bool showSaveButton;
  final bool showSettingsButton;

  /// Equipment page only: current worn gear, shown before the four presets.
  final bool showCurrentButton;

  /// When false (location stage), taps apply the snapshot to worn gear.
  final bool allowLongPressEdit;

  /// Equipment-page selection: which preset the paper doll is editing.
  final int? selectedPresetIndex;
  final VoidCallback? onSelectCurrent;
  final ValueChanged<int>? onSelectPreset;
  final ValueChanged<int>? onEditPreset;
  final VoidCallback? onSaveEditingPreset;
  final ValueChanged<String>? onMessage;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: controller, builder: (context, _) => _bar(context));
  }

  bool get _editing => selectedPresetIndex != null;

  bool get _saveEnabled => onSaveEditingPreset != null ? _editing : !showCurrentButton || _editing;

  bool get _stageSquareChips => compact && axis == Axis.vertical;

  Widget _bar(BuildContext context) {
    final save = controller.save;
    final presets = save.equipmentPresets;
    final gap = compact ? 4.0 : 6.0;
    final current = showCurrentButton
        ? _LabelChip(
            key: const Key('current-loadout'),
            compact: compact,
            square: _stageSquareChips,
            label: 'Current',
            semanticsLabel: 'Current loadout',
            selected: selectedPresetIndex == null,
            filled: true,
            onPressed: () => onSelectCurrent?.call(),
          )
        : null;
    final presetButtons = [
      for (var i = 0; i < equipmentPresetCount; i += 1)
        _PresetButton(
          key: Key('preset-chip-$i'),
          preset: i < presets.length ? presets[i] : null,
          index: i,
          selected: i == selectedPresetIndex || shouldHighlightEquipmentPreset(save, i),
          compact: compact,
          square: _stageSquareChips || showCurrentButton,
          skillsById: controller.indexes.skillsById,
          tooltipHint: allowLongPressEdit
              ? 'Tap for Apply or Edit. Long-press to rename.'
              : 'Tap to apply this preset',
          onTap: () {
            if (showCurrentButton || onEditPreset != null) {
              _offerApplyOrEdit(context, i);
              return;
            }
            _applyPreset(i);
          },
          onLongPress: allowLongPressEdit ? () => _editPreset(context, i) : null,
        ),
    ];
    final saveChip = showSaveButton
        ? _SaveChip(
            compact: compact,
            square: _stageSquareChips,
            onPressed: _saveEnabled ? _saveSelectedPreset : null,
          )
        : null;
    final settings = showSettingsButton
        ? _SettingsChip(
            key: const Key('preset-settings'),
            compact: compact,
            square: _stageSquareChips || showCurrentButton,
            onPressed: () => _openPresetSettings(context),
          )
        : null;
    if (axis == Axis.vertical) {
      final buttons = [
        if (current != null) current,
        ...presetButtons,
        if (saveChip != null) saveChip,
        if (settings != null) settings,
      ];
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < buttons.length; i += 1) ...[
            if (i > 0) SizedBox(height: gap),
            buttons[i],
          ],
        ],
      );
    }
    if (showCurrentButton) {
      return Row(
        children: [
          if (current != null) Expanded(child: current),
          for (final preset in presetButtons) ...[SizedBox(width: gap), preset],
          if (saveChip != null) ...[SizedBox(width: gap), saveChip],
          if (settings != null) ...[SizedBox(width: gap), settings],
        ],
      );
    }
    final buttons = [
      ...presetButtons,
      if (saveChip != null) saveChip,
      if (settings != null) settings,
    ];
    return Row(
      children: [
        for (var i = 0; i < buttons.length; i += 1) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(child: buttons[i]),
        ],
      ],
    );
  }

  void _saveSelectedPreset() {
    final custom = onSaveEditingPreset;
    if (custom != null) {
      custom();
      return;
    }
    final target = showCurrentButton
        ? selectedPresetIndex
        : controller.save.activeEquipmentPresetIndex.floor();
    if (target == null || target < 0 || target >= equipmentPresetCount) return;
    controller.commitLoadout(
      saveActiveEquipmentPreset(controller.save.copyWith(activeEquipmentPresetIndex: target)),
    );
    onMessage?.call('Preset saved.');
  }

  void _applyPreset(int index) {
    final result = applyEquipmentPreset(controller.db, controller.save, index);
    if (!result.ok) {
      onMessage?.call(result.reason ?? 'Could not apply that preset.');
      return;
    }
    controller.commitLoadout(result.save!);
    if (result.warning != null) onMessage?.call(result.warning!);
    onSelectPreset?.call(index);
    onSelectCurrent?.call();
  }

  Future<void> _offerApplyOrEdit(BuildContext context, int index) async {
    final presets = controller.save.equipmentPresets;
    final name = index < presets.length ? presets[index].name : 'Preset ${index + 1}';
    final choice = await showGamePopup<_PresetTapChoice>(
      context: context,
      builder: (context) {
        return GamePopupCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400)),
              const SizedBox(height: 6),
              const MutedText('Apply wears this snapshot. Edit changes the snapshot only.'),
              const SizedBox(height: 12),
              GameButton(
                label: 'Apply',
                onPressed: () => Navigator.of(context).pop(_PresetTapChoice.apply),
              ),
              const SizedBox(height: 8),
              GameButton(
                label: 'Edit',
                tone: GameButtonTone.secondary,
                onPressed: () => Navigator.of(context).pop(_PresetTapChoice.edit),
              ),
              const SizedBox(height: 8),
              GameButton(
                label: 'Cancel',
                tone: GameButtonTone.secondary,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      },
    );
    if (!context.mounted || choice == null) return;
    switch (choice) {
      case _PresetTapChoice.apply:
        _applyPreset(index);
      case _PresetTapChoice.edit:
        (onEditPreset ?? onSelectPreset)?.call(index);
    }
  }

  void _commitPresetIcon(int index, EquipmentPresetIcon icon) {
    controller.commit(setEquipmentPresetIcon(controller.save, index, icon));
  }

  Future<void> _openPresetSettings(BuildContext context) async {
    final save = controller.save;
    final skills = controller.db.skills.where((row) => row.releasePhase == 'Launch').toList();
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
          controller: controller,
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
    }
    controller.commit(next);
    onMessage?.call('Preset settings saved.');
  }

  Future<void> _editPreset(BuildContext context, int index) async {
    final save = trackActiveEquipmentPreset(controller.save);
    if (index < 0 || index >= save.equipmentPresets.length) return;
    final preset = save.equipmentPresets[index];
    final nameController = TextEditingController(text: preset.name);
    var icon = preset.icon;
    final skills = controller.db.skills.where((row) => row.releasePhase == 'Launch').toList();

    final confirmed = await showGamePopup<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return SizedBox(
              width: 340,
              child: SingleChildScrollView(
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
                        onChanged: (next) {
                          setLocal(() => icon = next);
                          _commitPresetIcon(index, next);
                        },
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

  final VoidCallback? onPressed;
  final bool compact;
  final bool square;

  @override
  Widget build(BuildContext context) {
    return _LabelChip(
      key: const Key('save-preset'),
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
    super.key,
    required this.onPressed,
    required this.compact,
    required this.square,
    required this.label,
    required this.semanticsLabel,
    this.selected = false,
    this.filled = false,
  });

  final VoidCallback? onPressed;
  final bool compact;
  final bool square;
  final String label;
  final String semanticsLabel;
  final bool selected;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final step = square ? 2.0 : 2.0;
    final chrome = UiChrome.of(context);
    final solid = filled || selected;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      selected: selected,
      label: semanticsLabel,
      child: Opacity(
        opacity: onPressed == null ? 0.45 : 1,
        child: Material(
          color: solid ? Palette.gold.withValues(alpha: selected ? 0.32 : 0.2) : chrome.slot,
          shape: PixelSteppedBorder(
            step: step,
            side: BorderSide(
              color: selected ? Palette.gold : (filled ? const Color(0xCCE8C36A) : Palette.edge),
              width: selected ? 3 : 1,
            ),
          ),
          child: InkWell(
            onTap: onPressed,
            customBorder: PixelSteppedBorder(step: step),
            child: SizedBox(
              width: square ? _chipSide(compact: compact) : null,
              height: _chipHeight(compact: compact, square: square),
              child: Padding(
                padding: square ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 8),
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
        ),
      ),
    );
  }
}

class _SettingsChip extends StatelessWidget {
  const _SettingsChip({
    super.key,
    required this.onPressed,
    required this.compact,
    required this.square,
  });

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
          color: UiChrome.of(context).slot,
          shape: PixelSteppedBorder(step: step),
          child: InkWell(
            onTap: onPressed,
            customBorder: PixelSteppedBorder(step: step),
            child: SizedBox(
              width: square ? _chipSide(compact: compact) : null,
              height: _chipHeight(compact: compact, square: square),
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
    super.key,
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
    final chrome = UiChrome.of(context);
    final fill = selected ? Color.lerp(chrome.slot, Palette.gold, 0.28)! : chrome.slot;
    return Tooltip(
      message: '$label\n$tooltipHint',
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Material(
          color: fill,
          shape: PixelSteppedBorder(
            step: step,
            side: BorderSide(
              color: selected ? Palette.gold : Palette.edge,
              width: selected ? 3 : 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            customBorder: PixelSteppedBorder(step: step),
            child: SizedBox(
              width: square ? _chipSide(compact: compact) : null,
              height: _chipHeight(compact: compact, square: square),
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
      final skill = skillsById[icon.skillId!];
      return Tooltip(
        message: skill?.displayName ?? icon.skillId!,
        child: GameImage(skillIconPath(skill), width: size, height: size),
      );
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
  const _IconChoice({
    required this.selected,
    required this.onTap,
    required this.child,
    this.tooltip,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final chrome = UiChrome.of(context);
    final tile = Material(
      color: selected ? Color.lerp(chrome.slot, chrome.embossFace, 0.18)! : chrome.slot,
      shape: PixelSteppedBorder(
        step: 2,
        side: BorderSide(
          color: selected ? chrome.embossFace : Palette.edge,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: PixelSteppedBorder(step: 2),
        child: SizedBox(width: 32, height: 32, child: Center(child: child)),
      ),
    );
    return tooltip == null ? tile : Tooltip(message: tooltip!, child: tile);
  }
}

class _AllPresetsSettingsDialog extends StatefulWidget {
  const _AllPresetsSettingsDialog({
    required this.controller,
    required this.presets,
    required this.skills,
    required this.skillsById,
  });

  final GameController controller;
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

  Widget _rowAt(int index) {
    return _PresetSettingsRow(
      index: index,
      nameController: _nameControllers[index],
      icon: _icons[index],
      skills: widget.skills,
      skillsById: widget.skillsById,
      onIconChanged: (icon) => _setIcon(index, icon),
    );
  }

  void _setIcon(int index, EquipmentPresetIcon icon) {
    setState(() => _icons[index] = icon);
    widget.controller.commit(setEquipmentPresetIcon(widget.controller.save, index, icon));
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
                      _rowAt(i),
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
        color: UiChrome.of(context).slot,
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

  bool _romanSelected(int n) => icon.kind == 'roman' && (icon.numeral ?? 0).floor() == n;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MutedText('Icon'),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 168),
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var n = 1; n <= 4; n += 1)
                  _IconChoice(
                    selected: _romanSelected(n),
                    tooltip: 'Roman ${_roman[n - 1]}',
                    onTap: () => onChanged(EquipmentPresetIcon(kind: 'roman', numeral: n)),
                    child: Text(_roman[n - 1], style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                _IconChoice(
                  selected: icon.kind == 'coin',
                  tooltip: 'Coin',
                  onTap: () => onChanged(const EquipmentPresetIcon(kind: 'coin')),
                  child: GameImage(goldIconPath(), width: 18, height: 18),
                ),
                for (final skill in skills)
                  _IconChoice(
                    selected: icon.kind == 'skill' && icon.skillId == skill.skillId,
                    tooltip: skill.displayName,
                    onTap: () =>
                        onChanged(EquipmentPresetIcon(kind: 'skill', skillId: skill.skillId)),
                    child: GameImage(skillIconPath(skill), width: 18, height: 18),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
