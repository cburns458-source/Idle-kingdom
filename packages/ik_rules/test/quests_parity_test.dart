import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';
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
                : result.failureJson(),
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

  group('quest step latch parity (BUG-01)', () {
    PlayerSave setItemCount(PlayerSave save, String itemId, num quantity) {
      final cleared = save.copyWith(
        inventory: save.inventory.where((stack) => stack.itemId != itemId).toList(),
      );
      return quantity > 0 ? addItemToInventory(cleared, itemId, quantity) : cleared;
    }

    for (final fixture in loadParityFixtures('quests/step-latch')) {
      test(fixture.name, () {
        if (fixture.name == 'handin-skipped-past') {
          final db = databaseOf(fixture);
          final quest = getQuest(db, 'QST-0001')!;
          final base = saveOf(fixture);
          PlayerSave withCounters(Map<String, num> counters) => base.copyWith(
            quests: [
              ...base.quests.where((row) => row.questId != 'QST-0001'),
              QuestProgress(
                questId: 'QST-0001',
                status: 'active',
                progress: counters.values.fold<num>(0, (sum, value) => sum + value),
                counters: counters,
              ),
            ],
          );
          Map<String, Object?> snapshot(String label, PlayerSave save) => <String, Object?>{
            'label': label,
            'currentStep': getCurrentStepId(db, save, quest),
            'complete': isStepComplete(db, save, 'QST-0001', '', 'QSTP-0002'),
            'passed': isStepPassed(db, save, 'QST-0001', 'QSTP-0002'),
            'progress': getQuestProgress(save, 'QST-0001').toJson(),
          };
          expect(
            checkParity(fixture, {
              'cases': [
                snapshot(
                  'partial',
                  withCounters({'step:QSTP-0001': 1, 'handIn:QSTP-0002:ITEM-0058': 4}),
                ),
                snapshot('latched', withCounters({'step:QSTP-0001': 1, 'step:QSTP-0002': 1})),
                snapshot('talk-only', withCounters({'step:QSTP-0001': 1})),
              ],
            }),
            isNull,
          );
          return;
        }
        final db = databaseOf(fixture);
        final quest = getQuest(db, 'QST-0006')!;
        final stages = <Object?>[];
        void record(String label, PlayerSave save) => stages.add(<String, Object?>{
          'label': label,
          'stepIndex': getCurrentStepIndex(db, save, quest),
          'progress': getQuestProgress(save, 'QST-0006').toJson(),
        });
        final base = saveOf(fixture);
        var save = base.copyWith(
          quests: [
            ...base.quests.where((row) => row.questId != 'QST-0006'),
            const QuestProgress(questId: 'QST-0006', status: 'active', progress: 0, counters: {}),
          ],
        );
        PlayerSave showFennel(PlayerSave save, {required bool cooked}) {
          final shown = cooked
              ? chooseDialogue(db, save, 'DLG-0005', 'DNODE-0007', 'DCH-0009')
              : chooseDialogue(db, save, 'DLG-0003', 'DNODE-0004', 'DCH-0005');
          if (!shown.ok) {
            throw StateError('Fennel ${cooked ? 'cooked' : 'raw'} show failed: ${shown.reason}');
          }
          return shown.save;
        }

        save = applyQuestStepUnlocks(db, setItemCount(save, 'ITEM-0025', 5));
        record('hold', save);
        save = showFennel(save, cooked: false);
        record('show', save);
        save = applyQuestVisitProgress(db, save, 'LOC-0023');
        for (var cooked = 1; cooked <= 5; cooked++) {
          save = setItemCount(setItemCount(save, 'ITEM-0025', 5 - cooked), 'ITEM-0058', cooked);
          save = applyQuestProcessProgress(db, save, 'RCP-0001');
          record('cook-$cooked', save);
        }
        save = showFennel(save, cooked: true);
        record('deliver', save);
        save = applyQuestStepUnlocks(db, setItemCount(save, 'ITEM-0058', 0));
        record('sold', save);
        expect(checkParity(fixture, {'stages': stages, 'save': save.toJson()}), isNull);
      });
    }
  });

  group('optional quest step parity', () {
    const questId = 'QST-9301';
    const kitchen = 'LOC-0023';
    const bakedPotato = 'ITEM-0058';
    const bakeRecipe = 'RCP-0001';

    /// Content plus the fixture's test-only quest rows appended.
    GameDatabase patchedDatabase(ParityFixture fixture) {
      final base = asJsonMap(contentDatabaseJson());
      final db = <String, Object?>{...base};
      final patch = fixture.inputField<Map<String, Object?>>('patch');
      for (final entry in patch.entries) {
        db[entry.key] = <Object?>[
          ...(base[entry.key] as List<Object?>? ?? const []),
          ...entry.value! as List<Object?>,
        ];
      }
      return assertGameDatabaseShape(db);
    }

    PlayerSave setItemCount(PlayerSave save, String itemId, num quantity) {
      final cleared = save.copyWith(
        inventory: save.inventory.where((stack) => stack.itemId != itemId).toList(),
      );
      return quantity > 0 ? addItemToInventory(cleared, itemId, quantity) : cleared;
    }

    PlayerSave withQuestActive(PlayerSave save) => save.copyWith(
      quests: [
        ...save.quests.where((row) => row.questId != questId),
        const QuestProgress(questId: questId, status: 'active', progress: 0, counters: {}),
      ],
    );

    Map<String, Object?> stage(GameDatabase db, String label, PlayerSave save) {
      final quest = getQuest(db, questId)!;
      return <String, Object?>{
        'label': label,
        'stepIndex': getCurrentStepIndex(db, save, quest),
        'currentStepId': getCurrentStepId(db, save, quest),
        'allStepsComplete': questAllStepsComplete(db, save, quest),
        'progress': getQuestProgress(save, questId).toJson(),
      };
    }

    Map<String, Object?> turnIn(GameDatabase db, PlayerSave save) {
      final result = completeQuest(db, save, questId, ignoreLocation: true);
      return result.ok
          ? <String, Object?>{
              'ok': true,
              'progress': getQuestProgress(result.save!, questId).toJson(),
            }
          : <String, Object?>{'ok': false, 'reason': result.reason};
    }

    for (final fixture in loadParityFixtures('quests/optional-steps')) {
      test(fixture.name, () {
        if (fixture.name == 'parser') {
          final db = patchedDatabase(fixture);
          final notes = fixture.inputField<List<Object?>>('notes');
          expect(
            checkParity(fixture, {
              'optional': [
                for (final value in notes)
                  isOptionalStep(QuestStepRow(<String, Object?>{'Notes': value})),
              ],
              'steps': [
                for (final step in getQuestSteps(db, questId))
                  <String, Object?>{'stepId': step.stepId, 'optional': isOptionalStep(step)},
              ],
            }),
            isNull,
          );
          return;
        }
        final db = patchedDatabase(fixture);
        final stages = <Object?>[];
        var save = withQuestActive(saveOf(fixture));
        stages.add(stage(db, 'accepted', save));
        if (fixture.name == 'done-midway') {
          save = applyQuestStepUnlocks(db, setItemCount(save, bakedPotato, 10));
          stages.add(stage(db, 'held-before-visit', save));
          save = applyQuestVisitProgress(db, setItemCount(save, bakedPotato, 0), kitchen);
          stages.add(stage(db, 'visited', save));
          save = applyQuestStepUnlocks(db, setItemCount(save, bakedPotato, 10));
          stages.add(stage(db, 'held', save));
          save = applyQuestStepUnlocks(db, setItemCount(save, bakedPotato, 0));
          stages.add(stage(db, 'spent', save));
          save = applyQuestProcessProgress(db, save, bakeRecipe);
          stages.add(stage(db, 'baked', save));
          expect(checkParity(fixture, {'stages': stages, 'turnIn': turnIn(db, save)}), isNull);
          return;
        }
        final turnInEarly = turnIn(db, save);
        save = applyQuestVisitProgress(db, save, kitchen);
        stages.add(stage(db, 'visited', save));
        save = applyQuestProcessProgress(db, save, bakeRecipe);
        stages.add(stage(db, 'baked', save));
        expect(
          checkParity(fixture, {
            'stages': stages,
            'turnInEarly': turnInEarly,
            'turnIn': turnIn(db, save),
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
        final gateways =
            const <String>[
              'LOC-0002',
              'LOC-0010',
              'LOC-0013',
              'LOC-0027',
              'LOC-0039',
              'LOC-0041',
              'LOC-0001',
            ].map((locationId) {
              final location = db.locations.firstWhereOrNull(
                (row) => row.locationId == locationId,
              )!;
              return <String, Object?>{
                'locationId': locationId,
                'isGateway': isSubMapGateway(location),
                'childMapId': subMapIdForGateway(db, locationId),
                'landing': landingLocationIdFor(location),
                'label': enterSubMapLabel(db, location),
              };
            }).toList();
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

  group('miniquest journal parity', () {
    const optionalMiniquest = 'QST-9302';
    const optionalHold = 'QSTP-9312';
    const kitchen = 'LOC-0023';
    const bakeRecipe = 'RCP-0001';

    GameDatabase patchedDatabase(ParityFixture fixture) {
      final base = asJsonMap(contentDatabaseJson());
      final db = <String, Object?>{...base};
      final patch = fixture.inputField<Map<String, Object?>>('patch');
      for (final entry in patch.entries) {
        db[entry.key] = <Object?>[
          ...(base[entry.key] as List<Object?>? ?? const []),
          ...entry.value! as List<Object?>,
        ];
      }
      return assertGameDatabaseShape(db);
    }

    Map<String, Object?> questsSection(GameDatabase db, PlayerSave save) {
      final section = logCompletion(db, save).section('quests')!;
      return <String, Object?>{
        'done': section.done,
        'total': section.total,
        'percent': section.percent,
      };
    }

    Map<String, Object?> journalSnapshot(GameDatabase db, PlayerSave save, String questId) {
      final quest = getQuest(db, questId)!;
      final row = miniQuestJournal(
        db,
        save,
        0,
      ).firstWhereOrNull((entry) => entry.questId == questId);
      return <String, Object?>{
        'inQuestLog': questLog(db, save).any((entry) => entry.questId == questId),
        'journal': row?.toJson(),
        'sharedSteps': [for (final step in questJournalSteps(db, save, quest)) step.toJson()],
        'stepJournal': [for (final step in questStepJournal(db, save, quest)) step.toJson()],
      };
    }

    for (final fixture in loadParityFixtures('quests/miniquest-journal')) {
      test(fixture.name, () {
        if (fixture.name == 'green-thumb') {
          final db = databaseOf(fixture);
          var save = saveOf(fixture).copyWith(
            currentLocationId: 'LOC-0001',
            inventory: const [InventoryStack(itemId: 'ITEM-0324', quantity: 1)],
            quests: const [QuestProgress(questId: 'QST-0006', status: 'completed', progress: 1)],
          );
          save = applyQuestAutoStartOnSeed(db, save);
          final before = questsSection(db, save);
          final miniDone = save.copyWith(
            quests: [
              for (final row in save.quests)
                if (row.questId == 'QST-0011') row.copyWith(status: 'completed') else row,
            ],
          );
          final feastDone = miniDone.copyWith(
            quests: [
              ...miniDone.quests.where((row) => row.questId != 'QST-0001'),
              const QuestProgress(questId: 'QST-0001', status: 'completed', progress: 10),
            ],
          );
          expect(
            checkParity(fixture, {
              'active': journalSnapshot(db, save, 'QST-0011'),
              'completed': journalSnapshot(db, miniDone, 'QST-0011'),
              'completionBefore': before,
              'completionAfterMiniquest': questsSection(db, miniDone),
              'completionAfterFeast': questsSection(db, feastDone),
            }),
            isNull,
          );
          return;
        }

        final db = patchedDatabase(fixture);
        var save = saveOf(fixture).copyWith(
          quests: const [
            QuestProgress(questId: optionalMiniquest, status: 'active', progress: 0, counters: {}),
          ],
        );
        save = applyQuestVisitProgress(db, save, kitchen);
        save = applyQuestProcessProgress(db, save, bakeRecipe);
        final holdStep = db.questSteps.firstWhere((row) => row.stepId == optionalHold);
        final before = questsSection(db, save);
        final finished = completeQuest(db, save, optionalMiniquest, ignoreLocation: true);
        expect(
          checkParity(fixture, {
            'holdOptional': isOptionalStep(holdStep),
            'skipped': journalSnapshot(db, save, optionalMiniquest),
            'completionBefore': before,
            'completed': finished.ok
                ? <String, Object?>{
                    'ok': true,
                    'snapshot': journalSnapshot(db, finished.save!, optionalMiniquest),
                    'completion': questsSection(db, finished.save!),
                  }
                : <String, Object?>{'ok': false, 'reason': finished.reason},
          }),
          isNull,
        );
      });
    }
  });
}
