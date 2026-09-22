import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = assertGameDatabaseShape(contentDatabaseJson());
  });

  test('resets selected quests and intro flags only', () {
    var save = createNewSave(db, 0).copyWith(
      hasSeenFennelIntro: true,
      hasSeenWardrobeIntro: true,
      quests: const [
        QuestProgress(questId: 'QST-0004', status: 'completed', progress: 3),
        QuestProgress(questId: 'QST-0006', status: 'active', progress: 1),
      ],
      miniquestCompletedAt: const <String, String>{'QST-0003': '2026-01-01T00:00:00.000Z'},
    );

    save = resetQuestProgress(save, const ['QST-0004']);
    expect(getQuestProgress(save, 'QST-0004').status, 'inactive');
    expect(getQuestProgress(save, 'QST-0006').status, 'active');
    expect(save.miniquestCompletedAt, containsPair('QST-0003', '2026-01-01T00:00:00.000Z'));

    save = resetQuestProgress(save, const ['QST-0003']);
    expect(save.miniquestCompletedAt.containsKey('QST-0003'), isFalse);

    save = resetIntroFlags(save, fennel: true);
    expect(save.hasSeenFennelIntro, isFalse);
    expect(save.hasSeenWardrobeIntro, isTrue);
  });
}
