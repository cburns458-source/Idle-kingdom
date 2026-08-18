import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

List<String> _stringList(ParityFixture fixture, String key) {
  return fixture.inputField<List<Object?>>(key).map((value) => value! as String).toList();
}

/// `mulberry32(seed)`, or the pinned zero generator the always-spawn case uses.
RandomFn _randomOf(ParityFixture fixture) {
  final seed = fixture.inputMap['seed'];
  if (seed == null) return () => 0;
  return Mulberry32((seed as num).toInt()).asFunction;
}

BountyDefinition _renamed(BountyDefinition bounty, String id) {
  return BountyDefinition(
    id: id,
    title: bounty.title,
    description: bounty.description,
    kind: bounty.kind,
    targetId: bounty.targetId,
    amount: bounty.amount,
    rewardGold: bounty.rewardGold,
    firstPlaceBonusGold: bounty.firstPlaceBonusGold,
  );
}

void main() {
  group('critter catalog parity', () {
    for (final fixture in loadParityFixtures('critters/catalog')) {
      test(fixture.name, () {
        expect(
          checkParity(fixture, {
            'defs': critterDefs.map((critter) => critter.toJson()).toList(),
            'byLocation': _stringList(fixture, 'locations')
                .map(
                  (locationId) => <String, Object?>{
                    'locationId': locationId,
                    'critterId': critterForLocation(locationId)?.id,
                  },
                )
                .toList(),
            'byId': const <String>['CRT-0001', 'CRT-0004', 'CRT-9999']
                .map(
                  (critterId) => <String, Object?>{
                    'critterId': critterId,
                    'internalKey': getCritter(critterId)?.internalKey,
                  },
                )
                .toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('critter collection parity', () {
    for (final fixture in loadParityFixtures('critters/collection')) {
      test(fixture.name, () {
        final save = saveOf(fixture);
        final nowMs = fixture.inputField<num>('nowMs');
        final locations = _stringList(fixture, 'locations');
        expect(
          checkParity(fixture, {
            'counts': _stringList(
              fixture,
              'critterIds',
            ).map((critterId) => collectionCount(save, critterId)).toList(),
            'spawns': locations
                .map(
                  (locationId) => <String, Object?>{
                    'locationId': locationId,
                    'spawn': activeSpawnAtLocation(save, locationId)?.toJson(),
                  },
                )
                .toList(),
            'collected': locations.map((locationId) {
              final result = collectCritter(save, locationId);
              return <String, Object?>{
                'locationId': locationId,
                if (result.ok) ...<String, Object?>{
                  'ok': true,
                  'save': result.save!.toJson(),
                  'critterId': result.critter!.id,
                  'count': result.count,
                  'message': result.message,
                } else ...<String, Object?>{'ok': false, 'reason': result.reason},
              };
            }).toList(),
            'forced': locations.map((locationId) {
              final result = spawnCritterAtLocation(save, locationId, nowMs);
              return <String, Object?>{
                'locationId': locationId,
                if (result.ok) ...<String, Object?>{
                  'ok': true,
                  'save': result.save!.toJson(),
                  'critterId': result.critter!.id,
                } else ...<String, Object?>{'ok': false, 'reason': result.reason},
              };
            }).toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('critter hour roll parity', () {
    for (final fixture in loadParityFixtures('critters/hours')) {
      test(fixture.name, () {
        final save = saveOf(fixture);
        final nowMs = fixture.inputField<num>('nowMs');
        final location = fixture.inputField<String>('location');
        final bySpan = numListOf(fixture, 'spans').map((elapsedMs) {
          final result = applyActivityTimeTowardCritters(
            save,
            location,
            elapsedMs,
            nowMs,
            _randomOf(fixture),
          );
          return <String, Object?>{
            'elapsedMs': elapsedMs,
            'save': result.save.toJson(),
            'spawnedId': result.spawned?.id,
            'hoursRolled': result.hoursRolled,
          };
        }).toList();
        expect(checkParity(fixture, {'bySpan': bySpan}), isNull);
      });
    }
  });

  group('appearance option parity', () {
    for (final fixture in loadParityFixtures('cosmetics/appearance')) {
      if (fixture.name != 'options') continue;
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final categories = _stringList(
          fixture,
          'categories',
        ).map((key) => appearanceCategoryByKey(key)!).toList();
        expect(
          checkParity(fixture, {
            'defaults': defaultAppearance(db).toJson(),
            'byCategory': categories
                .map(
                  (category) => <String, Object?>{
                    'category': category.key,
                    'label': appearanceCategoryLabel(category),
                    'options': appearanceOptions(
                      db,
                      category,
                    ).map((row) => row.raw['Appearance Option ID']).toList(),
                    'valid': _appearanceOptionIds
                        .map((optionId) => isValidAppearanceOption(db, category, optionId))
                        .toList(),
                  },
                )
                .toList(),
            'lookups': _appearanceOptionIds
                .map(
                  (optionId) => <String, Object?>{
                    'optionId': optionId,
                    'category': appearanceOptionById(db, optionId)?.raw['Category'],
                  },
                )
                .toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('appearance selection parity', () {
    for (final fixture in loadParityFixtures('cosmetics/appearance')) {
      if (fixture.name != 'set-option') continue;
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final options = _stringList(fixture, 'options');
        final results = <Map<String, Object?>>[];
        for (final key in appearanceCategories) {
          final category = appearanceCategoryByKey(key)!;
          for (final optionId in options) {
            final next = setAppearanceOption(db, save, category, optionId);
            results.add(<String, Object?>{
              'category': category.key,
              'optionId': optionId,
              'appearance': next?.appearance.toJson(),
              'direct': withAppearanceOption(save.appearance, category, optionId).toJson(),
            });
          }
        }
        expect(checkParity(fixture, {'results': results}), isNull);
      });
    }
  });

  group('wardrobe view parity', () {
    for (final fixture in loadParityFixtures('cosmetics/wardrobe-view')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        expect(
          checkParity(fixture, {
            'tabs': wardrobeSlotTabs(db).map((tab) => tab.toJson()).toList(),
            'slots': _stringList(
              fixture,
              'slotIds',
            ).map((slotId) => wardrobeSlotView(db, save, slotId)?.toJson()).toList(),
            'sliders': appearanceSliders(
              db,
              save.appearance,
            ).map((slider) => slider.toJson()).toList(),
            'notices': _wardrobeCosmeticIds
                .expand(
                  (cosmeticId) => <bool>[true, false].map(
                    (isFirstEver) => cosmeticUnlockNotice(db, cosmeticId, isFirstEver)?.toJson(),
                  ),
                )
                .toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('log view parity', () {
    for (final fixture in loadParityFixtures('log/view')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        expect(
          checkParity(fixture, {
            'achievements': achievementLog(db, save).map((row) => row.toJson()).toList(),
            'quests': questLog(db, save).map((row) => row.toJson()).toList(),
            'recipes': recipeLog(db, save).map((row) => row.toJson()).toList(),
            'critters': critterLog(save).map((row) => row.toJson()).toList(),
            'completion': logCompletion(db, save).toJson(),
          }),
          isNull,
        );
      });
    }
  });

  group('progression meta parity', () {
    for (final fixture in loadParityFixtures('achievements/sync')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final nowMs = fixture.inputField<num>('nowMs');
        final save = saveOf(fixture);
        final once = syncProgressionMeta(db, save, nowMs);
        expect(
          checkParity(fixture, {
            'once': once.toJson(),
            'twice': syncProgressionMeta(db, once, nowMs + 60000).toJson(),
            'collectsEverything': hasEveryCritter(save),
          }),
          isNull,
        );
      });
    }
  });

  group('achievement revocation parity', () {
    for (final fixture in loadParityFixtures('achievements/revoke')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final nowMs = fixture.inputField<num>('nowMs');
        final complete = saveOf(fixture);
        final held = syncProgressionMeta(db, complete, nowMs);
        final widened = held.copyWith(critterCollections: held.critterCollections.sublist(1));
        expect(
          checkParity(fixture, {
            'held': held.achievements.map((row) => row.toJson()).toList(),
            'afterNewCritter': syncProgressionMeta(
              db,
              widened,
              nowMs + 60000,
            ).achievements.map((row) => row.toJson()).toList(),
            'regained': syncProgressionMeta(
              db,
              complete,
              nowMs + 120000,
            ).achievements.map((row) => row.toJson()).toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('player title parity', () {
    for (final fixture in loadParityFixtures('save/title')) {
      test(fixture.name, () {
        final save = saveOf(fixture);
        final died = save.copyWith(hasEverDied: true);
        final nameless = save.copyWith(characterName: null);
        expect(
          checkParity(fixture, {
            'living': titleForSave(save)?.toJson(),
            'died': titleForSave(died)?.toJson(),
            'displayLiving': displayNameForSave(save, 'Adventurer'),
            'displayDied': displayNameForSave(died, 'Adventurer'),
            'displayNameless': displayNameForSave(nameless, 'Adventurer'),
            'prefixed': nameWithTitle(
              'Rowan',
              const PlayerTitle(text: 'Sir', placement: TitlePlacement.prefix),
            ),
            'untitled': nameWithTitle('Rowan', null),
          }),
          isNull,
        );
      });
    }
  });

  group('bounty turn-in parity', () {
    for (final fixture in loadParityFixtures('bounties/turn-in')) {
      if (fixture.name == 'rotated-board') continue;
      test(fixture.name, () {
        final save = saveOf(fixture);
        final nowMs = fixture.inputField<num>('nowMs');
        final board = hourlyBountyBoard(nowMs);
        expect(
          checkParity(fixture, {
            'hourKey': board.hourKey,
            'byBounty': board.bounties.map((bounty) {
              final prepared = prepareBountyTurnIn(save, bounty, nowMs);
              return <String, Object?>{
                'bountyId': bounty.id,
                'prepared': prepared.toJson(),
                'rewardFirst': prepared.ok
                    ? applyBountyReward(prepared.save!, bounty, true).toJson()
                    : null,
                'rewardLater': prepared.ok
                    ? applyBountyReward(prepared.save!, bounty, false).toJson()
                    : null,
              };
            }).toList(),
          }),
          isNull,
        );
      });
    }

    for (final fixture in loadParityFixtures('bounties/turn-in')) {
      if (fixture.name != 'rotated-board') continue;
      test(fixture.name, () {
        final save = saveOf(fixture);
        final nowMs = fixture.inputField<num>('nowMs');
        final bounty = hourlyBountyBoard(nowMs).bounties.first;
        return expect(
          checkParity(fixture, {
            'staleHour': prepareBountyTurnIn(
              save.copyWith(bountyHourKey: '2020-01-01T00'),
              bounty,
              nowMs,
            ).toJson(),
            'alreadyClaimed': prepareBountyTurnIn(
              save.copyWith(bountyClaimedIds: <String>[bounty.id]),
              bounty,
              nowMs,
            ).toJson(),
            'offBoard': prepareBountyTurnIn(save, _renamed(bounty, 'BNT-9999'), nowMs).toJson(),
          }),
          isNull,
        );
      });
    }
  });
}

const List<String> _appearanceOptionIds = <String>[
  'APR-0001',
  'APR-0004',
  'APR-0007',
  'APR-0017',
  'APR-9999',
];

const List<String> _wardrobeCosmeticIds = <String>['COS-0001', 'COS-9999'];
