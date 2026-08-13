import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

List<ArenaOpponent> _candidatesOf(ParityFixture fixture) {
  return fixture.inputField<List<Object?>>('candidates').map((value) {
    final row = value! as Map<String, Object?>;
    return ArenaOpponent(
      userId: row['userId']! as String,
      username: row['username']! as String,
      combatLevel: row['combatLevel']! as num,
      totalLevel: row['totalLevel']! as num,
    );
  }).toList();
}

Map<String, Object?>? _opponentJson(ArenaOpponent? row) {
  if (row == null) return null;
  return <String, Object?>{
    'userId': row.userId,
    'username': row.username,
    'combatLevel': row.combatLevel,
    'totalLevel': row.totalLevel,
  };
}

PlayerSave _withCombatLevel(PlayerSave save, num level) {
  return save.copyWith(
    skills: save.skills
        .map((skill) => skill.skillId == combatSkillId ? skill.copyWith(level: level) : skill)
        .toList(),
  );
}

void main() {
  group('pvp matchmaking parity', () {
    for (final fixture in loadParityFixtures('pvp/matchmaking')) {
      if (fixture.name != 'search-and-ranked') continue;
      test(fixture.name, () {
        final candidates = _candidatesOf(fixture);
        expect(
          checkParity(fixture, {
            'empty': searchArenaOpponents(candidates, '  ').map(_opponentJson).toList(),
            'mira': searchArenaOpponents(candidates, 'mi').map(_opponentJson).toList(),
            'a': searchArenaOpponents(candidates, 'A').map((row) => row.username).toList(),
            'closestLow': _opponentJson(pickRankedOpponent(1, 13, candidates)),
            'closestMira': _opponentJson(pickRankedOpponent(8, 13, candidates)),
            'closestKael': _opponentJson(pickRankedOpponent(18, 18, candidates)),
            'none': _opponentJson(pickRankedOpponent(1, 13, const <ArenaOpponent>[])),
          }),
          isNull,
        );
      });
    }

    for (final fixture in loadParityFixtures('pvp/matchmaking')) {
      if (fixture.name != 'ranked-cap') continue;
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final nowMs = fixture.inputField<num>('nowMs');
        var save = createNewSave(db, nowMs);
        final remainingFresh = rankedFightsRemaining(save, nowMs);
        final startOk = canStartRankedPvp(save, nowMs);
        save = applyRankedPvpResult(save, true, nowMs);
        for (var i = 0; i < 4; i++) {
          save = applyRankedPvpResult(save, false, nowMs);
        }
        final blocked = canStartRankedPvp(save, nowMs);
        final nextDay = applyRankedPvpResult(save, false, nowMs + 24 * 60 * 60 * 1000);
        expect(
          checkParity(fixture, {
            'remainingFresh': remainingFresh,
            'startOk': startOk.toJson(),
            'afterFive': <String, Object?>{
              'fights': save.rankedPvpFightsToday,
              'wins': save.rankedPvpWins,
              'losses': save.rankedPvpLosses,
              'remaining': rankedFightsRemaining(save, nowMs),
              'kd': rankedPvpKd(save.rankedPvpWins, save.rankedPvpLosses),
            },
            'blocked': blocked.toJson(),
            'nextDay': <String, Object?>{
              'dayKey': nextDay.rankedPvpDayKey,
              'fights': nextDay.rankedPvpFightsToday,
            },
          }),
          isNull,
        );
      });
    }
  });

  group('pvp fight parity', () {
    for (final fixture in loadParityFixtures('pvp/fight')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final nowMs = fixture.inputField<num>('nowMs');
        final seed = fixture.inputField<num>('seed').toInt();
        final you = createNewSave(db, nowMs);
        final them = _withCombatLevel(createNewSave(db, nowMs), 18);
        final fight = simulatePvpFight(db, you, them, Mulberry32(seed).asFunction);
        expect(
          checkParity(fixture, {
            'outcome': fight.outcome,
            'roundCount': fight.rounds.length,
            'last': fight.rounds.isEmpty ? null : fight.rounds.last.toJson(),
            'youMaxHp': fight.youMaxHp,
            'themMaxHp': fight.themMaxHp,
          }),
          isNull,
        );
      });
    }
  });

  group('pvp arena locations parity', () {
    for (final fixture in loadParityFixtures('pvp/arena')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        LocationRow? byId(String id) =>
            db.locations.where((row) => row.locationId == id).firstOrNull;
        expect(
          checkParity(fixture, {
            'plaza': locationHasArena(byId('LOC-0028')),
            'combat': locationHasArena(byId('LOC-0032')),
            'market': locationHasArena(byId('LOC-0029')),
            'missing': locationHasArena(null),
          }),
          isNull,
        );
      });
    }
  });
}
