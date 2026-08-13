import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'format.dart';

/// Talking to somebody: their greeting, what they can teach, and their quests.
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
  /// The dialogue on screen: the opening greeting until it is answered, and
  /// afterwards whichever pitch the player asked to hear again.
  NpcGreeting? _dialogue;
  String? _error;

  GameController get controller => widget.controller;

  NpcConversation get conversation => npcConversation(controller.db, controller.save, widget.npc);

  @override
  void initState() {
    super.initState();
    _dialogue = conversation.greeting;
  }

  /// Takes the merchant's advice, if they had any left, and leaves.
  void _dismissMerchant({String? thenOpenShop}) {
    final claimed = takeMerchantTip(controller.db, controller.save, conversation.npcId);
    if (claimed != null) {
      controller.commit(claimed.save!);
      controller.announce(claimed.message!);
    }
    widget.onClose();
    if (thenOpenShop != null) widget.onOpenShop?.call(thenOpenShop);
  }

  void _accept(String questId) {
    final result = acceptQuestFromNpc(controller.db, controller.save, questId);
    if (!result.ok) {
      setState(() => _error = result.reason);
      return;
    }
    controller.commit(result.save!);
    controller.announce(result.message!);
    setState(() {
      _error = null;
      _dialogue = null;
    });
  }

  /// Accepts [quest], or hears the giver out first when they have a pitch.
  void _openQuest(NpcQuestBlock quest) {
    final line = quest.pitchLine;
    if (line == null) {
      _accept(quest.questId);
      return;
    }
    setState(() {
      _error = null;
      _dialogue = QuestPitchGreeting(
        questId: quest.questId,
        line: line,
        acceptLabel: quest.acceptLabel,
      );
    });
  }

  void _learn() {
    final result = learnMentorProjects(controller.db, controller.save, conversation.npcId);
    if (!result.ok) {
      setState(() => _error = result.reason);
      return;
    }
    controller.commit(result.save!);
    controller.announce(result.message!);
    setState(() => _error = null);
  }

  Future<void> _turnIn(NpcQuestBlock quest) async {
    final result = completeQuest(controller.db, controller.save, quest.questId);
    if (!result.ok) {
      setState(() => _error = result.reason);
      return;
    }
    controller.commit(result.save!);
    controller.announce(result.message!);
    setState(() => _error = null);
    await showQuestRewards(context, questName: result.questName!, rewards: result.rewards);
  }

  @override
  Widget build(BuildContext context) {
    final conversation = this.conversation;

    switch (_dialogue) {
      case MerchantGreeting(line: final line, detail: final detail):
        return _DialogueCard(
          name: conversation.name,
          line: line,
          detail: detail,
          actions: [
            if (conversation.shopId case final shopId?)
              OutlinedButton(
                onPressed: () => _dismissMerchant(thenOpenShop: shopId),
                child: const Text('Browse the shop'),
              ),
            FilledButton(onPressed: _dismissMerchant, child: const Text('Continue')),
          ],
        );
      case QuestPitchGreeting(questId: final questId, line: final line, acceptLabel: final label):
        return _DialogueCard(
          name: conversation.name,
          line: line,
          error: _error,
          actions: [
            OutlinedButton(
              onPressed: () => setState(() => _dialogue = null),
              child: const Text('Not now'),
            ),
            FilledButton(onPressed: () => _accept(questId), child: Text(label)),
          ],
        );
      case null:
        break;
    }

    return GamePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    if (conversation.role case final role?) MutedText(role),
                  ],
                ),
              ),
              IconButton(
                onPressed: widget.onClose,
                tooltip: 'Close',
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          Text(conversation.description),
          if (conversation.mentor case final mentor?) ...[
            const SizedBox(height: 10),
            if (mentor.known)
              MutedText(mentor.knownNote)
            else
              FilledButton(onPressed: _learn, child: Text(mentor.learnLabel)),
          ],
          if (conversation.isMerchant && conversation.shopId != null) ...[
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () {
                widget.onClose();
                widget.onOpenShop?.call(conversation.shopId!);
              },
              child: const Text('Browse the shop'),
            ),
          ],
          for (final quest in conversation.quests) ...[
            const SizedBox(height: 12),
            _QuestBlock(
              quest: quest,
              onAccept: () => _openQuest(quest),
              onTurnIn: () => _turnIn(quest),
            ),
          ],
          if (_error case final error?) ...[
            const SizedBox(height: 8),
            Text(error, style: const TextStyle(color: Palette.danger, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class _QuestBlock extends StatelessWidget {
  const _QuestBlock({required this.quest, required this.onAccept, required this.onTurnIn});

  final NpcQuestBlock quest;
  final VoidCallback onAccept;
  final VoidCallback onTurnIn;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0x66231710),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Palette.edge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(quest.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (quest.summary case final summary?) MutedText(summary),
          const SizedBox(height: 8),
          switch (quest.status) {
            'completed' => MutedText(quest.completedNote),
            'inactive' => FilledButton(onPressed: onAccept, child: Text(quest.acceptLabel)),
            _ => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final line in quest.lines)
                  MutedText(
                    'Progress: ${formatThousands(line.owned < line.required ? line.owned : line.required)}'
                    ' / ${formatThousands(line.required)} ${line.name}',
                  ),
                if (quest.goldRequired > 0)
                  MutedText(
                    'Gold: ${formatThousands(quest.goldOwned)} / '
                    '${formatThousands(quest.goldRequired)}',
                  ),
                const SizedBox(height: 6),
                FilledButton(
                  onPressed: quest.ready ? onTurnIn : null,
                  child: const Text('Turn in'),
                ),
              ],
            ),
          },
        ],
      ),
    );
  }
}

/// A greeting, over the panel it belongs to.
class _DialogueCard extends StatelessWidget {
  const _DialogueCard({
    required this.name,
    required this.line,
    required this.actions,
    this.detail,
    this.error,
  });

  final String name;
  final String line;

  /// What listening is worth, when the greeting is an offer.
  final String? detail;
  final String? error;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return GamePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(line, style: const TextStyle(fontSize: 15)),
          if (detail case final detail?) ...[const SizedBox(height: 4), MutedText(detail)],
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
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: GamePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const MutedText('Quest complete'),
              Text(questName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Collect'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
