import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));
  });

  PlayerSave meadowSave(int startedAt, {required bool fullBag}) {
    var save = createNewSave(db, startedAt).copyWith(currentLocationId: 'LOC-0009');
    save = beginActivitySave(save, 'ACT-0012', isoFromMs(startedAt));
    final generated = generateNextAction(db, save, 'ACT-0012', () => 0, startedAt);
    save = generated!.save.copyWith(unattendedProgressAt: isoFromMs(startedAt));
    if (!fullBag) return save;
    return save.copyWith(
      inventory: [
        for (var index = 0; index < inventorySlotLimit; index += 1)
          InventoryStack(itemId: 'FILL-$index', quantity: 1),
      ],
    );
  }

  test('returns one merged leftBehind list when the bag fills during gathering catch-up', () {
    final startedAt = DateTime.utc(2026).millisecondsSinceEpoch;
    final resolved = resolveUnattendedProgress(
      db,
      meadowSave(startedAt, fullBag: true),
      startedAt + 180000,
      () => 0,
    );
    expect(resolved.gatheringActions, greaterThanOrEqualTo(3));
    expect(resolved.caughtUp, isTrue);
    expect(resolved.leftBehind, isNotEmpty);
    final ids = resolved.leftBehind.map((grant) => grant.itemId).toList();
    expect(ids.toSet().length, ids.length);
    expect(resolved.messages, contains(leftBehindAwayLine));
    expect(resolved.save.inventory, hasLength(inventorySlotLimit));
  });

  test('omits leftBehind when the bag has room', () {
    final startedAt = DateTime.utc(2026).millisecondsSinceEpoch;
    final resolved = resolveUnattendedProgress(
      db,
      meadowSave(startedAt, fullBag: false),
      startedAt + 180000,
      () => 0,
    );
    expect(resolved.gatheringActions, greaterThan(0));
    expect(resolved.leftBehind, isEmpty);
    expect(resolved.toJson().containsKey('leftBehind'), isFalse);
  });

  test('merges leftBehind across a step-limit resume and counts each item once', () {
    final startedAt = DateTime.utc(2026).millisecondsSinceEpoch;
    final save = meadowSave(startedAt, fullBag: true);
    final now = startedAt + 180000;
    final first = resolveUnattendedProgress(db, save, now, () => 0, maxStepsOverride: 4);
    expect(first.caughtUp, isFalse);
    expect(first.gatheringActions, greaterThan(0));
    expect(first.leftBehind, isNotEmpty);
    final again = resolveUnattendedProgress(db, first.save, now, () => 0, maxStepsOverride: 4);
    expect(again.gatheringActions, greaterThan(0));
    final merged = mergeLeftBehind([...first.leftBehind, ...again.leftBehind]);
    final ids = merged.map((grant) => grant.itemId).toList();
    expect(ids.toSet().length, ids.length);
    for (final grant in merged) {
      num firstQty = 0;
      num againQty = 0;
      for (final row in first.leftBehind) {
        if (row.itemId == grant.itemId) firstQty = row.quantity;
      }
      for (final row in again.leftBehind) {
        if (row.itemId == grant.itemId) againQty = row.quantity;
      }
      expect(grant.quantity, firstQty + againQty);
    }
  });
}
