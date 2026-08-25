import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/content/asset_paths.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

/// The audit that catches art the bundle would be missing.
///
/// Every path the client asks for is derived from the database, so the only way
/// to know a file is there is to walk the content and look. A missing icon is
/// otherwise invisible until the screen that needs it is opened on a device.
void main() {
  late LoadedDatabase database;
  late GameDatabase db;

  setUpAll(() {
    database = loadDatabaseFromRepo();
    db = database.launch;
  });

  /// `content/` is the symlink next to the pubspec, which is also the bundle
  /// root, so a bundle key doubles as a path from the client's directory.
  bool bundled(String key) => File(key).existsSync();

  void expectBundled(String key, String what) {
    expect(bundled(key), isTrue, reason: '$what has no art at $key');
  }

  test('every declared asset directory exists and holds files', () {
    for (final entry in declaredAssets()) {
      if (!entry.endsWith('/')) {
        expectBundled(entry, 'the declared asset $entry');
        continue;
      }
      final directory = Directory(entry);
      expect(directory.existsSync(), isTrue, reason: '$entry is declared but missing');
      final files = directory.listSync().whereType<File>();
      expect(files, isNotEmpty, reason: '$entry is declared but empty');
    }
  });

  test('every directory holding art is declared', () {
    final declared = declaredAssets().toSet();
    for (final directory in Directory('content/assets').listSync(recursive: true)) {
      if (directory is! Directory) continue;
      final holdsArt = directory.listSync().whereType<File>().isNotEmpty;
      if (!holdsArt) continue;
      final key = '${directory.path}/';
      expect(
        declared.contains(key),
        isTrue,
        reason: 'add $key to the assets list in pubspec.yaml, or the bundle will not carry it',
      );
    }
  });

  test('every item resolves to an icon', () {
    for (final item in db.items) {
      expectBundled(itemIconPath(item), 'item ${item.itemId} (${item.displayName})');
    }
    expectBundled(itemIconPath(null), 'an unknown item');
    expectBundled(goldIconPath(), 'gold');
    expectBundled(uiMapAssetPath(), 'the map button');
  });

  test('every item has a unique Icon Asset Key matching its Internal Key', () {
    final keys = <String>{};
    for (final item in db.items) {
      expect(item.iconAssetKey, item.internalKey, reason: '${item.itemId} (${item.displayName})');
      expect(
        keys.add(item.iconAssetKey!),
        isTrue,
        reason: '${item.itemId} reused Icon Asset Key ${item.iconAssetKey}',
      );
      expectBundled(itemIconPath(item), 'item ${item.itemId} (${item.displayName})');
    }
  });

  test('every skill resolves to an icon', () {
    for (final skill in db.skills) {
      expectBundled(skillIconPath(skill), 'skill ${skill.skillId} (${skill.displayName})');
    }
    expectBundled(skillIconPath(null), 'an unknown skill');
  });

  test('every equipment slot resolves to an icon', () {
    for (final slot in db.equipmentSlots) {
      expectBundled(slotIconPath(slot.slotId), 'slot ${slot.slotId}');
    }
  });

  test('every map and location has its own art', () {
    // The fallbacks exist so an unmapped id cannot crash a screen, but an id the
    // tables do not know would quietly show another place, so pin them here.
    for (final map in db.maps) {
      expect(
        hasMapArt(map.mapId),
        isTrue,
        reason: 'map ${map.mapId} (${map.displayName}) is not in the art table',
      );
      expectBundled(mapAssetPath(map.mapId), 'map ${map.mapId}');
    }
    for (final location in db.locations) {
      // A horizon gateway is browsed on the map and never entered, so it has no
      // background of its own to be missing.
      if (isFutureHorizonLocation(location.locationId)) continue;
      expect(
        hasLocationArt(location.locationId),
        isTrue,
        reason: 'location ${location.locationId} (${location.displayName}) is not in the art table',
      );
      expectBundled(locationAssetPath(location.locationId), 'location ${location.locationId}');
    }
  });

  test('every enemy has its own art', () {
    for (final enemy in db.enemies) {
      expect(
        hasEnemyArt(enemy.enemyId),
        isTrue,
        reason: 'enemy ${enemy.enemyId} (${enemy.displayName}) is not in the art table',
      );
      expectBundled(enemyAssetPath(enemy.enemyId), 'enemy ${enemy.enemyId}');
    }
  });

  test('every gathering action and production station has a scene', () {
    for (final action in db.actions) {
      if (action.category != 'Gathering') continue;
      expect(
        hasActionArt(action.actionId),
        isTrue,
        reason: 'action ${action.actionId} (${action.displayName}) is not in the art table',
      );
      expectBundled(actionAssetPath(action.actionId), 'action ${action.actionId}');
    }
    for (final facility in db.facilities) {
      expectBundled(workstationAssetPath(facility.facilityId), 'facility ${facility.facilityId}');
    }
    expectBundled(workstationAssetPath(null), 'a station without a facility');
  });

  test('every critter and appearance choice has a sprite', () {
    for (final critter in critterDefs) {
      expectBundled(critterAssetPath(critter.internalKey), 'critter ${critter.id}');
    }
    for (final race in db.races.where((row) => row.releasePhase == 'Launch')) {
      for (final option in appearanceOptions(db, AppearanceCategory.genderPresentation)) {
        final optionId = option.raw['Appearance Option ID'] as String;
        final appearance = withAppearanceOption(
          defaultAppearance(db),
          AppearanceCategory.genderPresentation,
          optionId,
        );
        expectBundled(
          playerAssetPath(appearance, raceId: race.raceId),
          'race ${race.raceId} appearance $optionId',
        );
      }
    }
    expectBundled(playerAssetPath(null), 'a player without an appearance');
    expectBundled(avatarFrameAssetPath(), 'the HUD portrait frame');
  });
}

/// The asset entries `pubspec.yaml` declares, in the order they are listed.
///
/// Parsed rather than hardcoded, because the point of the audit is to catch a
/// directory that was added to the repo and forgotten here.
List<String> declaredAssets() {
  final lines = File('pubspec.yaml').readAsLinesSync();
  final start = lines.indexWhere((line) => line.trimRight() == '  assets:');
  expect(start, isNot(-1), reason: 'pubspec.yaml no longer declares an assets list');
  final entries = <String>[];
  for (final line in lines.skip(start + 1)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    if (!trimmed.startsWith('- ')) break;
    entries.add(trimmed.substring(2).trim());
  }
  return entries;
}
