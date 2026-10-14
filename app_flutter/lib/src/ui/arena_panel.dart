import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'action_stage.dart';
import 'format.dart';
import 'item_icon.dart';
import 'player_gear_sheet.dart';
import 'plaza_points.dart';

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
  List<PvpRoundResult>? _replayRounds;
  String? _rankedCode;
  num? _rankedPointsGained;
  bool _startingFight = false;
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
    controller.progress.addListener(_onTick);
    _loadOpponents();
  }

  @override
  void dispose() {
    controller.progress.removeListener(_onTick);
    _searchFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onTick() {
    if (!_fighting || _outcome != null || !mounted) return;
    _advanceRounds(until: controller.session.clock());
  }

  Future<void> _loadOpponents() async {
    try {
      final rows = await multiplayer.service.listArenaOpponents();
      final own = await multiplayer.service.ownPvpSnapshot();
      if (!mounted) return;
      setState(() {
        _all = rows;
        _matches = searchArenaOpponents(rows, _search.text);
        _ownLoadout = own;
        _equipmentSaved = own != null;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load arena opponents: $error';
      });
    }
  }

  void _filter() {
    setState(() => _matches = searchArenaOpponents(_all, _search.text));
  }

  Future<void> _viewOpponentGear(ArenaOpponent opponent) async {
    final themSave = await multiplayer.service.readOpponentSave(opponent.userId);
    if (!mounted) return;
    if (themSave == null) {
      setState(() => _error = 'That player has no saved fight loadout.');
      return;
    }
    await openPlayerGear(
      context,
      controller: controller,
      username: opponent.username,
      equipment: publicPvpEquipmentFromSave(themSave),
    );
  }

  Future<void> _fightOpponent(ArenaOpponent opponent, {required bool ranked}) async {
    final loadout = _ownLoadout;
    if (loadout == null) {
      setState(() => _error = pvpEquipmentRequired);
      return;
    }
    if (ranked && multiplayer.service.hostedCommands) {
      await _hostedRankedFight();
      return;
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
      _replayRounds = null;
      _rankedCode = null;
      _rankedPointsGained = null;
    });
  }

  Future<void> _rankedMatch() async {
    if (multiplayer.service.hostedCommands) {
      await _hostedRankedFight();
      return;
    }
    final pick = pickRankedOpponent(combatLevelOf(save), totalLevel(save), _all);
    if (pick == null) {
      setState(() => _error = 'No other players to fight.');
      return;
    }
    await _fightOpponent(pick, ranked: true);
  }

  Future<void> _hostedRankedFight() async {
    final loadout = _ownLoadout;
    if (loadout == null) {
      setState(() => _error = pvpEquipmentRequired);
      return;
    }
    if (_startingFight) return;
    setState(() {
      _startingFight = true;
      _error = null;
    });
    final result = await multiplayer.submitGameCommand('ranked_pvp_fight');
    if (!mounted) return;
    if (!result.ok || result.rounds == null || result.rounds!.isEmpty) {
      setState(() {
        _startingFight = false;
        _error = result.reason ?? 'Could not start a ranked fight.';
      });
      return;
    }
    final opponent =
        result.opponent ??
        ArenaOpponent(userId: 'opponent', username: 'Opponent', combatLevel: 1, totalLevel: 1);
    final themSave = result.opponent != null
        ? await multiplayer.service.readOpponentSave(result.opponent!.userId)
        : null;
    if (!mounted) return;
    final you = composePvpFighter(controller.db, save, loadout);
    final them = themSave == null ? you : composePvpFighter(controller.db, themSave, themSave);
    setState(() {
      _startingFight = false;
      _error = null;
      _opponent = opponent;
      _you = you;
      _them = them;
      _youHp = you.currentHp;
      _themHp = them.currentHp;
      _youMaxHp = result.youMaxHp ?? you.currentHp;
      _themMaxHp = result.themMaxHp ?? them.currentHp;
      _roundStartedAt = controller.session.clock();
      _round = null;
      _roundSeq = 0;
      _outcome = null;
      _rankedFight = true;
      _rankedApplied = true;
      _replayRounds = result.rounds;
      _rankedCode = result.code;
      _rankedPointsGained = result.pointsGained;
    });
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
    final replay = _replayRounds;
    while (outcome == null && seq < 2000 && (skip || until - startedAt >= roundMs)) {
      final PvpRoundResult round;
      if (replay != null) {
        if (seq >= replay.length) {
          outcome = last?.outcome == 'win' ? 'win' : 'loss';
          break;
        }
        round = replay[seq];
      } else {
        round = resolvePvpRound(controller.db, you, them, youHp, themHp, controller.session.random);
      }
      last = round;
      youHp = round.youHp;
      themHp = round.themHp;
      seq += 1;
      if (!skip) startedAt += roundMs;
      if (round.outcome != 'ongoing') outcome = round.outcome;
    }
    if (seq >= 2000 && outcome == null) outcome = 'loss';
    if (outcome != null) _applyRanked(outcome);
    if (!mounted) return;
    setState(() {
      _youHp = youHp;
      _themHp = themHp;
      _round = last;
      _roundSeq = seq;
      _roundStartedAt = startedAt;
      _outcome = outcome;
    });
  }

  void _applyRanked(String outcome) {
    if (!_rankedFight || _rankedApplied) return;
    _rankedApplied = true;
    if (multiplayer.service.hostedCommands) return;
    final next = applyRankedPvpResult(save, outcome == 'win', controller.session.clock());
    controller.commit(next.save);
    _rankedPointsGained = next.pointsGained;
    _rankedCode = next.code;
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
          _ownLoadout = stripPvpConsumables(save);
        } else {
          _error = result.reason ?? 'Could not save PvP equipment.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _savingEquipment = false;
        _error = 'Could not save PvP equipment: $error';
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
      _replayRounds = null;
      _rankedCode = null;
      _rankedPointsGained = null;
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
                child: Text(
                  'Arena',
                  style: TextStyle(fontSize: GameFont.l, fontWeight: FontWeight.w400),
                ),
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
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GameButton(
                                label: 'View gear',
                                tone: GameButtonTone.secondary,
                                compact: true,
                                onPressed: () => _viewOpponentGear(row),
                              ),
                              const SizedBox(width: 6),
                              GameButton(
                                label: 'Fight',
                                compact: true,
                                onPressed: () => _fightOpponent(row, ranked: false),
                              ),
                            ],
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
    final remaining = rankedWinsRemaining(save, controller.session.clock());
    final capped = remaining <= 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MutedText(
          'Closest combat level. Win: ${formatThousands(rankedPvpWinPoints)} plaza points. '
          '${capped ? '0' : remaining} / ${formatThousands(rankedPvpDailyCap)} ranked wins left today.',
        ),
        if (capped) ...[const SizedBox(height: 6), const MutedText(rankedPvpDailyCapMessage)],
        const SizedBox(height: 8),
        GameButton(
          label: _startingFight ? 'Matching…' : 'Find match',
          onPressed: _loading || _startingFight ? null : _rankedMatch,
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
    final rankedGain = plazaPointsGainedNotice(_rankedPointsGained);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PvpActionStage(
          youName: save.characterName ?? 'You',
          themName: opponent.username,
          youAppearance: save.appearance,
          themAppearance: _them?.appearance ?? opponent.appearance ?? save.appearance,
          youRaceId: save.raceId,
          themRaceId: _them?.raceId,
          youBytes: controller.localPlayerPng,
          youHp: _youHp,
          youMaxHp: _youMaxHp,
          themHp: _themHp,
          themMaxHp: _themMaxHp,
          roundProgress: _roundProgress,
          controller: controller,
          roundStartedAt: _roundStartedAt,
          roundMs: _roundMs,
          round: _round,
          roundSeq: _roundSeq,
          finished: finished,
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: PlayerGearSheet(
                controller: controller,
                username: opponent.username,
                equipment: publicPvpEquipmentFromSave(_them),
                embedded: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!finished)
                    GameButton(label: 'Skip', tone: GameButtonTone.secondary, onPressed: _skipFight)
                  else ...[
                    Text(
                      _outcome == 'win' ? 'Victory' : 'Defeat',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: GameFont.xl,
                        fontWeight: FontWeight.w400,
                        color: _outcome == 'win'
                            ? const Color(0xFFB6E38A)
                            : const Color(0xFFFF8A8A),
                      ),
                    ),
                    if (_rankedFight && _rankedCode == rankedPvpDailyCapCode)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: MutedText(rankedPvpDailyCapMessage, textAlign: TextAlign.center),
                      )
                    else if (_rankedFight && _outcome == 'win' && rankedGain != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: MutedText(rankedGain, textAlign: TextAlign.center),
                      )
                    else if (_rankedFight && _outcome != 'win')
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: MutedText(
                          'Ranked fight recorded. No gold.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    else if (!_rankedFight)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: MutedText('Search fight. No gold.', textAlign: TextAlign.center),
                      ),
                    const SizedBox(height: 8),
                    GameButton(label: 'Back', onPressed: _clearFight),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
