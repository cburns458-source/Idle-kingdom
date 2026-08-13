import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ik_runtime/ik_runtime.dart';

import '../session/game_controller.dart';
import '../theme.dart';

/// Copying this device's save out, and pasting another one in.
///
/// This is the way off the retired React client and between devices without an
/// account, so it stays available whether or not anyone is signed in: the cloud
/// save above needs a backend, and this needs nothing.
class SaveTransferSection extends StatefulWidget {
  const SaveTransferSection({super.key, required this.controller});

  final GameController controller;

  @override
  State<SaveTransferSection> createState() => _SaveTransferSectionState();
}

class _SaveTransferSectionState extends State<SaveTransferSection> {
  final TextEditingController _pasted = TextEditingController();
  String? _notice;

  @override
  void dispose() {
    _pasted.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: exportSaveText(widget.controller.save)));
    if (!mounted) return;
    setState(() => _notice = saveCopiedNotice);
  }

  Future<void> _import() async {
    final result = importSaveText(_pasted.text, widget.controller.session.clock());
    if (!result.ok) {
      setState(() => _notice = result.reason);
      return;
    }
    final save = result.save!;
    // Adopting is destructive and cannot be undone from here, so it is asked
    // rather than assumed.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace this character?'),
        content: Text(saveTransferBlurb),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.controller.commit(save);
    _pasted.clear();
    setState(() => _notice = saveImportedNotice(save));
  }

  @override
  Widget build(BuildContext context) {
    return GamePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            saveTransferHeading,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const MutedText(saveTransferBlurb),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: _copy, child: const Text('Copy save')),
          const SizedBox(height: 8),
          TextField(
            controller: _pasted,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(hintText: saveImportHint),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _import, child: const Text('Import save')),
          if (_notice case final notice?) ...[
            const SizedBox(height: 8),
            Text(notice, style: const TextStyle(color: Palette.gold, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
