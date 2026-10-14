import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'bribe_popup.dart';
import 'dialogue_text.dart';
import 'dialogue_window.dart';
import 'format.dart';
import 'game_popup.dart';
import 'social_bits.dart';

/// Sends one quest-panel turn-in or hand-in. [useFavourites] is this request only.
typedef NpcQuestPanelRequest = Future<QuestCompletion> Function({
  required String questId,
  required bool useFavourites,
});

/// The sheet's Priority from which a quest-gated dialogue opens the panel.
///
/// The Fennel and King rows sit at 10 and 11; the ungated greetings (Citadel
/// Guide, Quartermaster Brenna) carry no Priority and stay behind
/// "Something else…".
const int questDialoguePriority = 10;

/// The first available dialogue whose Condition names a quest
/// (`quest_active`, `quest_step`, `quest_done`) at [questDialoguePriority] or
/// above, in [dialoguesForNpc] order. Null leaves the old quest panel in charge.
String? questDialogueForNpc(GameDatabase db, PlayerSave save, String npcId) {
  for (final dialogueId in dialoguesForNpc(db, save, npcId)) {
    for (final row in db.dialogues) {
      if (row.dialogueId != dialogueId) continue;
      if ((row.priority ?? 0) < questDialoguePriority) break;
      final gated = parseDialogueTokens(row.condition)
          .any((token) => token.name.startsWith('quest_'));
      if (gated) return dialogueId;
      break;
    }
  }
  return null;
}

/// Talking to somebody: Talk opens the dialogue box immediately.
///
/// Every line and label comes from [npcConversation], so this widget never
/// decides who says what — it only decides where the words go.
class NpcPanel extends StatefulWidget {
  const NpcPanel({
    super.key,
    required this.controller,
    required this.npc,
    required this.onClose,
    this.onOpenShop,
    this.onOpenTanner,
    this.turnInRequest,
  });

  final GameController controller;
  final NpcRow npc;
  final VoidCallback onClose;

  /// Opens the counter a merchant keeps, when the location has one.
  final void Function(String shopId)? onOpenShop;

  /// Opens the hide-to-leather counter a tanner keeps.
  final VoidCallback? onOpenTanner;

  /// Defaults to the local engine plus a `quest_complete` commit.
  final NpcQuestPanelRequest? turnInRequest;

  @override
  State<NpcPanel> createState() => _NpcPanelState();
}

class _NpcPanelState extends State<NpcPanel> {
  String? _whereaboutsLine;
  String? _mentorLine;
  String? _error;
  String? _selectedRaceId;
  bool _pickingRace = false;
  String? _standaloneDialogueId;

  /// Set once a standalone dialogue has been closed this visit, so the panel
  /// underneath can be reached instead of the quest dialogue reopening.
  bool _questDialogueDismissed = false;

  /// True until a seed-triggered quest start has been committed, so the first
  /// dialogue is chosen from the save the server will also hold.
  bool _seedStartPending = false;

  /// One turn-in in flight at a time, held until the next frame so a double tap
  /// on the same button is dropped.
  bool _busy = false;

  late final DialogueText _text = DialogueText(controller.db);

  GameController get controller => widget.controller;

  NpcConversation get conversation =>
      npcConversation(controller.db, controller.save, widget.npc, controller.session.clock());

  @override
  void initState() {
    super.initState();
    if (identical(applyQuestAutoStartOnSeed(controller.db, controller.save), controller.save)) {
      return;
    }
    // [npcConversation] only starts the quest on a copy. Committing here is
    // what lets the dialogue gated on that quest step open, and the commit
    // waits a frame because the panel is built inside the controller's
    // listener.
    _seedStartPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _commitSeedStart());
  }

  void _commitSeedStart() {
    if (!mounted) return;
    final started = applyQuestAutoStartOnSeed(controller.db, controller.save);
    if (!identical(started, controller.save)) {
      controller.commit(started, command: 'quest_autostart_seed');
    }
    setState(() => _seedStartPending = false);
  }

  void _close() {
    widget.onClose();
  }

  /// Takes the merchant's advice, if they had any left, and leaves.
  void _dismissMerchant({String? thenOpenShop}) {
    final claimed = takeMerchantTip(controller.db, controller.save, conversation.npcId);
    if (claimed != null) {
      controller.commit(
        claimed.save!,
        command: 'merchant_tip_claim',
        args: <String, Object?>{'npcId': conversation.npcId},
      );
      controller.announce(claimed.message!);
    }
    if (thenOpenShop != null) {
      widget.onClose();
      widget.onOpenShop?.call(thenOpenShop);
      return;
    }
    _close();
  }

  void _accept(String questId) {
    final result = acceptQuestFromNpc(controller.db, controller.save, questId);
    if (!result.ok) {
      setState(() => _error = result.reason);
      return;
    }
    controller.commit(
      result.save!,
      command: 'quest_accept',
      args: <String, Object?>{'questId': questId},
    );
    controller.announce(result.message!);
    setState(() => _error = null);
  }

  void _donate(String questId) {
    final result = donateForQuestFromNpc(controller.db, controller.save, questId);
    if (!result.ok) {
      setState(() => _error = result.reason);
      return;
    }
    controller.commit(
      result.save!,
      command: 'quest_donate',
      args: <String, Object?>{'questId': questId},
    );
    controller.announce(result.message!);
    setState(() => _error = null);
  }

  void _learn() {
    final mentor = conversation.mentor;
    final line = mentor?.line;
    if (line != null && mentor?.known != true && _mentorLine == null) {
      setState(() {
        _error = null;
        _mentorLine = line;
      });
      return;
    }
    _commitLearn();
  }

  void _commitLearn() {
    final result = learnMentorProjects(controller.db, controller.save, conversation.npcId);
    if (!result.ok) {
      setState(() => _error = result.reason);
      return;
    }
    controller.commit(
      result.save!,
      command: 'quest_learn',
      args: <String, Object?>{'npcId': conversation.npcId},
    );
    controller.announce(result.message!);
    setState(() {
      _error = null;
      _mentorLine = null;
    });
  }

  void _commitTalk() {
    final beforeBooks = controller.save.unlockedBookIds.toSet();
    final booksWereEmpty = beforeBooks.isEmpty;
    final result = talkWithQuestNpc(controller.db, controller.save, conversation.npcId);
    if (!result.ok) {
      setState(() => _error = result.reason);
      return;
    }
    controller.commit(
      result.save!,
      command: 'quest_talk',
      args: <String, Object?>{'npcId': conversation.npcId},
    );
    _announceIfPresent(result.message);
    final granted = result.save!.unlockedBookIds
        .where((id) => !beforeBooks.contains(id))
        .map((id) => QuestBookGrant(bookId: id, isFirstEver: booksWereEmpty))
        .toList();
    controller.noteBookUnlocks(granted);
    setState(() => _error = null);
  }

  Future<void> _bribe(NpcQuestBlock quest) async {
    if (_busy) return;
    final blocked = bribeForQuest(controller.db, controller.save, quest.questId);
    if (!blocked.ok && blocked.code == 'no_room') {
      if (!mounted) return;
      setState(() => _error = null);
      await showDialogueBagFullPopup(context: context, noRoom: blocked.noRoom);
      return;
    }
    if (!mounted) return;
    final paid = await showBribeConfirmPopup(
      context: context,
      db: controller.db,
      save: controller.save,
      questId: quest.questId,
    );
    if (!paid || !mounted) return;
    if (_busy) return;
    _busy = true;
    try {
      await _payBribe(quest);
    } finally {
      _releaseNextFrame();
    }
  }

  bool _stillCanBribe(String questId) {
    return conversation.quests.any((quest) => quest.questId == questId && quest.canBribe);
  }

  /// Hosted play waits for the server and takes the save it answers with, so a
  /// `not_enough_gold` refusal writes nothing back and a paid bribe is never
  /// worked out a second time here. Offline applies locally, same as today's
  /// synced command.
  Future<void> _payBribe(NpcQuestBlock quest) async {
    if (!_stillCanBribe(quest.questId)) return;
    final args = <String, Object?>{'questId': quest.questId};
    final hosted = controller.hostedPlay?.call() == true ? controller.submitHostedCommand : null;
    if (hosted != null) {
      final receipt = await hosted('quest_bribe', args);
      if (!mounted) return;
      if (!receipt.ok) {
        if (receipt.code == 'no_room' || receipt.noRoom != null) {
          setState(() => _error = null);
          await showDialogueBagFullPopup(context: context, noRoom: receipt.noRoom);
          return;
        }
        setState(() => _error = receipt.reason);
        return;
      }
      // The sync layer skips adopting a result while other commands are still
      // queued behind it, so apply the server's copy here either way.
      if (receipt.save case final server?) {
        controller.adoptHostedSave(server, command: 'quest_bribe');
      }
      controller.announce('The purse changes hands.');
      setState(() => _error = null);
      return;
    }
    final result = bribeForQuest(controller.db, controller.save, quest.questId);
    if (!result.ok) {
      if (result.code == 'no_room') {
        if (!mounted) return;
        setState(() => _error = null);
        await showDialogueBagFullPopup(context: context, noRoom: result.noRoom);
        return;
      }
      if (mounted) setState(() => _error = result.reason);
      return;
    }
    controller.commit(result.save!, command: 'quest_bribe', args: args);
    controller.announce(result.message!);
    if (!mounted) return;
    setState(() => _error = null);
  }

  void _chooseCombat(NpcQuestBlock quest) {
    final result = controller.chooseQuestCombat(quest.questId);
    if (!result.ok) {
      setState(() => _error = result.reason);
      return;
    }
    controller.commit(
      result.save!,
      command: 'choose_quest_combat',
      args: <String, Object?>{'questId': quest.questId},
    );
    controller.announce(result.message!);
    setState(() => _error = null);
    if (result.startedActivity) widget.onClose();
  }

  Future<QuestCompletion> _sendTurnIn(String questId, {required bool useFavourites}) async {
    final request = widget.turnInRequest;
    if (request != null) return request(questId: questId, useFavourites: useFavourites);
    final result = completeQuest(
      controller.db,
      controller.save,
      questId,
      useFavourites: useFavourites,
    );
    if (result.ok) {
      controller.commit(
        result.save!,
        command: 'quest_complete',
        args: <String, Object?>{'questId': questId, if (useFavourites) 'useFavourites': true},
      );
    }
    return result;
  }

  void _releaseNextFrame() {
    if (!mounted) {
      _busy = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _busy = false);
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _turnIn(NpcQuestBlock quest) async {
    if (_busy) return;
    _busy = true;
    try {
      await _completeTurnIn(quest);
    } finally {
      _releaseNextFrame();
    }
  }

  Future<void> _completeTurnIn(NpcQuestBlock quest) async {
    final beforeUnlocked = controller.save.cosmetics.unlocked.toSet();
    final wasEmpty = beforeUnlocked.isEmpty;
    var result = await _sendTurnIn(quest.questId, useFavourites: false);
    if (!mounted) return;
    if (result.code == 'confirm_favourites') {
      final yes = await showDialogueFavouritesPrompt(
        context: context,
        text: _text,
        favourites: result.favourites,
      );
      if (!yes || !mounted) return;
      result = await _sendTurnIn(quest.questId, useFavourites: true);
      if (!mounted) return;
    }
    if (!result.ok) {
      if (result.code == 'no_room') {
        setState(() => _error = null);
        await showDialogueBagFullPopup(context: context, noRoom: result.noRoom);
        return;
      }
      setState(() => _error = result.reason);
      return;
    }
    final spoken = questTalkLine(controller.db, quest.questId, conversation.npcId, result.save!);
    if (spoken == null) _announceIfPresent(result.message);
    final bundle = result.rewardBundle;
    if (bundle != null &&
        (bundle.goldGained > 0 || bundle.xpRewards.isNotEmpty || bundle.loot.isNotEmpty)) {
      controller.noteReward(bundle);
    }
    setState(() => _error = null);
    final granted = result.save!.cosmetics.unlocked
        .where((id) => !beforeUnlocked.contains(id))
        .map((id) => ShopCosmeticGrant(cosmeticId: id, isFirstEver: wasEmpty))
        .toList();
    controller.noteCosmeticUnlocks(granted);
    controller.noteBookUnlocks(result.booksGranted);
    await showQuestRewards(
      context,
      questName: result.questName!,
      rewards: result.rewards,
      spokenLine: spoken,
      thankYou: spoken == null,
    );
    if (!mounted) return;
    if (result.pendingSkillXp > 0) {
      await showSkillXpPicker(context, controller: controller, amount: result.pendingSkillXp);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_seedStartPending) return const SizedBox.shrink();
    final conversation = this.conversation;

    if (_standaloneDialogueId case final dialogueId?) {
      return _standaloneHost(dialogueId);
    }

    if (_whereaboutsLine case final whereaboutsLine?) {
      return _playerDialogue(
        name: conversation.name,
        line: whereaboutsLine,
        actions: [
          GameButton(label: 'Continue', onPressed: () => setState(() => _whereaboutsLine = null)),
        ],
      );
    }

    if (_mentorLine case final mentorLine?) {
      return _playerDialogue(
        name: conversation.name,
        line: mentorLine,
        actions: [GameButton(label: 'Continue', onPressed: _commitLearn)],
      );
    }

    return _openingDialogue(conversation);
  }

  /// Closing any standalone dialogue drops back to the panel underneath; the
  /// quest dialogue does not reopen until the NPC is tapped again.
  Widget _standaloneHost(String dialogueId) {
    return StandaloneDialogueHost(
      key: ValueKey<String>(dialogueId),
      controller: controller,
      dialogueId: dialogueId,
      onClose: () => setState(() {
        _standaloneDialogueId = null;
        _questDialogueDismissed = true;
      }),
    );
  }

  List<Widget> _withStandalone(List<Widget> actions) {
    final ids = dialoguesForNpc(controller.db, controller.save, widget.npc.npcId);
    if (ids.isEmpty) return actions;
    return [
      GameButton(
        label: 'Something else…',
        tone: GameButtonTone.secondary,
        compact: true,
        onPressed: () => setState(() => _standaloneDialogueId = ids.first),
      ),
      ...actions,
    ];
  }

  Widget _openingDialogue(NpcConversation conversation) {
    if (!_questDialogueDismissed) {
      final questDialogueId = questDialogueForNpc(controller.db, controller.save, widget.npc.npcId);
      if (questDialogueId != null) {
        // Held until closed, so a choice that moves the quest on does not swap
        // the conversation out from under its own reply.
        _standaloneDialogueId = questDialogueId;
        return _standaloneHost(questDialogueId);
      }
    }

    final talkQuest = conversation.quests.where((quest) => quest.canTalk).firstOrNull;
    if (talkQuest != null) {
      return _playerDialogue(
        name: conversation.name,
        line: _spokenLine(conversation, talkQuest),
        error: _error,
        actions: _withStandalone([GameButton(label: 'Continue', onPressed: _commitTalk)]),
      );
    }

    final donateQuest = conversation.quests.where((quest) => quest.canDonate).firstOrNull;
    if (donateQuest != null) {
      return _playerDialogue(
        name: conversation.name,
        line: donateQuest.pitchLine ?? donateQuest.summary ?? conversation.description,
        journal: _requirementJournal(donateQuest.questId),
        error: _error,
        actions: [
          GameButton(
            label: 'Not now',
            tone: GameButtonTone.secondary,
            compact: true,
            onPressed: _close,
          ),
          GameButton(label: donateQuest.donateLabel, onPressed: () => _donate(donateQuest.questId)),
        ],
      );
    }

    final acceptQuest = conversation.quests.where((quest) => quest.canAccept).firstOrNull;
    if (acceptQuest != null) {
      return _playerDialogue(
        name: conversation.name,
        line: acceptQuest.pitchLine ?? acceptQuest.summary ?? conversation.description,
        journal: _requirementJournal(acceptQuest.questId),
        error: _error,
        actions: [
          GameButton(
            label: 'Not now',
            tone: GameButtonTone.secondary,
            compact: true,
            onPressed: _close,
          ),
          GameButton(label: acceptQuest.acceptLabel, onPressed: () => _accept(acceptQuest.questId)),
        ],
      );
    }

    final turnInQuest = conversation.quests.where((quest) => quest.canTurnIn).firstOrNull;
    if (turnInQuest != null) {
      return _playerDialogue(
        name: conversation.name,
        line: _spokenLine(conversation, turnInQuest),
        error: _error,
        actions: _withStandalone([
          if (turnInQuest.canBribe)
            GameButton(
              label: turnInQuest.bribeLabel,
              tone: GameButtonTone.secondary,
              compact: true,
              onPressed: () => _bribe(turnInQuest),
            ),
          if (turnInQuest.canChooseCombat)
            GameButton(
              label: turnInQuest.combatLabel,
              tone: GameButtonTone.secondary,
              compact: true,
              onPressed: () => _chooseCombat(turnInQuest),
            ),
          if (turnInQuest.ready)
            GameButton(label: 'Turn in', onPressed: () => _turnIn(turnInQuest))
          else
            GameButton(label: 'Done', onPressed: _close),
        ]),
      );
    }

    final choiceQuest = conversation.quests
        .where((quest) => quest.canBribe || quest.canChooseCombat)
        .firstOrNull;
    if (choiceQuest != null) {
      return _playerDialogue(
        name: conversation.name,
        line: _spokenLine(conversation, choiceQuest),
        error: _error,
        actions: _withStandalone([
          if (choiceQuest.canBribe)
            GameButton(
              label: choiceQuest.bribeLabel,
              tone: GameButtonTone.secondary,
              compact: true,
              onPressed: () => _bribe(choiceQuest),
            ),
          if (choiceQuest.canChooseCombat)
            GameButton(
              label: choiceQuest.combatLabel,
              tone: GameButtonTone.secondary,
              compact: true,
              onPressed: () => _chooseCombat(choiceQuest),
            ),
          GameButton(label: 'Done', onPressed: _close),
        ]),
      );
    }

    final activeQuest = conversation.quests.where((quest) => quest.status == 'active').firstOrNull;
    if (activeQuest != null) {
      return _playerDialogue(
        name: conversation.name,
        line: _spokenLine(conversation, activeQuest),
        error: _error,
        actions: _withStandalone([GameButton(label: 'Done', onPressed: _close)]),
      );
    }

    if (conversation.isMerchant) {
      final greeting = conversation.greeting;
      final line = greeting is MerchantGreeting ? greeting.line : conversation.description;
      return _playerDialogue(
        name: conversation.name,
        line: line,
        detail: greeting is MerchantGreeting ? greeting.detail : null,
        error: _error,
        actions: [
          if (conversation.shopId case final shopId?)
            GameButton(
              label: 'Browse the shop',
              tone: GameButtonTone.secondary,
              compact: true,
              onPressed: () => _dismissMerchant(thenOpenShop: shopId),
            ),
          if (conversation.whereabouts case final whereabouts?)
            GameButton(
              label: whereabouts.label,
              tone: GameButtonTone.secondary,
              compact: true,
              onPressed: () => setState(() => _whereaboutsLine = whereabouts.line),
            ),
          ..._withStandalone([GameButton(label: 'Done', onPressed: _close)]),
        ],
      );
    }

    if (conversation.mentor case final mentor?) {
      return _playerDialogue(
        name: conversation.name,
        line: mentor.known ? mentor.knownNote : conversation.description,
        error: _error,
        actions: _withStandalone([
          if (conversation.whereabouts case final whereabouts?)
            GameButton(
              label: whereabouts.label,
              tone: GameButtonTone.secondary,
              compact: true,
              onPressed: () => setState(() => _whereaboutsLine = whereabouts.line),
            ),
          if (!mentor.known) GameButton(label: mentor.learnLabel, onPressed: _learn),
          GameButton(label: 'Done', onPressed: _close),
        ]),
      );
    }

    if (conversation.whereabouts case final whereabouts?) {
      return _playerDialogue(
        name: conversation.name,
        line: conversation.description,
        error: _error,
        actions: _withStandalone([
          GameButton(
            label: whereabouts.label,
            tone: GameButtonTone.secondary,
            compact: true,
            onPressed: () => setState(() => _whereaboutsLine = whereabouts.line),
          ),
          GameButton(label: 'Done', onPressed: _close),
        ]),
      );
    }

    if (conversation.tanner != null) {
      return _playerDialogue(
        name: conversation.name,
        line: conversation.description,
        error: _error,
        actions: _withStandalone([
          GameButton(
            label: 'Done',
            tone: GameButtonTone.secondary,
            compact: true,
            onPressed: _close,
          ),
          GameButton(
            label: 'Tan hides',
            onPressed: () {
              widget.onClose();
              widget.onOpenTanner?.call();
            },
          ),
        ]),
      );
    }

    if (conversation.raceChange case final raceChange?) {
      return _raceChangeDialogue(conversation, raceChange);
    }

    final completed = conversation.quests.where((quest) => quest.status == 'completed').firstOrNull;
    return _playerDialogue(
      name: conversation.name,
      line: completed?.completedNote ?? conversation.description,
      error: _error,
      actions: _withStandalone([GameButton(label: 'Done', onPressed: _close)]),
    );
  }

  Widget _raceChangeDialogue(NpcConversation conversation, RaceChangeOffer raceChange) {
    final selected = raceChange.options
        .where((option) => option.raceId == _selectedRaceId)
        .firstOrNull;

    if (_pickingRace && selected != null) {
      return _playerDialogue(
        name: conversation.name,
        line: '${selected.name}. ${selected.summary}',
        detail: raceChange.warning,
        error: _error,
        journal: [
          for (final line in selected.lines)
            QuestJournalStep(
              key: line.itemId ?? 'gold',
              label: '${line.name} ${line.owned} / ${line.required}',
              state: line.owned >= line.required ? 'done' : 'current',
            ),
        ],
        actions: [
          GameButton(
            label: 'Back',
            tone: GameButtonTone.secondary,
            compact: true,
            onPressed: () => setState(() {
              _selectedRaceId = null;
              _error = null;
            }),
          ),
          GameButton(
            label: selected.current
                ? 'Already this race'
                : selected.canAfford && raceChange.ready
                ? 'Change to ${selected.name}'
                : 'Need more',
            onPressed: selected.current || !selected.canAfford || !raceChange.ready
                ? null
                : () {
                    final reason = controller.changeRaceWithVesper(selected.raceId);
                    if (reason != null) {
                      setState(() => _error = reason);
                      return;
                    }
                    setState(() {
                      _error = null;
                      _pickingRace = false;
                      _selectedRaceId = null;
                    });
                  },
          ),
        ],
      );
    }

    if (_pickingRace) {
      return _playerDialogue(
        name: conversation.name,
        line: raceChange.prompt,
        detail: raceChange.warning,
        error: _error,
        actions: [
          GameButton(
            label: 'Back',
            tone: GameButtonTone.secondary,
            compact: true,
            onPressed: () => setState(() {
              _pickingRace = false;
              _error = null;
            }),
          ),
          for (final option in raceChange.options.where((row) => !row.current))
            GameButton(
              label: option.name,
              tone: GameButtonTone.secondary,
              compact: true,
              onPressed: () => setState(() {
                _selectedRaceId = option.raceId;
                _error = null;
              }),
            ),
        ],
      );
    }

    final line = raceChange.ready
        ? raceChange.prompt
        : (raceChange.cooldownLabel ?? conversation.description);
    return _playerDialogue(
      name: conversation.name,
      line: line,
      detail: raceChange.ready ? raceChange.warning : null,
      error: _error,
      actions: [
        GameButton(label: 'Done', tone: GameButtonTone.secondary, compact: true, onPressed: _close),
        if (raceChange.ready)
          GameButton(label: 'Change race', onPressed: () => setState(() => _pickingRace = true)),
      ],
    );
  }

  List<QuestJournalStep> _requirementJournal(String questId) {
    final quest = getQuest(controller.db, questId);
    if (quest == null) return const <QuestJournalStep>[];
    return questRequirementJournal(controller.db, controller.save, quest);
  }

  void _announceIfPresent(String? message) {
    if (message != null && message.trim().isNotEmpty) {
      controller.announce(message);
    }
  }

  String _spokenLine(NpcConversation conversation, NpcQuestBlock quest) {
    final talk = quest.talkLine;
    if (talk != null && talk.trim().isNotEmpty) return talk;
    if (quest.idlePrompt.trim().isNotEmpty) return quest.idlePrompt;
    return conversation.description;
  }

  Widget _playerDialogue({
    required String name,
    required String line,
    String? detail,
    String? error,
    List<QuestJournalStep> journal = const [],
    Widget? extra,
    required List<Widget> actions,
  }) {
    return _DialogueCard(
      name: name,
      line: line,
      detail: detail,
      error: error,
      journal: journal,
      extra: extra,
      actions: actions,
      npcId: widget.npc.npcId,
    );
  }
}

/// A greeting, over the panel it belongs to.
class _DialogueCard extends StatelessWidget {
  const _DialogueCard({
    required this.name,
    required this.line,
    required this.actions,
    required this.npcId,
    this.detail,
    this.error,
    this.journal = const [],
    this.extra,
  });

  final String name;
  final String line;

  /// What listening is worth, when the greeting is an offer.
  final String? detail;
  final String? error;
  final List<QuestJournalStep> journal;
  final Widget? extra;
  final List<Widget> actions;
  final String npcId;

  @override
  Widget build(BuildContext context) {
    return GamePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IgnorePointer(child: NpcPortrait(npcId: npcId, size: 68)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontSize: GameFont.l, fontWeight: FontWeight.w400),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(line, style: const TextStyle(fontSize: GameFont.m)),
          if (detail case final detail?) ...[const SizedBox(height: 4), MutedText(detail)],
          if (journal.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final step in journal) _QuestMenuLine(step: step),
          ],
          if (extra case final extra?) ...[const SizedBox(height: 8), extra],
          if (error case final error?) ...[
            const SizedBox(height: 6),
            Text(
              error,
              style: const TextStyle(color: Palette.danger, fontSize: GameFont.s),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: actions),
        ],
      ),
    );
  }
}

class _QuestMenuLine extends StatelessWidget {
  const _QuestMenuLine({required this.step});

  final QuestJournalStep step;

  @override
  Widget build(BuildContext context) {
    if (step.state == 'header') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4, top: 2),
        child: Text(step.label, style: const TextStyle(fontWeight: FontWeight.w600)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            step.state == 'done' ? '✓' : '•',
            style: TextStyle(color: step.state == 'done' ? Palette.softGreen : Palette.gold),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              step.label,
              style: TextStyle(color: step.state == 'done' ? Palette.muted : Palette.parchmentText),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows what a turn-in paid out.
Future<void> showQuestRewards(
  BuildContext context, {
  required String questName,
  required List<String> rewards,
  String? spokenLine,
  bool thankYou = true,
}) {
  return showGamePopup<void>(
    context: context,
    builder: (context) => GamePopupCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (thankYou) const MutedText('Thank you'),
          Text(
            questName,
            style: const TextStyle(fontSize: gamePopupTitleSize, fontWeight: FontWeight.w400),
          ),
          if (spokenLine case final spoken?) ...[
            const SizedBox(height: 8),
            Text(spoken, style: const TextStyle(fontSize: GameFont.m)),
          ],
          const SizedBox(height: 8),
          if (rewards.isEmpty && questName != botanyAllDiedTitle)
            const MutedText('No rewards.')
          else
            for (final reward in rewards)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('· $reward', style: const TextStyle(color: Palette.gold)),
              ),
          const SizedBox(height: 10),
          GameButton(label: 'Collect', onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    ),
  );
}

/// Lets the player pick which non-combat skill receives quest XP.
Future<void> showSkillXpPicker(
  BuildContext context, {
  required GameController controller,
  required num amount,
}) {
  final skills = selectableNonCombatSkills(controller.db);
  return showGamePopup<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => GamePopupCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const MutedText('Choose a skill'),
          Text(
            '${formatThousands(amount)} XP',
            style: const TextStyle(fontSize: gamePopupTitleSize, fontWeight: FontWeight.w400),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final skill in skills)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: GameButton(
                      label: skill.displayName,
                      tone: GameButtonTone.secondary,
                      onPressed: () {
                        final result = assignQuestSkillXp(
                          controller.db,
                          controller.save,
                          skill.skillId,
                          amount,
                        );
                        if (result.ok) {
                          controller.commit(
                            result.save!,
                            command: 'quest_assign_skill_xp',
                            args: <String, Object?>{'skillId': skill.skillId, 'amount': amount},
                          );
                          controller.announce(result.message!);
                        } else {
                          controller.report(result.reason);
                        }
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
