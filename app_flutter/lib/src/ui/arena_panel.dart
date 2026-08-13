import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import '../content/asset_paths.dart';
import '../session/game_controller.dart';
import '../session/multiplayer_controller.dart';
import '../theme.dart';
import 'format.dart';
import 'item_icon.dart';

/// How long each recorded PvP round stays on screen. Live PvE rounds are slower.
const Duration _pvpPlaybackTick = Duration(milliseconds: 200);

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
  _ArenaTab _tab = _ArenaTab.search;
  List<ArenaOpponent> _all = const <ArenaOpponent>[];
  List<ArenaOpponent> _matches = const <ArenaOpponent>[];
  bool _loading = true;
  String? _error;
  ArenaOpponent? _opponent;
  PvpFightResult? _fight;
  int _roundIndex = 0;
  bool _showResult = false;
  Timer? _playback;
  bool _rankedFight = false;

  GameController get controller => widget.controller;
  MultiplayerController get multiplayer => widget.multiplayer;
  PlayerSave get save => controller.save;

  @override
  void initState() {
    super.initState();
    _loadOpponents();
  }

  @override
  void dispose() {
    _playback?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadOpponents() async {
    final rows = await multiplayer.service.listArenaOpponents();
    if (!mounted) return;
    setState(() {
      _all = rows;
      _matches = searchArenaOpponents(rows, _search.text);
      _loading = false;
    });
  }

  void _filter() {
    setState(() => _matches = searchArenaOpponents(_all, _search.text));
  }

  Future<void> _fightOpponent(ArenaOpponent opponent, {required bool ranked}) async {
    if (ranked) {
      final gate = canStartRankedPvp(save, controller.session.clock());
      if (!gate.ok) {
        setState(() => _error = gate.reason);
        return;
      }
    }
    final them = await multiplayer.service.readOpponentSave(opponent.userId);
    if (!mounted) return;
    if (them == null) {
      setState(() => _error = 'That player has no character to fight.');
      return;
    }
    final fight = simulatePvpFight(controller.db, save, them, controller.session.random);
    if (ranked) {
      final next = applyRankedPvpResult(save, fight.outcome == 'win', controller.session.clock());
      controller.commit(next);
      unawaited(multiplayer.service.submitLeaderboard(controller.db, next));
    }
    _playback?.cancel();
    setState(() {
      _error = null;
      _opponent = opponent;
      _fight = fight;
      _rankedFight = ranked;
      _roundIndex = 0;
      _showResult = fight.rounds.isEmpty;
    });
    if (fight.rounds.length <= 1) {
      setState(() => _showResult = true);
      return;
    }
    _playback = Timer.periodic(_pvpPlaybackTick, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_roundIndex >= fight.rounds.length - 1) {
          timer.cancel();
          _showResult = true;
        } else {
          _roundIndex++;
        }
      });
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

  void _skipPlayback() {
    _playback?.cancel();
    setState(() {
      final fight = _fight;
      if (fight != null && fight.rounds.isNotEmpty) {
        _roundIndex = fight.rounds.length - 1;
      }
      _showResult = true;
    });
  }

  void _clearFight() {
    _playback?.cancel();
    setState(() {
      _fight = null;
      _opponent = null;
      _showResult = false;
      _roundIndex = 0;
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
                child: Text('Arena', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              GoldAmount(
                amount: save.gold,
                style: const TextStyle(color: Palette.gold),
              ),
              if (widget.onClose != null)
                IconButton(
                  onPressed: widget.onClose,
                  tooltip: 'Close',
                  icon: const Icon(Icons.close, size: 18),
                ),
            ],
          ),
          const MutedText('Snapshot fights. Current equipment. Any player on the game.'),
          if (_error case final error?) ...[
            const SizedBox(height: 6),
            Text(error, style: warningStyle),
          ],
          const SizedBox(height: 10),
          if (_fight != null) _fightView() else _lobby(),
        ],
      ),
    );
  }

  Widget _lobby() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        if (_tab == _ArenaTab.search) _searchLobby() else _rankedLobby(),
      ],
    );
  }

  Widget _searchLobby() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MutedText('Search by name. No gold, no rank.'),
        const SizedBox(height: 8),
        TextField(
          controller: _search,
          decoration: const InputDecoration(hintText: 'Player name'),
          onChanged: (_) => _filter(),
        ),
        const SizedBox(height: 8),
        if (_loading)
          const MutedText('Loading players…')
        else if (_search.text.trim().isEmpty)
          const MutedText('Type a name to find someone.')
        else if (_matches.isEmpty)
          const MutedText('No players match that name.')
        else
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
    final fight = _fight!;
    final opponent = _opponent!;
    final round = fight.rounds.isEmpty
        ? null
        : fight.rounds[_roundIndex.clamp(0, fight.rounds.length - 1)];
    final youHp = round?.youHp ?? fight.youMaxHp;
    final themHp = round?.themHp ?? fight.themMaxHp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PvpStage(
          youName: save.characterName ?? 'You',
          themName: opponent.username,
          youAppearance: save.appearance,
          themAppearance: opponent.appearance ?? save.appearance,
          youHp: youHp,
          youMaxHp: fight.youMaxHp,
          themHp: themHp,
          themMaxHp: fight.themMaxHp,
          round: round,
        ),
        const SizedBox(height: 8),
        if (!_showResult)
          GameButton(label: 'Skip', tone: GameButtonTone.secondary, onPressed: _skipPlayback)
        else ...[
          Text(
            fight.outcome == 'win' ? 'Victory' : 'Defeat',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: fight.outcome == 'win' ? const Color(0xFFB6E38A) : const Color(0xFFFF8A8A),
            ),
          ),
          if (_rankedFight && fight.outcome == 'win')
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

class _PvpStage extends StatelessWidget {
  const _PvpStage({
    required this.youName,
    required this.themName,
    required this.youAppearance,
    required this.themAppearance,
    required this.youHp,
    required this.youMaxHp,
    required this.themHp,
    required this.themMaxHp,
    required this.round,
  });

  final String youName;
  final String themName;
  final PlayerAppearance youAppearance;
  final PlayerAppearance themAppearance;
  final num youHp;
  final num youMaxHp;
  final num themHp;
  final num themMaxHp;
  final PvpRoundResult? round;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: [
                  Image.asset(
                    playerAssetPath(youAppearance),
                    height: 110,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerRight,
                    filterQuality: FilterQuality.none,
                  ),
                  Text(youName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (round != null && (round!.themHit ?? 0) > 0)
                    Text(
                      '-${round!.themHit!.round()}',
                      style: const TextStyle(color: Color(0xFFFFD0D0), fontWeight: FontWeight.w700),
                    ),
                  PillBar(
                    value: youMaxHp <= 0 ? 0 : (youHp / youMaxHp).clamp(0, 1).toDouble(),
                    gradient: Meters.playerHp,
                    height: 11.5,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                children: [
                  Image.asset(
                    playerAssetPath(themAppearance),
                    height: 110,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerLeft,
                    filterQuality: FilterQuality.none,
                  ),
                  Text(themName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (round != null && round!.youHit > 0)
                    Text(
                      round!.youCrit
                          ? 'CRIT ${round!.youHit.round()}'
                          : '-${round!.youHit.round()}',
                      style: TextStyle(
                        color: round!.youCrit ? const Color(0xFFFFD166) : const Color(0xFFFF8A3D),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  PillBar(
                    value: themMaxHp <= 0 ? 0 : (themHp / themMaxHp).clamp(0, 1).toDouble(),
                    gradient: Meters.enemyHp,
                    height: 11.5,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
