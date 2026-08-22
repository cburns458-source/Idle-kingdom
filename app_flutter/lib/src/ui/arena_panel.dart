import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'action_stage.dart';
import 'format.dart';
import 'item_icon.dart';

enum _ArenaTab { search, ranked }

/// Citadel arena: search any stored player by name, or take a ranked match
/// against whoever is closest in combat level.
class ArenaPanel extends StatefulWidget {
  const ArenaPanel({super.key, required this.controller, required this.multiplayer, this.onClose});

  final GameController controller;
  final MultiplayerController multiplayer;
  final VoidCallback? onClose;

  @override
  State<ArenaPanel> createState() => _ArenaPanelState();
}

class _ArenaPanelState extends State<ArenaPanel> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  _ArenaTab _tab = _ArenaTab.search;
  List<ArenaOpponent> _all = const <ArenaOpponent>[];
  List<ArenaOpponent> _matches = const <ArenaOpponent>[];
  bool _loading = true;
  String? _error;
  ArenaOpponent? _opponent;
  PlayerSave? _you;
  PlayerSave? _them;
  num _youHp = 0;
  num _themHp = 0;
  num _youMaxHp = 0;
  num _themMaxHp = 0;
  num _roundStartedAt = 0;
  PvpRoundResult? _round;
  int _roundSeq = 0;
  String? _outcome;
  bool _rankedFight = false;
  bool _rankedApplied = false;
  bool _savingEquipment = false;
  bool _equipmentSaved = false;
  PlayerSave? _ownLoadout;

  GameController get controller => widget.controller;
  MultiplayerController get multiplayer => widget.multiplayer;
  PlayerSave get save => controller.save;
  bool get _fighting => _you != null && _them != null;

  num get _roundMs => configNumber(controller.db, 'combat_round_duration', 4) * 1000;

  double get _roundProgress {
    if (!_fighting || _outcome != null) return _outcome == null ? 0 : 1;
    final elapsed = controller.session.clock() - _roundStartedAt;
    return _roundMs <= 0 ? 1 : (elapsed / _roundMs).clamp(0, 1).toDouble();
  }

  @override
  void initState() {
    super.initState();
    controller.addListener(_onTick);
    _loadOpponents();
  }

  @override
  void dispose() {
    controller.removeListener(_onTick);
    _searchFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onTick() {
    if (!_fighting || _outcome != null || !mounted) return;
    _advanceRounds(until: controller.session.clock());
  }

  Future<void> _loadOpponents() async {
    final rows = await multiplayer.service.listArenaOpponents();
    final own = await multiplayer.service.ownPvpSnapshot();
    if (!mounted) return;
    setState(() {
      _all = rows;
      _matches = searchArenaOpponents(rows, _search.text);
      _ownLoadout = own;
      _equipmentSaved = own != null;
      _loading = false;
    });
  }

  void _filter() {
    setState(() => _matches = searchArenaOpponents(_all, _search.text));
  }

  Future<void> _fightOpponent(ArenaOpponent opponent, {required bool ranked}) async {
    final loadout = _ownLoadout;
    if (loadout == null) {
      setState(() => _error = pvpEquipmentRequired);
      return;
    }
    if (ranked) {
      final gate = canStartRankedPvp(save, controller.session.clock());
      if (!gate.ok) {
        setState(() => _error = gate.reason);
        return;
      }
    }
    final themSave = await multiplayer.service.readOpponentSave(opponent.userId);
    if (!mounted) return;
    if (themSave == null) {
      setState(() => _error = 'That player has no character to fight.');
      return;
    }
    final you = composePvpFighter(controller.db, save, loadout);
    final them = composePvpFighter(controller.db, themSave, themSave);
    setState(() {
      _error = null;
      _opponent = opponent;
      _you = you;
      _them = them;
      _youHp = you.currentHp;
      _themHp = them.currentHp;
      _youMaxHp = you.currentHp;
      _themMaxHp = them.currentHp;
      _roundStartedAt = controller.session.clock();
      _round = null;
      _roundSeq = 0;
      _outcome = null;
      _rankedFight = ranked;
      _rankedApplied = false;
    });
  }

  Future<void> _rankedMatch() async {
    final pick = pickRankedOpponent(combatLevelOf(save), totalLevel(save), _all);
    if (pick == null) {
      setState(() => _error = 'No other players to fight.');
      return;
    }
    await _fightOpponent(pick, ranked: true);
  }

  void _advanceRounds({required num until, bool skip = false}) {
    final you = _you;
    final them = _them;
    if (you == null || them == null || _outcome != null) return;
    final roundMs = _roundMs;
    var youHp = _youHp;
    var themHp = _themHp;
    var startedAt = _roundStartedAt;
    var seq = _roundSeq;
    PvpRoundResult? last = _round;
    String? outcome;
    while (outcome == null && seq < 2000 && (skip || until - startedAt >= roundMs)) {
      final round = resolvePvpRound(
        controller.db,
        you,
        them,
        youHp,
        themHp,
        controller.session.random,
      );
      last = round;
      youHp = round.youHp;
      themHp = round.themHp;
      seq += 1;
      if (!skip) startedAt += roundMs;
      if (round.outcome != 'ongoing') outcome = round.outcome;
    }
    if (seq >= 2000 && outcome == null) outcome = 'loss';
    if (!mounted) return;
    setState(() {
      _youHp = youHp;
      _themHp = themHp;
      _round = last;
      _roundSeq = seq;
      _roundStartedAt = startedAt;
      _outcome = outcome;
    });
    if (outcome != null) _applyRanked(outcome);
  }

  void _applyRanked(String outcome) {
    if (!_rankedFight || _rankedApplied) return;
    _rankedApplied = true;
    final next = applyRankedPvpResult(save, outcome == 'win', controller.session.clock());
    controller.commit(next);
  }

  Future<void> _saveEquipment() async {
    if (_savingEquipment) return;
    setState(() {
      _savingEquipment = true;
      _error = null;
    });
    try {
      final result = await multiplayer.service.savePvpEquipment(save);
      if (!mounted) return;
      setState(() {
        _savingEquipment = false;
        if (result.ok) {
          _equipmentSaved = true;
          _ownLoadout = save;
        } else {
          _error = result.reason ?? 'Could not save PvP equipment.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingEquipment = false;
        _error = 'Could not save PvP equipment.';
      });
    }
  }

  void _skipFight() {
    _advanceRounds(until: controller.session.clock(), skip: true);
  }

  void _clearFight() {
    setState(() {
      _you = null;
      _them = null;
      _opponent = null;
      _round = null;
      _roundSeq = 0;
      _outcome = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GamePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Arena', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w400)),
              ),
              GoldAmount(
                amount: save.gold,
                style: const TextStyle(color: Palette.gold),
              ),
              if (widget.onClose != null)
                GameIconButton(icon: Icons.close, tooltip: 'Close', onPressed: widget.onClose),
            ],
          ),
          const MutedText('You fight in the gear you save. Combat level and race stay current.'),
          if (_error case final error?) ...[
            const SizedBox(height: 6),
            Text(error, style: warningStyle),
          ],
          const SizedBox(height: 10),
          Expanded(child: _fighting ? SingleChildScrollView(child: _fightView()) : _lobby()),
        ],
      ),
    );
  }

  Widget _lobby() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GameButton(
          label: _savingEquipment ? 'Saving…' : 'Save equipment',
          tone: GameButtonTone.secondary,
          onPressed: _savingEquipment ? null : _saveEquipment,
        ),
        const SizedBox(height: 6),
        MutedText(
          _equipmentSaved
              ? 'Loadout saved. Others will fight this gear at your current combat level.'
              : 'Save the gear you fight in. Search and ranked ignore anyone who has not saved.',
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: GameButton(
                label: 'Search',
                tone: _tab == _ArenaTab.search ? GameButtonTone.primary : GameButtonTone.secondary,
                onPressed: () => setState(() => _tab = _ArenaTab.search),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GameButton(
                label: 'Ranked',
                tone: _tab == _ArenaTab.ranked ? GameButtonTone.primary : GameButtonTone.secondary,
                onPressed: () => setState(() => _tab = _ArenaTab.ranked),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(child: _tab == _ArenaTab.search ? _searchLobby() : _rankedLobby()),
      ],
    );
  }

  Widget _searchLobby() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MutedText('Search by name. No gold, no rank.'),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Align(alignment: Alignment.topLeft, child: MutedText('Loading players…'))
              : _search.text.trim().isEmpty
              ? const Align(
                  alignment: Alignment.topLeft,
                  child: MutedText('Type a name to find someone.'),
                )
              : _matches.isEmpty
              ? const Align(
                  alignment: Alignment.topLeft,
                  child: MutedText('No players match that name.'),
                )
              : ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final row in _matches)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: DockRow(
                          title: row.username,
                          lines: [MutedText('Combat ${formatThousands(row.combatLevel)}')],
                          trailing: GameButton(
                            label: 'Fight',
                            onPressed: () => _fightOpponent(row, ranked: false),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        TextField(
          key: const Key('arena-search-field'),
          focusNode: _searchFocus,
          controller: _search,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(hintText: 'Player name'),
          onChanged: (_) => _filter(),
        ),
      ],
    );
  }

  Widget _rankedLobby() {
    final remaining = rankedFightsRemaining(save, controller.session.clock());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MutedText(
          'Closest combat level. Win: ${formatThousands(rankedPvpWinGold)} gold. '
          '$remaining / ${formatThousands(rankedPvpDailyCap)} left today.',
        ),
        const SizedBox(height: 8),
        GameButton(
          label: 'Find match',
          onPressed: remaining > 0 && !_loading ? _rankedMatch : null,
        ),
        const SizedBox(height: 6),
        MutedText(
          'Record ${formatThousands(save.rankedPvpWins)}–${formatThousands(save.rankedPvpLosses)} '
          '(K/D ${rankedPvpKd(save.rankedPvpWins, save.rankedPvpLosses).toStringAsFixed(2)}).',
        ),
      ],
    );
  }

  Widget _fightView() {
    final opponent = _opponent!;
    final finished = _outcome != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PvpActionStage(
          youName: save.characterName ?? 'You',
          themName: opponent.username,
          youAppearance: save.appearance,
          themAppearance: _them?.appearance ?? opponent.appearance ?? save.appearance,
          youBytes: controller.localPlayerPng,
          youHp: _youHp,
          youMaxHp: _youMaxHp,
          themHp: _themHp,
          themMaxHp: _themMaxHp,
          roundProgress: _roundProgress,
          round: _round,
          roundSeq: _roundSeq,
          finished: finished,
        ),
        const SizedBox(height: 8),
        if (!finished)
          GameButton(label: 'Skip', tone: GameButtonTone.secondary, onPressed: _skipFight)
        else ...[
          Text(
            _outcome == 'win' ? 'Victory' : 'Defeat',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w400,
              color: _outcome == 'win' ? const Color(0xFFB6E38A) : const Color(0xFFFF8A8A),
            ),
          ),
          if (_rankedFight && _outcome == 'win')
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: MutedText('Ranked purse: 1,000 gold.', textAlign: TextAlign.center),
            )
          else if (_rankedFight)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: MutedText('Ranked fight recorded. No gold.', textAlign: TextAlign.center),
            )
          else
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: MutedText('Search fight. No gold.', textAlign: TextAlign.center),
            ),
          const SizedBox(height: 8),
          GameButton(label: 'Back', onPressed: _clearFight),
        ],
      ],
    );
  }
}
