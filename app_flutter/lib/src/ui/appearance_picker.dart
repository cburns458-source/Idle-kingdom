import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../theme.dart';

/// The appearance rows, one discrete slider each.
///
/// Shared by character creation and the wardrobe, which is why it takes an
/// appearance and hands back a category and an option rather than a save.
class AppearancePicker extends StatelessWidget {
  const AppearancePicker({
    super.key,
    required this.db,
    required this.appearance,
    required this.onSelect,
  });

  final GameDatabase db;
  final PlayerAppearance appearance;
  final void Function(AppearanceCategory category, String optionId) onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final slider in appearanceSliders(db, appearance))
          _SliderRow(slider: slider, onSelect: (optionId) => onSelect(slider.category, optionId)),
      ],
    );
  }
}

/// A slider with one stop per option — no value text, since the portrait is the
/// preview.
class _SliderRow extends StatelessWidget {
  const _SliderRow({required this.slider, required this.onSelect});

  final AppearanceSlider slider;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final maxIndex = slider.optionIds.length - 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MutedText(slider.label),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Palette.gold,
              inactiveTrackColor: Palette.edge,
              thumbColor: Palette.gold,
              overlayShape: SliderComponentShape.noOverlay,
              trackHeight: 4,
            ),
            child: Slider(
              value: slider.selectedIndex.toDouble(),
              min: 0,
              max: maxIndex <= 0 ? 1 : maxIndex.toDouble(),
              divisions: maxIndex <= 0 ? null : maxIndex,
              label: slider.label,
              onChanged: maxIndex <= 0
                  ? null
                  : (value) => onSelect(slider.optionIds[value.round()]),
            ),
          ),
        ],
      ),
    );
  }
}
