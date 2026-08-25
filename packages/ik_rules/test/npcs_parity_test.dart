import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

List<String> _idsOf(ParityFixture fixture, String key) {
  return fixture.inputField<List<Object?>>(key).map((value) => value! as String).toList();
}

Object? _actionJson(NpcActionResult? result) => result?.toJson();

void main() {
  group('npc conversation parity', () {
    for (final fixture in loadParityFixtures('npcs/conversation')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);

        if (fixture.name == 'merchant-tip') {
          final first = takeMerchantTip(db, save, 'NPC-0007');
          expect(
            checkParity(fixture, {
              'first': first == null
                  ? null
                  : <String, Object?>{'save': first.save!.toJson(), 'message': first.message},
              'again': first == null
                  ? null
                  : _actionJson(takeMerchantTip(db, first.save!, 'NPC-0007')),
              'otherMerchant': _actionJson(takeMerchantTip(db, save, 'NPC-0008')),
            }),
            isNull,
          );
          return;
        }

        if (fixture.name == 'mentor-unlock') {
          final results = _idsOf(fixture, 'npcIds').map((npcId) {
            final result = learnMentorProjects(db, save, npcId);
            return result.ok
                ? <String, Object?>{
                    'npcId': npcId,
                    'ok': true,
                    'message': result.message,
                    'save': result.save!.toJson(),
                  }
                : <String, Object?>{'npcId': npcId, 'ok': false, 'reason': result.reason};
          }).toList();
          expect(checkParity(fixture, {'results': results}), isNull);
          return;
        }

        if (fixture.name.startsWith('accept-')) {
          final results = _idsOf(fixture, 'questIds').map((questId) {
            final result = acceptQuestFromNpc(db, save, questId);
            return result.ok
                ? <String, Object?>{
                    'questId': questId,
                    'ok': true,
                    'message': result.message,
                    'save': result.save!.toJson(),
                  }
                : <String, Object?>{'questId': questId, 'ok': false, 'reason': result.reason};
          }).toList();
          expect(checkParity(fixture, {'results': results}), isNull);
          return;
        }

        final conversations = _idsOf(fixture, 'npcIds').map((npcId) {
          final npc = db.npcs.firstWhere((row) => row.raw['NPC ID'] == npcId);
          return npcConversation(
            db,
            save,
            npc,
            DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
          ).toJson();
        }).toList();
        expect(
          checkParity(fixture, {
            'conversations': conversations,
            'pitchLines': const <String>[
              'QST-0001',
              'QST-0002',
              'QST-9999',
            ].map((questId) => questPitchLine(db, questId)).toList(),
            'mentorSkills': const <String>[
              'NPC-0002',
              'NPC-0003',
              'NPC-0004',
              'NPC-0007',
              'NPC-9999',
            ].map(skillForKnowledgeNpc).toList(),
          }),
          isNull,
        );
      });
    }
  });
}
