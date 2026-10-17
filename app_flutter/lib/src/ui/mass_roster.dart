import 'package:flutter/material.dart';
import 'package:ik_rules/ik_rules.dart';

import '../theme.dart';

/// Overlay copy on location art: parchment, not tan-panel ink.
const Color _rosterInk = Palette.parchmentText;

/// Gold on location art and stone boards. [Palette.gold] is ~4.1:1 on stone.
const Color _rosterGold = Palette.heading;

/// Late-joiner shares: grey parchment, not gold or green. ≥4.5:1 on wood/stone.
const Color rosterLateShare = Color(0xFFC8C8C8);

const String massJoinedLateLabel = 'Joined late, no loot';

/// Seconds left before a mass lobby locks, never below zero.
int massCountdownRemainingSeconds(MassEncounterSnapshot mass, num nowMs) {
  final ends = mass.countdownEndsAt;
  final endMs = ends == null ? null : DateTime.tryParse(ends)?.millisecondsSinceEpoch;
  if (endMs == null) return massCountdownSeconds;
  final remaining = ((endMs - nowMs) / 1000).ceil();
  return remaining < 0 ? 0 : remaining;
}

/// Lobby, fight, and settled-until-claim all keep locked-in rows on the list.
bool massRosterShowsShares(MassEncounterSnapshot mass) => mass.isFighting || mass.isSettled;

/// Lobby: players still here. Fight and settled: locked-in names plus late joiners.
List<MassParticipantView> massRosterRows(MassEncounterSnapshot mass) {
  final rows = [
    for (final row in mass.participants)
      if (massRosterShowsShares(mass) ? row.lockedIn || row.late : row.present) row,
  ];
  rows.sort((a, b) {
    final byDamage = b.damageDealt.compareTo(a.damageDealt);
    if (byDamage != 0) return byDamage;
    return a.username.toLowerCase().compareTo(b.username.toLowerCase());
  });
  return rows;
}

/// How many names the header counts, capped at [massPlayerCap] in the label.
int massRosterCount(MassEncounterSnapshot mass) {
  if (massRosterShowsShares(mass)) return mass.lockedCount.round().clamp(0, massPlayerCap);
  return massRosterRows(mass).length.clamp(0, massPlayerCap);
}

/// This row's share of summed damage, 0–100. Late joiners stay at 0.
int massDamageSharePercent(MassParticipantView row, List<MassParticipantView> rows) {
  if (row.late) return 0;
  final total = rows.fold<num>(0, (sum, other) => sum + (other.late ? 0 : other.damageDealt));
  if (total <= 0) return 0;
  return ((row.damageDealt / total) * 100).round();
}

/// Lobby countdown, player cap, and per-player damage shares.
///
/// Sits on location art, so copy stays parchment or gold. Late joiners get one
/// grey share line; options elsewhere stay unlabeled.
class MassRoster extends StatelessWidget {
  const MassRoster({super.key, required this.mass, required this.nowMs});

  final MassEncounterSnapshot mass;
  final num nowMs;

  @override
  Widget build(BuildContext context) {
    if (mass.isClosed) return const SizedBox.shrink();
    final rows = massRosterRows(mass);
    final count = massRosterCount(mass);
    final spectating = mass.you?.late == true;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (mass.isLobby)
            Text(
              '${massCountdownRemainingSeconds(mass, nowMs)}s',
              key: const Key('mass-countdown'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: GameFont.l,
                color: _rosterGold,
                shadows: overlayShadow,
              ),
            ),
          Text(
            '$count/$massPlayerCap',
            key: const Key('mass-player-count'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: GameFont.m, color: _rosterInk, shadows: overlayShadow),
          ),
          if (spectating)
            const Text(
              massJoinedLateLabel,
              key: Key('mass-spectating'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: GameFont.s,
                color: rosterLateShare,
                shadows: overlayShadow,
              ),
            ),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 88),
              child: ListView.builder(
                key: const Key('mass-participants'),
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final showsShares = massRosterShowsShares(mass);
                  final share = showsShares ? '${massDamageSharePercent(row, rows)}%' : null;
                  final shareColor = row.late ? rosterLateShare : _rosterGold;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            row.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: GameFont.s,
                              color: _rosterInk,
                              shadows: overlayShadow,
                            ),
                          ),
                        ),
                        if (row.late && showsShares)
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Text(
                              massJoinedLateLabel,
                              style: TextStyle(
                                fontSize: GameFont.s,
                                color: rosterLateShare,
                                shadows: overlayShadow,
                              ),
                            ),
                          ),
                        if (share != null)
                          Text(
                            share,
                            style: TextStyle(
                              fontSize: GameFont.s,
                              color: shareColor,
                              shadows: overlayShadow,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
