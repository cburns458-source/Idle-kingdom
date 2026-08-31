import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'game_popup.dart';
import 'social_bits.dart';

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
  });

  final GameController controller;
  final NpcRow npc;
  final VoidCallback onClose;

  /// Opens the counter a merchant keeps, when the location has one.
  final void Function(String shopId)? onOpenShop;

  @override
  State<NpcPanel> createState() => _NpcPanelState();
}

class _NpcPanelState extends State<NpcPanel> {
  String? _whereaboutsLine;
  String? _mentorLine;
  String? _error;
  String? _selectedRaceId;
  bool _pickingRace = false;

  GameController get controller => widget.controller;

  NpcConversation get conversation =>
      npcConversation(controller.db, controller.save, widget.npc, controller.session.clock());

  void _close() {
    widget.onClose();
  }

  /// Takes the merchant's advice, if they had any left, and leaves.
  void _dismissMerchant({String? thenOpenShop}) {
    final claimed = takeMerchantTip(controller.db, controller.save, conversation.npcId);
    if (claimed != null) {
      controller.commit(claimed.save!);
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
    controller.commit(result.save!);
    controller.announce(result.message!);
    setState(() => _error = null);
  }

  void _donate(String questId) {
    final result = donateForQuestFromNpc(controller.db, controller.save, questId);
    if (!result.ok) {
      setState(() => _error = result.reason);
      return;
    }
    controller.commit(result.save!);
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
    controller.commit(result.save!);
    controller.announce(result.message!);
    setState(() {
      _error = null;
      _mentorLine = null;
    });
  }

  void _commitTalk() {
    final result = talkWithQuestNpc(controller.db, controller.save, conversation.npcId);
    if (!result.ok) {
      setState(() => _error = result.reason);
      return;
    }
    controller.commit(result.save!);
    controller.announce(result.message!);
    setState(() => _error = null);
  }

  void _bribe(NpcQuestBlock quest) {
    final result = bribeForQuest(controller.db, controller.save, quest.questId);
    if (!result.ok) {
      setState(() => _error = result.reason);
      return;
    }
    controller.commit(result.save!);
    controller.announce(result.message!);
    setState(() => _error = null);
  }

  void _chooseCombat(NpcQuestBlock quest) {
    final result = controller.chooseQuestCombat(quest.questId);
    if (!result.ok) {
      setState(() => _error = result.reason);
      return;
    }
    controller.commit(result.save!);
    controller.announce(result.message!);
    setState(() => _error = null);
    if (result.startedActivity) widget.onClose();
  }

  Future<void> _turnIn(NpcQuestBlock quest) async {
    final beforeUnlocked = controller.save.cosmetics.unlocked.toSet();
    final wasEmpty = beforeUnlocked.isEmpty;
    final result = completeQuest(controller.db, controller.save, quest.questId);
    if (!result.ok) {
      setState(() => _error = result.reason);
      return;
    }
    controller.commit(result.save!);
    controller.announce(result.message!);
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
    await showQuestRewards(context, questName: result.questName!, rewards: result.rewards);
    if (!mounted) return;
    if (result.pendingSkillXp > 0) {
      await showSkillXpPicker(context, controller: controller, amount: result.pendingSkillXp);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conversation = this.conversation;

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

  Widget _openingDialogue(NpcConversation conversation) {
    final talkQuest = conversation.quests.where((quest) => quest.canTalk).firstOrNull;
    if (talkQuest != null) {
      return _playerDialogue(
        name: conversation.name,
        line: talkQuest.talkLine ?? talkQuest.idlePrompt,
        progress: talkQuest.progressLines,
        error: _error,
        actions: [GameButton(label: 'Continue', onPressed: _commitTalk)],
      );
    }

    final donateQuest = conversation.quests.where((quest) => quest.canDonate).firstOrNull;
    if (donateQuest != null) {
      return _playerDialogue(
        name: conversation.name,
        line: donateQuest.pitchLine ?? donateQuest.summary ?? conversation.description,
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
        line: turnInQuest.talkLine ?? turnInQuest.idlePrompt,
        progress: turnInQuest.progressLines,
        error: _error,
        actions: [
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
        ],
      );
    }

    final choiceQuest = conversation.quests
        .where((quest) => quest.canBribe || quest.canChooseCombat)
        .firstOrNull;
    if (choiceQuest != null) {
      return _playerDialogue(
        name: conversation.name,
        line: choiceQuest.talkLine ?? choiceQuest.idlePrompt,
        progress: choiceQuest.progressLines,
        error: _error,
        actions: [
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
        ],
      );
    }

    final activeQuest = conversation.quests.where((quest) => quest.status == 'active').firstOrNull;
    if (activeQuest != null) {
      return _playerDialogue(
        name: conversation.name,
        line: activeQuest.idlePrompt,
        progress: activeQuest.progressLines,
        error: _error,
        actions: [GameButton(label: 'Done', onPressed: _close)],
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
          GameButton(label: 'Done', onPressed: _close),
        ],
      );
    }

    if (conversation.mentor case final mentor?) {
      return _playerDialogue(
        name: conversation.name,
        line: mentor.known ? mentor.knownNote : conversation.description,
        error: _error,
        actions: [
          if (conversation.whereabouts case final whereabouts?)
            GameButton(
              label: whereabouts.label,
              tone: GameButtonTone.secondary,
              compact: true,
              onPressed: () => setState(() => _whereaboutsLine = whereabouts.line),
            ),
          if (!mentor.known) GameButton(label: mentor.learnLabel, onPressed: _learn),
          GameButton(label: 'Done', onPressed: _close),
        ],
      );
    }

    if (conversation.whereabouts case final whereabouts?) {
      return _playerDialogue(
        name: conversation.name,
        line: conversation.description,
        error: _error,
        actions: [
          GameButton(
            label: whereabouts.label,
            tone: GameButtonTone.secondary,
            compact: true,
            onPressed: () => setState(() => _whereaboutsLine = whereabouts.line),
          ),
          GameButton(label: 'Done', onPressed: _close),
        ],
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
      actions: [GameButton(label: 'Done', onPressed: _close)],
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
        progress: [
          for (final line in selected.lines)
            QuestProgressLine(
              key: line.itemId ?? 'gold',
              label: line.name,
              current: line.owned,
              required: line.required,
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

  Widget _playerDialogue({
    required String name,
    required String line,
    String? detail,
    String? error,
    List<QuestProgressLine> progress = const [],
    required List<Widget> actions,
  }) {
    return _DialogueCard(
      name: name,
      line: line,
      detail: detail,
      error: error,
      progress: progress,
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
    this.progress = const [],
  });

  final String name;
  final String line;

  /// What listening is worth, when the greeting is an offer.
  final String? detail;
  final String? error;
  final List<QuestProgressLine> progress;
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
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(line, style: const TextStyle(fontSize: 15)),
          if (detail case final detail?) ...[const SizedBox(height: 4), MutedText(detail)],
          if (progress.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final line in progress)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.current >= line.required ? '✓' : '•',
                      style: TextStyle(
                        color: line.current >= line.required ? Palette.softGreen : Palette.gold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        line.caption,
                        style: TextStyle(
                          color: line.current >= line.required
                              ? Palette.muted
                              : Palette.parchmentText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (error case final error?) ...[
            const SizedBox(height: 6),
            Text(error, style: const TextStyle(color: Palette.danger, fontSize: 12)),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: actions),
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
}) {
  return showGamePopup<void>(
    context: context,
    builder: (context) => GamePopupCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const MutedText('Thank you'),
          Text(questName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400)),
          if (spokenLine case final spoken?) ...[
            const SizedBox(height: 8),
            Text(spoken, style: const TextStyle(fontSize: 15)),
          ],
          const SizedBox(height: 8),
          if (rewards.isEmpty)
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
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w400),
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
                          controller.commit(result.save!);
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
