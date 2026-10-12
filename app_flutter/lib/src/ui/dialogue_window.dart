import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'social_bits.dart';

/// Reusable standalone dialogue card (extracted look from NPC talk).
class DialogueWindow extends StatelessWidget {
  const DialogueWindow({
    super.key,
    required this.view,
    required this.onChoose,
    required this.onClose,
    this.message,
    this.error,
  });

  final DialogueView view;
  final void Function(String choiceId) onChoose;
  final VoidCallback onClose;
  final String? message;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return GamePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IgnorePointer(child: NpcPortrait(npcId: view.npcId, size: 68)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  view.speakerName,
                  style: const TextStyle(fontSize: GameFont.l, fontWeight: FontWeight.w400),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(view.line, style: const TextStyle(fontSize: GameFont.m)),
          if (message case final notice?) ...[const SizedBox(height: 4), MutedText(notice)],
          if (error case final err?) ...[
            const SizedBox(height: 6),
            Text(
              err,
              style: const TextStyle(color: Palette.danger, fontSize: GameFont.s),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              for (final choice in view.choices)
                GameButton(label: choice.label, onPressed: () => onChoose(choice.choiceId)),
              if (view.choices.isEmpty) GameButton(label: 'Close', onPressed: onClose),
            ],
          ),
        ],
      ),
    );
  }
}

/// Controller-backed host that starts and advances a standalone dialogue.
class StandaloneDialogueHost extends StatefulWidget {
  const StandaloneDialogueHost({
    super.key,
    required this.controller,
    required this.dialogueId,
    required this.onClose,
  });

  final GameController controller;
  final String dialogueId;
  final VoidCallback onClose;

  @override
  State<StandaloneDialogueHost> createState() => _StandaloneDialogueHostState();
}

class _StandaloneDialogueHostState extends State<StandaloneDialogueHost> {
  DialogueView? _view;
  String? _error;
  String? _message;

  GameController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    final started = startDialogue(controller.db, controller.save, widget.dialogueId);
    if (!started.ok || started.view == null) {
      _error = started.reason;
    } else {
      _view = started.view;
    }
  }

  void _choose(String choiceId) {
    final view = _view;
    if (view == null) return;
    final result = chooseDialogue(
      controller.db,
      controller.save,
      view.dialogueId,
      view.nodeId,
      choiceId,
    );
    if (!result.ok) {
      setState(() => _error = result.reason);
      return;
    }
    controller.commit(
      result.save,
      command: 'dialogue_choose',
      args: <String, Object?>{
        'dialogueId': view.dialogueId,
        'nodeId': view.nodeId,
        'choiceId': choiceId,
      },
    );
    if (result.message != null) controller.announce(result.message!);
    if (result.completed || result.view == null) {
      widget.onClose();
      return;
    }
    setState(() {
      _view = result.view;
      _error = null;
      _message = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    if (view == null) {
      return GamePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _error ?? 'That conversation could not be started.',
              style: const TextStyle(color: Palette.danger),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: GameButton(label: 'Close', onPressed: widget.onClose),
            ),
          ],
        ),
      );
    }
    return DialogueWindow(
      view: view,
      onChoose: _choose,
      onClose: widget.onClose,
      message: _message,
      error: _error,
    );
  }
}
