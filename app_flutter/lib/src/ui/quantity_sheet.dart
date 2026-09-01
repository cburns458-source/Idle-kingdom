import 'package:flutter/material.dart';

import '../theme.dart';
import 'format.dart';
import 'game_popup.dart';

/// Asks for a whole number, with a keypad so a thumb can answer.
///
/// Returns the chosen quantity, or null when dismissed. The keypad is here
/// because a phone keyboard covers the panel that asked, and because the same
/// dialog is reached from shops, crafting and projects.
Future<int?> askQuantity(
  BuildContext context, {
  required String title,
  String? subtitle,

  /// Lines under the title: what a unit costs, how many are on hand.
  List<String> details = const <String>[],
  String confirmLabel = 'Confirm',
  int initialValue = 1,
  int min = 1,
  int? max,
}) {
  return showGamePopup<int>(
    context: context,
    builder: (context) => _QuantitySheet(
      title: title,
      subtitle: subtitle,
      details: details,
      confirmLabel: confirmLabel,
      initialValue: initialValue,
      min: min,
      max: max,
    ),
  );
}

class _QuantitySheet extends StatefulWidget {
  const _QuantitySheet({
    required this.title,
    required this.subtitle,
    required this.details,
    required this.confirmLabel,
    required this.initialValue,
    required this.min,
    required this.max,
  });

  final String title;
  final String? subtitle;
  final List<String> details;
  final String confirmLabel;
  final int initialValue;
  final int min;
  final int? max;

  @override
  State<_QuantitySheet> createState() => _QuantitySheetState();
}

class _QuantitySheetState extends State<_QuantitySheet> {
  late String _text = '${widget.initialValue < widget.min ? widget.min : widget.initialValue}';
  String? _error;

  /// False until a key is pressed, so the first digit replaces the suggested
  /// amount instead of appending to it — typing 2 over a prefilled 1 means two.
  bool _edited = false;

  void _append(String digit) {
    setState(() {
      _error = null;
      final next = !_edited || _text == '0' ? digit : '$_text$digit';
      _edited = true;
      if (next.length <= 9) _text = next;
    });
  }

  void _backspace() {
    setState(() {
      _error = null;
      _edited = true;
      _text = _text.length <= 1 ? '0' : _text.substring(0, _text.length - 1);
    });
  }

  void _confirm() {
    final parsed = int.tryParse(_text.trim());
    if (parsed == null || parsed < widget.min) {
      setState(() => _error = 'Enter a whole number of at least ${widget.min}.');
      return;
    }
    final ceiling = widget.max;
    if (ceiling != null && parsed > ceiling) {
      setState(() => _error = 'Maximum is ${formatThousands(ceiling)}.');
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final ceiling = widget.max;
    return GamePopupCard(
      child: GamePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.subtitle case final subtitle?) MutedText(subtitle),
            Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400)),
            for (final line in widget.details)
              Padding(padding: const EdgeInsets.only(top: 2), child: MutedText(line)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Palette.panel,
                      borderRadius: BorderRadius.zero /* pixel step 2 */,
                      border: Border.all(color: Palette.edge),
                    ),
                    child: Text(
                      _text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w400),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GameButton(
                  label: 'Max',
                  tone: GameButtonTone.secondary,
                  compact: true,
                  onPressed: ceiling == null || ceiling < widget.min
                      ? null
                      : () => setState(() {
                          _error = null;
                          _edited = true;
                          _text = '$ceiling';
                        }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 2,
              children: [
                for (final key in const ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'C', '0'])
                  GameButton(
                    label: key,
                    tone: GameButtonTone.secondary,
                    compact: true,
                    onPressed: () => key == 'C'
                        ? setState(() {
                            _edited = true;
                            _text = '0';
                          })
                        : _append(key),
                  ),
                GameIconButton(
                  icon: Icons.backspace_outlined,
                  tooltip: 'Backspace',
                  onPressed: _backspace,
                ),
              ],
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 6),
              Text(error, style: const TextStyle(color: Palette.danger, fontSize: 12)),
            ],
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
                  child: GameButton(label: widget.confirmLabel, onPressed: _confirm),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
