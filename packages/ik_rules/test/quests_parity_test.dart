import 'package:collection/collection.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

List<String> _stringList(ParityFixture fixture, String key) {
  return fixture.inputField<List<Object?>>(key).map((value) => value! as String).toList();
}

void main() {
  group('objective kind parity', () {
    for (final fixture in loadParityFixtures('quests/objective-kinds')) {
      test(fixture.name, () {
        final kinds = fixture
            .inputField<List<Object?>>('types')
            .map(normalizeObjectiveKind)
            .toList();
        expect(checkParity(fixture, {'kinds': kinds}), isNull);
      });
    }
  });

  group('quest objective parity', () {
    for (final fixture in loadParityFixtures('quests/objectives')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final rows = asQuestRows(db)
            .map(
              (quest) => <String, Object?>{
                'questId': quest['Quest ID'],
                'repeatable': isQuestRepeatable(quest),
                'structured': parseStructuredObjectives(quest).toJson(),
              },
            )
            .toList();
        expect(
          checkParity(fixture, {
            'rows': rows,
            'lookups': const <String>[
              'QST-0001',
              'QST-0002',
              'QST-9999',
            ].map((questId) => getQuest(db, questId)?['Quest ID']).toList(),
            'byNpc': const <String>['NPC-0001', 'NPC-0005', 'NPC-0007']
                .map(
                  (npcId) => <String, Object?>{
                    'npcId': npcId,
                    'questIds': questsForNpc(db, npcId).map((quest) => quest['Quest ID']).toList(),
                  },
                )
                .toList(),
            'statusLabels': const <String>[
              'inactive',
              'active',
              'completed',
            ].map(questStatusLabel).toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('quest progress view parity', () {
    for (final fixture in loadParityFixtures('quests/progress-view')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final byQuest = asQuestRows(db)
            .map(
              (quest) => <String, Object?>{
                'questId': quest['Quest ID'],
                'progress': getQuestProgress(save, jsString(quest['Quest ID'])).toJson(),
                'status': questObjectiveProgress(db, save, quest).toJson(),
              },
            )
            .toList();
        expect(checkParity(fixture, {'byQuest': byQuest}), isNull);
      });
    }
  });

  group('quest accept parity', () {
    for (final fixture in loadParityFixtures('quests/accept')) {
      test(fixture.name, () {
        final result = acceptQuest(
          databaseOf(fixture),
          saveOf(fixture),
          fixture.inputField<String>('questId'),
        );
        expect(
          checkParity(
            fixture,
            result.ok
                ? <String, Object?>{'ok': true, 'save': result.save!.toJson()}
                : <String, Object?>{'ok': false, 'reason': result.reason},
          ),
          isNull,
        );
      });
    }
  });

  group('quest completion parity', () {
    for (final fixture in loadParityFixtures('quests/complete')) {
      test(fixture.name, () {
        final result = completeQuest(
          databaseOf(fixture),
          saveOf(fixture),
          fixture.inputField<String>('questId'),
        );
        expect(
          checkParity(
            fixture,
            result.ok
                ? <String, Object?>{
                    'ok': true,
                    'save': result.save!.toJson(),
                    'message': result.message,
                    'questName': result.questName,
                    'rewards': result.rewards,
                    'pendingSkillXp': result.pendingSkillXp,
                  }
                : <String, Object?>{'ok': false, 'reason': result.reason},
          ),
          isNull,
        );
      });
    }
  });

  group('quest counter parity', () {
    for (final fixture in loadParityFixtures('quests/counters')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final defeated = applyQuestDefeatProgress(db, save, 'ENM-0001', 2);
        final processed = applyQuestProcessProgress(db, defeated, 'RCP-0001', 3);
        final learned = applyQuestLearnRecipeProgress(db, processed, 'RCP-0003');
        expect(
          checkParity(fixture, {
            'defeated': defeated.toJson(),
            'processed': processed.toJson(),
            'learned': learned.toJson(),
            // The inactive comparison needs a save with no active quests, which
            // the recorded fixture does not carry; an emptied quest list matches.
            'inactive': applyQuestProcessProgress(
              db,
              save.copyWith(quests: const <QuestProgress>[]),
              'RCP-0001',
              1,
            ).toJson(),
            'zeroAmount': applyQuestDefeatProgress(db, save, 'ENM-0001', 0).toJson(),
          }),
          isNull,
        );
      });
    }
  });

  group('submap topology parity', () {
    for (final fixture in loadParityFixtures('world/submaps')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final maps = _stringList(fixture, 'mapIds')
            .map(
              (mapId) => <String, Object?>{
                'mapId': mapId,
                'subMap': isSubMap(db, mapId),
                'displayName': subMapDisplayName(db, mapId),
                'gateway': gatewayLocationIdForSubMap(db, mapId),
              },
            )
            .toList();
        final gateways = const <String>['LOC-0002', 'LOC-0010', 'LOC-0013', 'LOC-0027', 'LOC-0001']
            .map((locationId) {
              final location = db.locations.firstWhereOrNull(
                (row) => row.locationId == locationId,
              )!;
              return <String, Object?>{
                'locationId': locationId,
                'isGateway': isSubMapGateway(location),
                'childMapId': subMapIdForGateway(db, locationId),
                'label': enterSubMapLabel(db, location),
              };
            })
            .toList();
        final locked = db.locations
            .map(
              (location) => <String, Object?>{
                'locationId': location.locationId,
                'requiresUnlock': locationRequiresUnlock(location),
                'unlockedForBase': isLocationUnlocked(save.unlockedLocationIds, location),
              },
            )
            .toList();
        expect(
          checkParity(fixture, {
            'maps': maps,
            'gateways': gateways,
            'locked': locked,
            'unlockOnce': unlockLocation(const <String>[], 'LOC-0026'),
            'unlockTwice': unlockLocation(const <String>['LOC-0026'], 'LOC-0026'),
          }),
          isNull,
        );
      });
    }
  });
}
