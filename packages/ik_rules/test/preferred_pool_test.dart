import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

GameDatabase _db() => filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));

const _woodcutting = 'SKL-0006';
const _rareWood = 'POOL-0021';
const _searchRareWood = 'ACT-0026';
const _cedar = 'ACN-0046';
const _poplar = 'ACN-0048';
const _cutPoplar = 'ACT-0032';

PlayerSave _withWoodcutting(PlayerSave save, num level) {
  return save.copyWith(
    skills: [
      for (final skill in save.skills)
        if (skill.skillId == _woodcutting) skill.copyWith(level: level) else skill,
    ],
  );
}

List<String> _ids(List<PoolCandidate> entries) {
  return [for (final pair in entries) pair.action.actionId];
}

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = _db();
  });

  test('rare wood prefers cedar until woodcutting 30', () {
    final starter = createNewSave(db, 0);
    expect(_ids(preferredPoolEntries(db, starter, _rareWood)), [_cedar]);
    expect(_ids(eligiblePoolEntries(db, _rareWood)), [_cedar, _poplar]);

    final ready = _withWoodcutting(starter, 30);
    expect(_ids(preferredPoolEntries(db, ready, _rareWood)), [_cedar, _poplar]);
  });

  test('searching for rare wood rolls cedar for a level 1 woodcutter', () {
    final save = createNewSave(db, 0).copyWith(currentLocationId: 'LOC-0008');
    final low = generateNextAction(db, save, _searchRareWood, () => 0, 0);
    final high = generateNextAction(db, save, _searchRareWood, () => 0.999, 0);
    expect(low!.action.actionId, _cedar);
    expect(high!.action.actionId, _cedar);
    expect(high.save.actionDurationMs, 15000);
  });

  test('searching for rare wood can roll poplar at woodcutting 30', () {
    final save = _withWoodcutting(createNewSave(db, 0).copyWith(currentLocationId: 'LOC-0008'), 30);
    expect(generateNextAction(db, save, _searchRareWood, () => 0, 0)!.action.actionId, _cedar);
    expect(generateNextAction(db, save, _searchRareWood, () => 0.999, 0)!.action.actionId, _poplar);
  });

  test('a lone high-proficiency pool still rolls when nothing is ready', () {
    final save = createNewSave(db, 0).copyWith(currentLocationId: 'LOC-0031');
    expect(_ids(preferredPoolEntries(db, save, 'POOL-0023')), [_poplar]);
    expect(generateNextAction(db, save, _cutPoplar, () => 0, 0)!.action.actionId, _poplar);
  });
}
