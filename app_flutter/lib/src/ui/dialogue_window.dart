import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'dialogue_text.dart';
import 'game_popup.dart';
import 'social_bits.dart';

/// Visible choices a player can see (hidden+disabled rows stay out).
List<DialogueChoiceView> visibleDialogueChoices(Iterable<DialogueChoiceView> choices) {
  return [
    for (final choice in choices)
      if (!(choice.hidden && !choice.enabled)) choice,
  ];
}

/// Tap-to-advance when a line has no branching choices.
VoidCallback? dialogueTapAdvance({
  required List<DialogueChoiceView> visible,
  required void Function(String choiceId) onChoose,
  required VoidCallback onClose,
}) {
  if (visible.length > 1) return null;
  if (visible.length == 1) {
    final choice = visible.single;
    return choice.enabled ? () => onChoose(choice.choiceId) : null;
  }
  return onClose;
}

/// Reusable standalone dialogue card (extracted look from NPC talk).
class DialogueWindow extends StatelessWidget {
  const DialogueWindow({
    super.key,
    required this.view,
    required this.text,
    required this.onChoose,
    required this.onClose,
    this.progress,
    this.message,
    this.error,
  });

  final DialogueView view;
  final DialogueText text;
  final void Function(String choiceId) onChoose;
  final VoidCallback onClose;

  /// Show / HandIn lines to list; defaults to the view's own.
  final List<StepProgressGroup>? progress;
  final String? message;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final groups = progress ?? view.stepProgress;
    final choices = visibleDialogueChoices(view.choices);
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
          for (final group in groups)
            for (final line in group.items) ...[
              const SizedBox(height: 4),
              Text(text.progressLine(group, line), style: const TextStyle(fontSize: GameFont.s)),
            ],
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
              for (final choice in choices)
                GameButton(
                  label: text.choiceLabel(choice, view.stepProgress) ?? choice.label,
                  onPressed: choice.enabled ? () => onChoose(choice.choiceId) : null,
                ),
              if (choices.isEmpty) GameButton(label: 'Close', onPressed: onClose),
            ],
          ),
        ],
      ),
    );
  }
}

/// Fennel's tutorial lines: portrait + current line along the bottom.
///
/// Tap advances a single-choice line. Branching choices stay as buttons.
class FennelDialoguePanel extends StatelessWidget {
  const FennelDialoguePanel({
    super.key,
    required this.view,
    required this.text,
    required this.onChoose,
    required this.onClose,
    this.progress,
    this.message,
    this.error,
  });

  final DialogueView view;
  final DialogueText text;
  final void Function(String choiceId) onChoose;
  final VoidCallback onClose;
  final List<StepProgressGroup>? progress;
  final String? message;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final groups = progress ?? view.stepProgress;
    final choices = visibleDialogueChoices(view.choices);
    final advance = dialogueTapAdvance(visible: choices, onChoose: onChoose, onClose: onClose);
    return Material(
      key: const Key('fennel-dialogue-panel'),
      color: Colors.transparent,
      child: GamePanel(
        onTap: advance,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IgnorePointer(child: NpcPortrait(npcId: view.npcId, size: 68)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(view.line, style: const TextStyle(fontSize: GameFont.m)),
                ),
              ],
            ),
            for (final group in groups)
              for (final line in group.items) ...[
                const SizedBox(height: 4),
                Text(text.progressLine(group, line), style: const TextStyle(fontSize: GameFont.s)),
              ],
            if (message case final notice?) ...[const SizedBox(height: 4), MutedText(notice)],
            if (error case final err?) ...[
              const SizedBox(height: 6),
              Text(
                err,
                style: const TextStyle(color: Palette.danger, fontSize: GameFont.s),
              ),
            ],
            if (choices.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  for (final choice in choices)
                    GameButton(
                      label: text.choiceLabel(choice, view.stepProgress) ?? choice.label,
                      onPressed: choice.enabled ? () => onChoose(choice.choiceId) : null,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bag `no_room` popup. [noRoom] picks a full stack or the make-room line.
Future<void> showDialogueBagFullPopup({
  required BuildContext context,
  NoRoom? noRoom,
  int? slotsNeeded,
}) async {
  await showGameAlert(
    context: context,
    message: DialogueText.noRoomPopup(noRoom, slotsNeeded: slotsNeeded),
  );
}

/// Yes/No prompt listing every favourited stack the engine returned.
Future<bool> showDialogueFavouritesPrompt({
  required BuildContext context,
  required DialogueText text,
  required List<DialogueItemDelta> favourites,
}) {
  return showGameAlert(
    context: context,
    message: '${DialogueText.favouritesPrompt}\n\n${text.favouritesList(favourites)}',
    confirmLabel: 'Yes',
    cancelLabel: 'No',
  );
}

/// Sends one choice. [useFavourites] is the player's yes for this request only.
typedef DialogueRequest = Future<DialogueResult> Function(
  DialogueView view,
  String choiceId, {
  required bool useFavourites,
});

/// Controller-backed host that starts and advances a standalone dialogue.
class StandaloneDialogueHost extends StatefulWidget {
  const StandaloneDialogueHost({
    super.key,
    required this.controller,
    required this.dialogueId,
    required this.onClose,
    this.request,
    this.docked = false,
  });

  final GameController controller;
  final String dialogueId;
  final VoidCallback onClose;

  /// Defaults to the local engine plus a `dialogue_choose` commit.
  final DialogueRequest? request;

  /// Bottom-of-screen Fennel panel used by the tutorial overlay.
  final bool docked;

  @override
  State<StandaloneDialogueHost> createState() => _StandaloneDialogueHostState();
}

class _StandaloneDialogueHostState extends State<StandaloneDialogueHost> {
  DialogueView? _view;
  String? _error;
  String? _message;

  /// Progress the last choice touched, kept on screen after the node moves on.
  List<StepProgressGroup> _touched = const <StepProgressGroup>[];

  /// One choice in flight at a time, held until the next frame so a double tap
  /// on the same button is dropped.
  bool _busy = false;

  late final DialogueText _text = DialogueText(controller.db);

  GameController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    final started = startDialogue(controller.db, controller.save, widget.dialogueId);
    if (!started.ok || started.view == null) {
      _error = _text.startFailure(started.code);
    } else {
      _view = started.view;
    }
  }

  Future<DialogueResult> _send(
    DialogueView view,
    String choiceId, {
    required bool useFavourites,
  }) async {
    final request = widget.request;
    if (request != null) return request(view, choiceId, useFavourites: useFavourites);
    final result = chooseDialogue(
      controller.db,
      controller.save,
      view.dialogueId,
      view.nodeId,
      choiceId,
      useFavourites: useFavourites,
    );
    if (result.ok) {
      // Queue before [commit]: its notify flushes the reward popup ahead of
      // any level-up the payout caused.
      controller.noteDialogueQuestCompletions(result.questCompletions);
      controller.commit(
        result.save,
        command: 'dialogue_choose',
        args: <String, Object?>{
          'dialogueId': view.dialogueId,
          'nodeId': view.nodeId,
          'choiceId': choiceId,
          if (useFavourites) 'useFavourites': true,
        },
      );
    }
    return result;
  }

  Future<void> _choose(String choiceId) async {
    final view = _view;
    if (view == null || _busy) return;
    _busy = true;
    try {
      final before = controller.save;
      var result = await _send(view, choiceId, useFavourites: false);
      if (!mounted) return;
      if (result.code == 'confirm_favourites') {
        if (!await _confirmFavourites(result.favourites) || !mounted) return;
        result = await _send(view, choiceId, useFavourites: true);
        if (!mounted) return;
      }
      await _settle(before, result);
    } finally {
      _releaseNextFrame();
    }
  }

  void _releaseNextFrame() {
    if (!mounted) {
      _busy = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _busy = false);
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<bool> _confirmFavourites(List<DialogueItemDelta> favourites) {
    return showDialogueFavouritesPrompt(context: context, text: _text, favourites: favourites);
  }

  Future<void> _settle(PlayerSave before, DialogueResult result) async {
    if (result.ok) {
      final notice = _text.notice(before, result);
      if (notice != null) controller.announce(notice);
      final beforeUnlocked = before.cosmetics.unlocked.toSet();
      controller.noteCosmeticUnlocks([
        for (final id in result.save.cosmetics.unlocked)
          if (!beforeUnlocked.contains(id))
            ShopCosmeticGrant(cosmeticId: id, isFirstEver: beforeUnlocked.isEmpty),
      ]);
      if (result.completed || result.view == null) {
        widget.onClose();
        return;
      }
      setState(() {
        _view = result.view;
        _error = null;
        _message = notice;
        _touched = result.stepProgress;
      });
      return;
    }
    if (result.code == 'no_room') {
      final spoken = DialogueText.spokenNpcLine(result.noRoom);
      setState(() {
        _error = null;
        if (spoken != null) _view = _withSpokenLine(_view, spoken);
      });
      await showDialogueBagFullPopup(context: context, noRoom: result.noRoom);
      return;
    }
    setState(() => _error = _text.failure(result));
  }

  static DialogueView? _withSpokenLine(DialogueView? view, String line) {
    if (view == null || view.line == line) return view;
    return DialogueView(
      dialogueId: view.dialogueId,
      nodeId: view.nodeId,
      speakerName: view.speakerName,
      npcId: view.npcId,
      line: line,
      choices: view.choices,
      finished: view.finished,
      stepProgress: view.stepProgress,
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    if (view == null) {
      return GamePanel(
        child: Column(
          mainAxisSize: widget.docked ? MainAxisSize.min : MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_error ?? _text.startFailure(null), style: const TextStyle(color: Palette.danger)),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: GameButton(label: 'Close', onPressed: widget.onClose),
            ),
          ],
        ),
      );
    }
    final shown = {for (final group in view.stepProgress) (group.questId, group.stepId)};
    final progress = [
      ...view.stepProgress,
      for (final group in _touched)
        if (!shown.contains((group.questId, group.stepId))) group,
    ];
    if (widget.docked) {
      return FennelDialoguePanel(
        view: view,
        text: _text,
        progress: progress,
        onChoose: _choose,
        onClose: widget.onClose,
        message: _message,
        error: _error,
      );
    }
    return DialogueWindow(
      view: view,
      text: _text,
      progress: progress,
      onChoose: _choose,
      onClose: widget.onClose,
      message: _message,
      error: _error,
    );
  }
}
