import 'dart:io';

import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

const _nowMs = 1760486400000; // 2026-10-15T00:00:00.000Z
const _weekMs = 7 * 24 * 60 * 60 * 1000;
const _temple = 'LOC-0036';
const _faithTitleIds = <String>[
  'COS-0013',
  'COS-0014',
  'COS-0015',
  'COS-0016',
  'COS-0017',
  'COS-0018',
  'COS-0019',
];
const _faithNames = <String>[
  'Vaelithra',
  'Khavessa',
  'Nymorai',
  'Drazhkar',
  'Korvethan',
  'Elyndara',
  'Veyrathi',
];
const _theologianNote = 'Have chosen all 7 faiths.';

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

String _versionFromSource(String source, RegExp pattern) {
  final match = pattern.firstMatch(source);
  expect(match, isNotNull, reason: source);
  return match!.group(1)!;
}

void main() {
  late GameDatabase db;

  setUpAll(() {
    db = filterLaunchContent(assertGameDatabaseShape(contentDatabaseJson()));
  });

  PlayerSave withEquippedFaithTitle({int faithIndex = 0}) {
    final faith = religions(db)[faithIndex];
    final titleId = faith.titleCosmeticId!;
    final first = chooseReligion(
      db,
      _atTemple(createNewSave(db, _nowMs)),
      faith.religionId,
      _nowMs,
    );
    expect(first.ok, isTrue, reason: first.reason);
    final granted = grantCosmetic(first.save!, titleId).save;
    final worn = equipCosmetic(db, granted, titleCosmeticSlotId, titleId);
    expect(worn.ok, isTrue);
    return worn.save!.copyWith(characterName: 'Tester');
  }

  test('lists exactly the seven approved faith names', () {
    final names = [for (final faith in religions(db)) faith.displayName];
    expect(names, hasLength(7));
    expect(names.toSet(), _faithNames.toSet());
  });

  test('marks COS-0013..COS-0019 as prefix titles and keeps The Undying a suffix', () {
    for (final cosmeticId in _faithTitleIds) {
      final cosmetic = db.cosmetics.firstWhere((row) => row.cosmeticId == cosmeticId);
      expect(cosmetic.raw['Title Placement'], 'prefix');
      expect(cosmetic.titlePlacement, 'prefix');
      expect(titlePlacementForCosmetic(cosmetic), TitlePlacement.prefix);
      expect(titleForCosmeticId(db, cosmeticId)?.placement, TitlePlacement.prefix);
    }
    final undying = db.cosmetics.firstWhere((row) => row.cosmeticId == starterTitleCosmeticId);
    expect(undying.raw['Title Placement'], 'suffix');
    expect(titlePlacementForCosmetic(undying), TitlePlacement.suffix);
    expect(titleForCosmeticId(db, starterTitleCosmeticId)?.text, 'The Undying');
    expect(titleForCosmeticId(db, starterTitleCosmeticId)?.placement, TitlePlacement.suffix);
  });

  test('shows the equipped faith title before the name and drops it when unequipped, locked, or the faith changes', () {
    final save = withEquippedFaithTitle();
    final title = titleForSave(save, db);
    expect(title?.placement, TitlePlacement.prefix);
    expect(title?.text, isNotEmpty);
    expect(nameWithTitle('Tester', title), '${title!.text} Tester');

    final unequipped = equipCosmetic(db, save, titleCosmeticSlotId, null);
    expect(unequipped.ok, isTrue);
    expect(titleForSave(unequipped.save!, db), isNull);
    expect(nameWithTitle('Tester', titleForSave(unequipped.save!, db)), 'Tester');

    final otherFaith = religions(db)[1];
    final locked = save.copyWith(religionId: otherFaith.religionId);
    expect(isFaithTitleLocked(db, locked, save.cosmetics.equipped[titleCosmeticSlotId]), isTrue);

    final switched = chooseReligion(
      db,
      save.copyWith(gold: 100000),
      otherFaith.religionId,
      _nowMs + _weekMs,
    );
    expect(switched.ok, isTrue, reason: switched.reason);
    expect(switched.save!.cosmetics.equipped[titleCosmeticSlotId], isNull);
    expect(isFaithTitleLocked(db, switched.save!, religions(db).first.titleCosmeticId), isTrue);
    expect(titleForSave(switched.save!, db), isNull);
  });

  test('keeps the equipped faith title after a world death', () {
    final save = withEquippedFaithTitle();
    final before = titleForSave(save, db);
    expect(before?.placement, TitlePlacement.prefix);
    final dead = applyCombatDefeat(db, save, _nowMs);
    expect(dead.hasEverDied, isTrue);
    expect(titleForSave(dead, db)?.text, before?.text);
    expect(titleForSave(dead, db)?.placement, before?.placement);
    expect(nameWithTitle('Tester', titleForSave(dead, db)), '${before!.text} Tester');
  });

  test('resolves a published titleCosmeticId and writes nothing for a missing or unknown id', () {
    final save = withEquippedFaithTitle();
    final titleId = religions(db).first.titleCosmeticId;
    expect(equippedTitleCosmeticId(save), titleId);
    expect(titleForCosmeticId(db, titleId)?.placement, TitlePlacement.prefix);
    expect(
      nameWithTitle('Hero', titleForCosmeticId(db, titleId)),
      startsWith(titleForCosmeticId(db, titleId)!.text),
    );
    expect(titleForCosmeticId(db, null), isNull);
    expect(titleForCosmeticId(db, ''), isNull);
    expect(titleForCosmeticId(db, 'COS-9999'), isNull);
    expect(nameWithTitle('Mira', titleForCosmeticId(db, 'COS-9999')), 'Mira');
    expect(nameWithTitle('Mira', titleForCosmeticId(db, null)), 'Mira');
  });

  test('uses Theologian deed text exactly "Have chosen all 7 faiths."', () {
    final row = db.achievements.singleWhere((entry) => entry['Achievement ID'] == 'ACH-0051');
    expect(row['Display Name'], 'Theologian');
    expect(row['Notes'], _theologianNote);
    expect(row['Notes'], isNot(contains('granted once')));
    expect(row['Notes'], isNot(contains('Survives reload')));

    final log = achievementLog(
      db,
      createNewSave(db, _nowMs),
    ).singleWhere((entry) => entry.achievementId == 'ACH-0051');
    expect(log.note, _theologianNote);
    expect(log.note.toLowerCase(), isNot(contains('granted once')));
    expect(log.note, isNot(contains('Survives reload')));
  });

  test('keeps databaseContentVersion in lockstep with the TypeScript loader', () {
    final root = parityRepoRoot();
    final tsSource = File('${root.path}/src/game/data/loadDatabase.ts').readAsStringSync();
    final dartSource = File('${root.path}/packages/ik_content/lib/src/load_database.dart')
        .readAsStringSync();
    final tsVersion = _versionFromSource(
      tsSource,
      RegExp(r"export const DATABASE_CONTENT_VERSION = '([^']+)'"),
    );
    final dartVersion = _versionFromSource(
      dartSource,
      RegExp(r"const String databaseContentVersion = '([^']+)';"),
    );
    expect(tsVersion, databaseContentVersion);
    expect(dartVersion, databaseContentVersion);
    expect(tsVersion, dartVersion);
  });
}
