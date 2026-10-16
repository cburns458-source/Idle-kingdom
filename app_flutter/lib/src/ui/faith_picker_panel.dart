import 'package:flutter/material.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../theme.dart';
import 'floating_slot.dart';
import 'item_icon.dart';

/// Temple overlay: names first, then one faith's page.
class FaithPickerPanel extends StatefulWidget {
  const FaithPickerPanel({super.key, required this.controller, this.onClose});

  final GameController controller;
  final VoidCallback? onClose;

  @override
  State<FaithPickerPanel> createState() => _FaithPickerPanelState();
}

class _FaithPickerPanelState extends State<FaithPickerPanel> {
  String? _pendingId;
  String? _error;
  bool _busy = false;

  GameController get controller => widget.controller;
  GameDatabase get db => controller.db;
  PlayerSave get save => controller.save;

  num get _nowMs => controller.session.clock();

  num get _cost => religionChangeGoldCost(db, save);

  String? get _cooldown {
    final readyAt = religionChangeReadyAt(db, save);
    if (readyAt == null || _nowMs >= readyAt) return null;
    return formatDurationRemaining(readyAt - _nowMs);
  }

  bool get _cooldownBlocks => _cooldown != null;

  Future<void> _choose() async {
    final religionId = _pendingId;
    if (religionId == null || _busy) return;
    if (_cooldownBlocks || save.gold < _cost || save.religionId == religionId) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final reason = await controller.chooseReligionAtTemple(religionId);
    if (!mounted) return;
    if (reason != null) {
      setState(() {
        _busy = false;
        _error = reason;
      });
      return;
    }
    widget.onClose?.call();
  }

  void _openFaith(String religionId) {
    setState(() {
      _pendingId = religionId;
      _error = null;
    });
  }

  void _backToList() {
    setState(() {
      _pendingId = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final faiths = religions(db);
        final pending = religionById(db, _pendingId);
        return SizedBox.expand(
          child: GamePanel(
            framed: true,
            child: pending == null
                ? _FaithList(
                    db: db,
                    faiths: faiths,
                    currentId: save.religionId,
                    onOpen: _openFaith,
                    onClose: widget.onClose,
                  )
                : _FaithPage(
                    db: db,
                    faith: pending,
                    cost: _cost,
                    cooldown: _cooldown,
                    error: _error,
                    busy: _busy,
                    following: save.religionId == pending.religionId,
                    canChoose:
                        !_busy &&
                        !_cooldownBlocks &&
                        save.gold >= _cost &&
                        save.religionId != pending.religionId,
                    onBack: _busy ? null : _backToList,
                    onChoose: _choose,
                    onClose: widget.onClose,
                  ),
          ),
        );
      },
    );
  }
}

class _FaithList extends StatelessWidget {
  const _FaithList({
    required this.db,
    required this.faiths,
    required this.currentId,
    required this.onOpen,
    required this.onClose,
  });

  final GameDatabase db;
  final List<ReligionRow> faiths;
  final String? currentId;
  final ValueChanged<String> onOpen;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Choose a faith…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: GameFont.l, fontWeight: FontWeight.w400),
              ),
            ),
            if (onClose != null) GameCloseButton(onPressed: onClose!),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final faith in faiths)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _FaithNameRow(
                      faith: faith,
                      bonuses: faithBonusViews(db, faith.religionId),
                      flavour: faithFlavourLine(faith),
                      current: currentId == faith.religionId,
                      onTap: () => onOpen(faith.religionId),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FaithPage extends StatelessWidget {
  const _FaithPage({
    required this.db,
    required this.faith,
    required this.cost,
    required this.cooldown,
    required this.error,
    required this.busy,
    required this.following,
    required this.canChoose,
    required this.onBack,
    required this.onChoose,
    required this.onClose,
  });

  final GameDatabase db;
  final ReligionRow faith;
  final num cost;
  final String? cooldown;
  final String? error;
  final bool busy;
  final bool following;
  final bool canChoose;
  final VoidCallback? onBack;
  final VoidCallback onChoose;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final god = faithGodName(faith);
    final bonuses = faithBonusViews(db, faith.religionId);
    final flavour = faithFlavourLine(faith);
    final description = faithDescription(faith);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                faith.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: GameFont.l, fontWeight: FontWeight.w400),
              ),
            ),
            if (onClose != null) GameCloseButton(onPressed: onClose!),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (god != null && god.isNotEmpty)
                  Text(
                    god,
                    style: TextStyle(fontSize: GameFont.m, color: UiChrome.of(context).panelInk),
                  ),
                if (bonuses.isNotEmpty) ...[
                  if (god != null && god.isNotEmpty) const SizedBox(height: 12),
                  _FaithBonusList(religionId: faith.religionId, bonuses: bonuses),
                ],
                if (flavour.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(flavour, key: Key('faith-flavour-${faith.religionId}')),
                ],
                if (description.isNotEmpty) ...[const SizedBox(height: 12), Text(description)],
                const SizedBox(height: 12),
                _FaithCost(cost: cost),
                if (cooldown case final remaining?) Text(remaining),
                if (error case final message?)
                  Text(
                    message,
                    style: const TextStyle(color: Palette.danger, fontSize: GameFont.s),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                key: const Key('faith-back'),
                height: minItemTapExtent,
                child: GameButton(label: 'Back', tone: GameButtonTone.secondary, onPressed: onBack),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                key: const Key('faith-choose'),
                height: minItemTapExtent,
                child: GameButton(
                  label: 'Choose',
                  waiting: busy,
                  onPressed: canChoose && !following ? onChoose : null,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FaithCost extends StatelessWidget {
  const _FaithCost({required this.cost});

  final num cost;

  @override
  Widget build(BuildContext context) {
    if (cost <= 0) return const Text('Free');
    return GoldAmount(amount: cost);
  }
}

/// God name from the Religions `God` column.
String? faithGodName(ReligionRow faith) {
  final name = faith.god?.trim();
  if (name == null || name.isEmpty) return null;
  return name;
}

/// Lore line from the Religions `Description` column. Empty until that column lands.
String faithDescription(ReligionRow faith) {
  final raw = faith.raw['Description'];
  if (raw is! String) return '';
  return raw.trim();
}

/// Quest flavour keyed by Religions `Religion ID`.
const Map<String, String> faithFlavourById = <String, String>{
  'REL-0001': 'Bow to the god Oruveth and receive their guidance in tending the forest.',
  'REL-0002': 'Bow to the god Theryvak and receive their guidance in the patient hunt.',
  'REL-0003': 'Bow to the god Ulvaryn and receive their guidance on the waters.',
  'REL-0004': 'Bow to the god Azhurak and receive their guidance in battle.',
  'REL-0005': 'Bow to the god Zorvael and receive their guidance in fortune.',
  'REL-0006': 'Bow to the god Gorveth and receive their guidance in the deep stone.',
  'REL-0007': 'Bow to the god Saelun and receive their guidance in the harvest.',
};

String faithFlavourLine(ReligionRow faith) {
  final id = faith.raw['Religion ID'];
  if (id is! String) return '';
  return faithFlavourById[id] ?? '';
}

/// One faith bonus, split into amount, optional skill, and stat from the row.
class FaithBonusView {
  const FaithBonusView({required this.amountLabel, required this.statLabel, this.skillName});

  final String amountLabel;
  final String statLabel;
  final String? skillName;

  /// Skill (when the bonus is tied to one) plus the stat, e.g. `Woodcutting drop chance`.
  String get detailLine {
    final skill = skillName;
    if (skill != null && skill.isNotEmpty) return '$skill $statLabel';
    return statLabel;
  }
}

/// Every bonus this faith gives, in database order. Nothing is dropped.
List<FaithBonusView> faithBonusViews(GameDatabase db, String religionId) {
  return [for (final bonus in religionBonusesFor(db, religionId)) faithBonusView(db, bonus)];
}

FaithBonusView faithBonusView(GameDatabase db, ReligionBonusRow bonus) {
  final value = jsNumber(bonus.raw['Bonus Value'] ?? 0);
  final amount = value.isFinite ? jsNumberToString(value) : '0';
  final bonusType = bonus.raw['Bonus Type'];
  final percent = bonusType is String && bonusType.endsWith('_percent');
  final amountLabel = percent ? '+$amount%' : '+$amount';
  final reference = bonus.raw['Reference ID'];
  String? skillName;
  if (reference is String && reference.isNotEmpty) {
    String? displayName;
    for (final row in db.skills) {
      if (row.raw['Skill ID'] != reference) continue;
      final name = row.raw['Display Name'];
      if (name is String) displayName = name;
      break;
    }
    skillName = displayName != null && displayName.trim().isNotEmpty
        ? displayName.trim()
        : reference;
  }
  final statLabel = switch (bonusType) {
    'skill_drop_chance_percent' => 'drop chance',
    'max_hp_percent' => 'maximum HP',
    'gold_gain_percent' => 'Gold from enemies and actions',
    _ => bonusType is String && bonusType.trim().isNotEmpty ? bonusType : '',
  };
  return FaithBonusView(amountLabel: amountLabel, statLabel: statLabel, skillName: skillName);
}

class _FaithBonusList extends StatelessWidget {
  const _FaithBonusList({required this.religionId, required this.bonuses, this.compact = false});

  final String religionId;
  final List<FaithBonusView> bonuses;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < bonuses.length; i++) ...[
          if (i > 0) SizedBox(height: compact ? 8 : 10),
          KeyedSubtree(
            key: Key('faith-bonus-$religionId-$i'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bonuses[i].amountLabel,
                  style: TextStyle(
                    fontSize: compact ? GameFont.s : GameFont.m,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 2),
                Text(bonuses[i].detailLine, style: const TextStyle(fontSize: GameFont.s)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _FaithNameRow extends StatelessWidget {
  const _FaithNameRow({
    required this.faith,
    required this.bonuses,
    required this.flavour,
    required this.current,
    required this.onTap,
  });

  final ReligionRow faith;
  final List<FaithBonusView> bonuses;
  final String flavour;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: Key('faith-${faith.religionId}'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minItemTapExtent),
        child: GamePanel(
          highlight: current,
          onTap: onTap,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                faith.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w400),
              ),
              if (bonuses.isNotEmpty) ...[
                const SizedBox(height: 8),
                _FaithBonusList(religionId: faith.religionId, bonuses: bonuses, compact: true),
              ],
              if (flavour.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  flavour,
                  key: Key('faith-flavour-${faith.religionId}'),
                  style: const TextStyle(fontSize: GameFont.s),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
