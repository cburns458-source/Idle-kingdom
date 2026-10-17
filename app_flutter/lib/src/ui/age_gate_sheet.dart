import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';

import '../session/multiplayer_controller.dart';
import '../theme.dart';

/// Asked once per account, before the first character name.
class AgeGateSheet extends StatefulWidget {
  const AgeGateSheet({
    super.key,
    required this.multiplayer,
    this.signalSource = const FallbackAgeSignalSource(),
  });

  final MultiplayerController multiplayer;
  final AgeSignalSource signalSource;

  @override
  State<AgeGateSheet> createState() => _AgeGateSheetState();
}

class _AgeGateSheetState extends State<AgeGateSheet> {
  final TextEditingController _yearText = TextEditingController();
  int? _year;
  int? _month;
  String? _error;
  bool _busy = false;
  bool _askedStore = false;

  @override
  void dispose() {
    _yearText.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryStoreSignal());
  }

  Future<void> _tryStoreSignal() async {
    if (_askedStore) return;
    _askedStore = true;
    final signal = await widget.signalSource.requestDeclaredAge();
    if (!mounted || signal == null || !isStoreAgeBand(signal.band)) return;
    setState(() => _busy = true);
    final reason = await widget.multiplayer.submitAccountAge(
      source: 'store_signal',
      ageBand: signal.band,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = reason;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final year = _year;
    if (year == null) {
      setState(() => _error = 'Enter the year you were born.');
      return;
    }
    final asOf = DateTime.now().toUtc();
    if (needsBirthMonth(year, asOf) && _month == null) {
      setState(() => _error = 'Enter the month you were born.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final reason = await widget.multiplayer.submitAccountAge(
      birthYear: year,
      birthMonth: _month,
      source: 'self',
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = reason;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showMonth = _year != null && needsBirthMonth(_year!);

    return DecoratedBox(
      decoration: chromeBoardFill(context),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              ageGateTitle,
              style: TextStyle(fontSize: GameFont.xl, fontWeight: FontWeight.w400),
            ),
            const SizedBox(height: 8),
            const MutedText(ageGateBody),
            const SizedBox(height: 16),
            TextField(
              key: const Key('age-year'),
              controller: _yearText,
              keyboardType: TextInputType.number,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Birth year',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() {
                _year = int.tryParse(value.trim());
                _error = null;
              }),
            ),
            if (showMonth) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: const Key('age-month'),
                initialValue: _month,
                decoration: const InputDecoration(
                  labelText: 'Birth month',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('January')),
                  DropdownMenuItem(value: 2, child: Text('February')),
                  DropdownMenuItem(value: 3, child: Text('March')),
                  DropdownMenuItem(value: 4, child: Text('April')),
                  DropdownMenuItem(value: 5, child: Text('May')),
                  DropdownMenuItem(value: 6, child: Text('June')),
                  DropdownMenuItem(value: 7, child: Text('July')),
                  DropdownMenuItem(value: 8, child: Text('August')),
                  DropdownMenuItem(value: 9, child: Text('September')),
                  DropdownMenuItem(value: 10, child: Text('October')),
                  DropdownMenuItem(value: 11, child: Text('November')),
                  DropdownMenuItem(value: 12, child: Text('December')),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        _month = value;
                        _error = null;
                      }),
              ),
            ],
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
