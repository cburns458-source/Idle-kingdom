import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));
  });

  test('grantBook unlocks into the Library and is idempotent', () {
    final save = createNewSave(db, 1);
    expect(save.unlockedBookIds, isEmpty);

    final first = grantBook(save, 'BOOK-0001');
    expect(first.granted, isTrue);
    expect(first.isFirstEver, isTrue);
    expect(first.save.unlockedBookIds, <String>['BOOK-0001']);
    expect(isBookUnlocked(first.save, 'BOOK-0001'), isTrue);

    final again = grantBook(first.save, 'BOOK-0001');
    expect(again.granted, isFalse);
    expect(again.save.unlockedBookIds, <String>['BOOK-0001']);

    final second = grantBook(first.save, 'BOOK-0002');
    expect(second.granted, isTrue);
    expect(second.isFirstEver, isFalse);
    expect(libraryBookRows(db, second.save).map((row) => row.bookId), <String>[
      'BOOK-0002',
      'BOOK-0001',
    ]);
  });

  test('bookUnlockNotice names the book and hints on the first ever unlock', () {
    final first = bookUnlockNotice(db, 'BOOK-0001', true);
    expect(first, isNotNull);
    expect(first!.name, "Newcomer's Guide");
    expect(first.hint, libraryHint);

    final later = bookUnlockNotice(db, 'BOOK-0002', false);
    expect(later, isNotNull);
    expect(later!.name, "Botanist's Guide");
    expect(later.hint, isNull);
  });

  test('quest notes wire RewardBook ids for Getting Started and Green Thumb', () {
    final started = parseStructuredObjectives(getQuest(db, 'QST-0006')!);
    expect(started.rewardBookIds, <String>['BOOK-0001']);
    final green = parseStructuredObjectives(getQuest(db, 'QST-0011')!);
    expect(green.rewardBookIds, <String>['BOOK-0002']);
    expect(getQuest(db, 'QST-0011')!['Display Name'], 'Green Thumb');
  });

  test('Main Hall kitchen stays locked until Grand Feast is started', () {
    final save = createNewSave(db, 1);
    expect(mainHallKitchenLocked(db, save, mainHallCookActivityId), isTrue);
    final start = validateActivityStart(db, save, mainHallCookActivityId);
    expect(start.ok, isFalse);
    expect(start.reason, mainHallKitchenLockedMessage);
  });

  test('Fight the goblins activity card reports Might', () {
    final save = createNewSave(db, 1);
    expect(skillIdsForActivity(db, save, 'ACT-0002'), contains(combatDisplaySkillId));
  });
}
