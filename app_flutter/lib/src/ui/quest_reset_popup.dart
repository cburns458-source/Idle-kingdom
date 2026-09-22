import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'game_popup.dart';

/// Testing cheat: pick quests and intro flags to clear.
Future<void> showQuestResetPopup({
  required BuildContext context,
  required GameController controller,
  required ValueChanged<String?> onRan,
}) {
  return showGamePopup<void>(
    context: context,
    builder: (context) => _QuestResetPopup(controller: controller, onRan: onRan),
  );
}

class _QuestResetPopup extends StatefulWidget {
  const _QuestResetPopup({required this.controller, required this.onRan});

  final GameController controller;
  final ValueChanged<String?> onRan;

  @override
  State<_QuestResetPopup> createState() => _QuestResetPopupState();
}

class _QuestResetPopupState extends State<_QuestResetPopup> {
  final Set<String> _questIds = <String>{};
  bool _fennel = false;
  bool _wardrobe = false;

  GameController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final rows = [...asQuestRows(controller.db)]
      ..sort((a, b) {
        final left = (a['Display Name'] as String?) ?? '';
        final right = (b['Display Name'] as String?) ?? '';
        return left.compareTo(right);
      });
    return GamePopupCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Reset quests',
            style: TextStyle(fontSize: gamePopupTitleSize, fontWeight: FontWeight.w400),
          ),
          const SizedBox(height: 4),
          const MutedText('Clears progress so those quests can be taken again.'),
          const SizedBox(height: 8),
          _FlagRow(
            label: 'Fennel intro',
            value: _fennel,
            onChanged: (value) => setState(() => _fennel = value),
          ),
          _FlagRow(
            label: 'Wardrobe intro',
            value: _wardrobe,
            onChanged: (value) => setState(() => _wardrobe = value),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              GameTextButton(
                label: 'All',
                onPressed: () => setState(() {
                  _questIds
                    ..clear()
                    ..addAll(rows.map((row) => row['Quest ID']).whereType<String>());
                }),
              ),
              const SizedBox(width: 6),
              GameTextButton(label: 'None', onPressed: () => setState(() => _questIds.clear())),
            ],
          ),
          const SizedBox(height: 6),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final row in rows)
                  _QuestRow(
                    title: (row['Display Name'] as String?) ?? row['Quest ID'] as String,
                    status: questStatusLabel(
                      getQuestProgress(controller.save, row['Quest ID'] as String).status,
                    ),
                    selected: _questIds.contains(row['Quest ID']),
                    onChanged: (value) {
                      final id = row['Quest ID'] as String;
                      setState(() {
                        if (value) {
                          _questIds.add(id);
                        } else {
                          _questIds.remove(id);
                        }
                      });
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              GameButton(
                label: 'Cancel',
                tone: GameButtonTone.secondary,
                compact: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GameButton(
                  label: 'Reset selected',
                  compact: true,
                  onPressed: () {
                    final notice = controller.debugResetQuests(
                      _questIds.toList(),
                      fennel: _fennel,
                      wardrobe: _wardrobe,
                    );
                    widget.onRan(notice);
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FlagRow extends StatelessWidget {
  const _FlagRow({required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: (next) => onChanged(next ?? false),
            visualDensity: VisualDensity.compact,
          ),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

class _QuestRow extends StatelessWidget {
  const _QuestRow({
    required this.title,
    required this.status,
    required this.selected,
    required this.onChanged,
  });

  final String title;
  final String status;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!selected),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: selected,
            onChanged: (next) => onChanged(next ?? false),
            visualDensity: VisualDensity.compact,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  MutedText(status),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
