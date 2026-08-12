import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// `null` reads back from the fixture as an absent enchant target.
String? _enchantTarget(ParityFixture fixture) => fixture.inputMap['target'] as String?;

Map<String, Object?> _knowledgeJson(ProjectKnowledge knowledge) {
  return knowledge.ok
      ? <String, Object?>{'ok': true}
      : <String, Object?>{'ok': false, 'npcId': knowledge.npcId, 'npcName': knowledge.npcName};
}

void main() {
  group('project row parity', () {
    for (final fixture in loadParityFixtures('projects/rows')) {
      test(fixture.name, () {
        final rows = databaseOf(fixture).projects
            .map(
              (project) => <String, Object?>{
                'projectId': project.projectId,
                'complete': isCompleteProject(project),
                'inputs': projectInputs(project).map((input) => input.toJson()).toList(),
                'skills': projectSkillRequirements(project)
                    .map((requirement) => requirement.toJson())
                    .toList(),
              },
            )
            .toList();
        expect(checkParity(fixture, {'rows': rows}), isNull);
      });
    }
  });

  group('project gate parity', () {
    for (final fixture in loadParityFixtures('projects/gates')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final rows = db.projects
            .where(isCompleteProject)
            .map(
              (project) => <String, Object?>{
                'projectId': project.projectId,
                'skills': meetsProjectSkills(save, project),
                'knowledge': meetsProjectKnowledge(db, save, project),
                'unmet': unmetProjectSkillRequirements(
                  db,
                  save,
                  project,
                ).map((entry) => entry.toJson()).toList(),
                'materialMax': maxProjectsFromMaterials(save, project),
                'goldMax': maxProjectsFromGold(save, project),
                'quantityMax': maxProjectQuantity(save, project),
              },
            )
            .toList();
        expect(checkParity(fixture, {'rows': rows}), isNull);
      });
    }
  });

  group('project facility parity', () {
    for (final fixture in loadParityFixtures('projects/facility')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final locationIds = fixture
            .inputField<List<Object?>>('locations')
            .map((value) => value! as String)
            .toList();
        final byFacility =
            const <String>['FAC-0003', 'FAC-0005', 'FAC-0008', 'FAC-0013', 'FAC-0016']
                .map(
                  (facilityId) => <String, Object?>{
                    'facilityId': facilityId,
                    'all': projectsForFacility(db, facilityId).map((row) => row.projectId).toList(),
                    'smithingOnly': projectsForFacility(
                      db,
                      facilityId,
                      'SKL-0011',
                    ).map((row) => row.projectId).toList(),
                  },
                )
                .toList();
        final stations = locationIds
            .map(
              (locationId) => <String, Object?>{
                'locationId': locationId,
                'stations': specialProductionStationsAt(db, locationId)
                    .map(
                      (station) => <String, Object?>{
                        'facilityId': station.facility.facilityId,
                        'skillId': station.skillId,
                        'skillName': station.skillName,
                        'label': station.label,
                      },
                    )
                    .toList(),
              },
            )
            .toList();
        expect(
          checkParity(fixture, {
            'byFacility': byFacility,
            'stations': stations,
            'labels': const <String>[
              'SKL-0011',
              'SKL-0012',
              'SKL-0013',
              'SKL-0007',
            ].map((skillId) => specialProductionStationLabel(skillId, 'Fallback')).toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('project validation parity', () {
    for (final fixture in loadParityFixtures('projects/validate')) {
      test(fixture.name, () {
        final validation = validateProjectCompletion(
          databaseOf(fixture),
          saveOf(fixture),
          fixture.inputField<String>('projectId'),
          fixture.inputField<num>('quantity'),
          _enchantTarget(fixture),
        );
        expect(
          checkParity(
            fixture,
            validation.ok
                ? <String, Object?>{'ok': true}
                : <String, Object?>{'ok': false, 'reason': validation.reason},
          ),
          isNull,
        );
      });
    }
  });

  group('project completion parity', () {
    for (final fixture in loadParityFixtures('projects/complete')) {
      test(fixture.name, () {
        final result = completeSpecialProject(
          databaseOf(fixture),
          saveOf(fixture),
          fixture.inputField<String>('projectId'),
          fixture.inputField<num>('quantity'),
          enchantTargetId: _enchantTarget(fixture),
          nowMs: fixture.inputField<num>('nowMs'),
        );
        expect(
          checkParity(
            fixture,
            result.ok
                ? <String, Object?>{
                    'ok': true,
                    'save': result.save!.toJson(),
                    'outputLabel': result.outputLabel,
                    'outputQty': result.outputQty,
                    'xpGained': result.xpGained,
                    'goldSpent': result.goldSpent,
                  }
                : <String, Object?>{'ok': false, 'reason': result.reason},
          ),
          isNull,
        );
      });
    }
  });

  group('npc knowledge parity', () {
    const knowledgeSkills = <String>['SKL-0011', 'SKL-0012', 'SKL-0013', 'SKL-0007'];

    for (final fixture in loadParityFixtures('npcs/knowledge')) {
      if (fixture.name != 'lookups') continue;
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final npcIds = fixture
            .inputField<List<Object?>>('npcIds')
            .map((value) => value! as String)
            .toList();
        final byLocation = fixture
            .inputField<List<Object?>>('locations')
            .map((value) => value! as String)
            .map(
              (locationId) => <String, Object?>{
                'locationId': locationId,
                'npcIds': npcsAtLocation(db, locationId).map((npc) => npc.npcId).toList(),
                'shopIds': npcsAtLocation(
                  db,
                  locationId,
                ).map((npc) => shopIdForMerchant(db, npc)).toList(),
              },
            )
            .toList();
        expect(
          checkParity(fixture, {
            'byLocation': byLocation,
            'mentorForSkill': knowledgeSkills.map(knowledgeNpcForSkill).toList(),
            'knows': npcIds.map((npcId) => hasNpcKnowledge(save, npcId)).toList(),
            'projectKnowledge': knowledgeSkills
                .map((skillId) => _knowledgeJson(hasProjectKnowledge(db, save, skillId)))
                .toList(),
          }),
          isNull,
        );
      });
    }

    for (final fixture in loadParityFixtures('npcs/knowledge')) {
      if (fixture.name != 'unlock') continue;
      test(fixture.name, () {
        final base = saveOf(fixture);
        final results = fixture
            .inputField<List<Object?>>('npcIds')
            .map((value) => value! as String)
            .map((npcId) {
              final first = unlockNpcKnowledge(base, npcId);
              if (!first.ok) {
                return <String, Object?>{'npcId': npcId, 'ok': false, 'reason': first.reason};
              }
              final again = unlockNpcKnowledge(first.save!, npcId);
              return <String, Object?>{
                'npcId': npcId,
                'ok': true,
                'alreadyHad': first.alreadyHad,
                'save': first.save!.toJson(),
                'repeatAlreadyHad': again.ok ? again.alreadyHad : null,
              };
            })
            .toList();
        expect(checkParity(fixture, {'results': results}), isNull);
      });
    }
  });
}
