import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

const _nowMs = 1760486400000; // 2026-10-15T00:00:00.000Z
const _weekMs = 7 * 24 * 60 * 60 * 1000;
const _temple = 'LOC-0036';
const _woodcuttingFaith = 'REL-0001';
const _huntingFaith = 'REL-0002';

PlayerSave _withTotalLevel(PlayerSave save, num target) {
  final bump = target - totalLevel(save);
  if (bump <= 0) return save;
  final first = save.skills.first;
  return save.copyWith(
    skills: <SkillProgress>[
      first.copyWith(level: first.level + bump),
      ...save.skills.skip(1),
    ],
  );
}

PlayerSave _atTemple(PlayerSave save, [num level = 100]) {
  return _withTotalLevel(save, level).copyWith(currentLocationId: _temple, gold: 100000);
}

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));
  });

  test('reads the multiplier and rounding step from one Config value', () {
    final row = db.config.firstWhere((entry) => entry.raw['Key'] == religionChangeGoldKey);
    expect(row.raw['Value'], '10:50');
    final settings = religionChangeGoldSettings(db);
    expect(settings.multiplier, 10);
    expect(settings.roundingStep, 50);
  });

  test('the first pick is free', () {
    final ready = _atTemple(createNewSave(db, _nowMs), 100);
    final goldBefore = ready.gold;
    final first = chooseReligion(db, ready, _woodcuttingFaith, _nowMs);
    expect(first.ok, isTrue);
    expect(first.goldCost, 0);
    expect(first.save!.gold, goldBefore);
    expect(religionChangeGoldCost(db, ready), 0);
  });

  test('costs 1000, 2500, 5000 and 10000 gold at total levels 100, 250, 500 and 1000', () {
    final first = chooseReligion(
      db,
      _atTemple(createNewSave(db, _nowMs), 100),
      _woodcuttingFaith,
      _nowMs,
    );
    expect(first.ok, isTrue);
    final following = first.save!;
    expect(religionChangeGoldCost(db, following), 1000);
    expect(religionChangeGoldCost(db, _withTotalLevel(following, 250)), 2500);
    expect(religionChangeGoldCost(db, _withTotalLevel(following, 500)), 5000);
    expect(religionChangeGoldCost(db, _withTotalLevel(following, 1000)), 10000);

    final changed = chooseReligion(
      db,
      _withTotalLevel(following, 250).copyWith(gold: 2500),
      _huntingFaith,
      _nowMs + _weekMs,
    );
    expect(changed.ok, isTrue);
    expect(changed.goldCost, 2500);
    expect(changed.save!.gold, 0);
  });

  test('rounds 104 down to 1000 gold and 105 up to 1050 gold', () {
    final first = chooseReligion(
      db,
      _atTemple(createNewSave(db, _nowMs), 100),
      _woodcuttingFaith,
      _nowMs,
    );
    expect(first.ok, isTrue);
    final following = first.save!;
    expect(religionChangeGoldCost(db, _withTotalLevel(following, 104)), 1000);
    expect(religionChangeGoldCost(db, _withTotalLevel(following, 105)), 1050);
  });
}
