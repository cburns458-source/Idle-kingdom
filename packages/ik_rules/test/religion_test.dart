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

  test('reads exponential change-cost settings from Config', () {
    expect(
      db.config.firstWhere((entry) => entry.raw['Key'] == religionChangeGoldBaseKey).raw['Value'],
      1000,
    );
    expect(
      db.config.firstWhere((entry) => entry.raw['Key'] == religionChangeGoldGrowthKey).raw['Value'],
      1.0043561527973446,
    );
    expect(
      db.config.firstWhere((entry) => entry.raw['Key'] == religionChangeGoldCapKey).raw['Value'],
      50000,
    );
  });

  test('faith title cosmetics are prefix titles', () {
    for (final faith in religions(db)) {
      final cosmetic = db.cosmetics.firstWhere((row) => row.cosmeticId == faith.titleCosmeticId);
      expect(cosmetic.raw['Title Placement'], 'prefix');
      expect(titlePlacementForCosmetic(cosmetic), TitlePlacement.prefix);
    }
    final undying = db.cosmetics.firstWhere((row) => row.cosmeticId == starterTitleCosmeticId);
    expect(undying.raw['Title Placement'], 'suffix');
    expect(titlePlacementForCosmetic(undying), TitlePlacement.suffix);
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

  test('costs gold on a later change from the shared exponential setting, at level boundaries', () {
    final first = chooseReligion(
      db,
      _atTemple(createNewSave(db, _nowMs), 100),
      _woodcuttingFaith,
      _nowMs,
    );
    expect(first.ok, isTrue);
    final following = first.save!;
    expect(religionChangeGoldCost(db, following), 1000);
    expect(religionChangeGoldCost(db, _withTotalLevel(following, 101)), 1000);
    expect(religionChangeGoldCost(db, _withTotalLevel(following, 250)), 1900);
    expect(religionChangeGoldCost(db, _withTotalLevel(following, 500)), 5650);
    expect(religionChangeGoldCost(db, _withTotalLevel(following, 750)), 16850);
    expect(religionChangeGoldCost(db, _withTotalLevel(following, 999)), 49750);
    expect(religionChangeGoldCost(db, _withTotalLevel(following, 1000)), 50000);
    expect(religionChangeGoldCost(db, _withTotalLevel(following, 1001)), 50000);

    final changed = chooseReligion(
      db,
      _withTotalLevel(following, 101).copyWith(gold: 1000),
      _huntingFaith,
      _nowMs + _weekMs,
    );
    expect(changed.ok, isTrue);
    expect(changed.goldCost, 1000);
    expect(changed.save!.gold, 0);
  });
}
