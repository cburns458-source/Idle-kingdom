import 'package:flutter/material.dart';

import '../session/multiplayer_controller.dart';
import '../theme.dart';

/// Asked once per account, before the first character name.
class AgeGateSheet extends StatefulWidget {
  const AgeGateSheet({super.key, required this.multiplayer});

  final MultiplayerController multiplayer;

  @override
  State<AgeGateSheet> createState() => _AgeGateSheetState();
}

class _AgeGateSheetState extends State<AgeGateSheet> {
  int? _year;
  String? _error;
  bool _busy = false;

  List<int> get _years {
    final nowYear = DateTime.now().toUtc().year;
    return [for (var year = nowYear; year >= nowYear - 120; year--) year];
  }

  Future<void> _submit() async {
    if (_busy) return;
    final year = _year;
    if (year == null) {
      setState(() => _error = 'Enter the year you were born.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final reason = await widget.multiplayer.submitAccountAge(birthYear: year);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = reason;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: chromeBoardFill(context),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<int>(
              key: const Key('age-year'),
              initialValue: _year,
              isExpanded: true,
              menuMaxHeight: 280,
              decoration: const InputDecoration(
                labelText: 'Birth year',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final year in _years) DropdownMenuItem(value: year, child: Text('$year')),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                      _year = value;
                      _error = null;
                    }),
            ),
            const SizedBox(height: 16),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(error, style: const TextStyle(color: Palette.danger)),
              ),
            GameButton(label: 'Continue', onPressed: _busy ? null : _submit, waiting: _busy),
          ],
        ),
      ),
    );
  }
}
