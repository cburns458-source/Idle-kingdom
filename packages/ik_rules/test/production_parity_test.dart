import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

Map<String, Object?> _queueJson(ProductionQueueResult result) {
  return result.ok
      ? <String, Object?>{'ok': true, 'save': result.save!.toJson()}
      : <String, Object?>{'ok': false, 'reason': result.reason};
}

void main() {
  group('recipe row parity', () {
    for (final fixture in loadParityFixtures('production/recipes')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final rows = db.recipes
            .map(
              (recipe) => <String, Object?>{
                'recipeId': recipe.recipeId,
                'complete': isCompleteRecipe(recipe),
                'ingredients': recipeIngredients(recipe).map((row) => row.toJson()).toList(),
                'queueCap': maxCraftsFromQueueCap(db, recipe),
                'automatic': isAutomaticLevelUnlock(recipe),
              },
            )
            .toList();
        expect(
          checkParity(fixture, {'rows': rows, 'queueCapSeconds': queueCapSeconds(db)}),
          isNull,
        );
      });
    }
  });

  group('facility alias parity', () {
    for (final fixture in loadParityFixtures('production/facility-lookup')) {
      test(fixture.name, () {
        final facilityIds = fixture
            .inputField<List<Object?>>('facilityIds')
            .map((value) => value! as String)
            .toList();
        expect(
          checkParity(fixture, {
            'recipeLookup': facilityIds.map(recipeFacilityIdForLookup).toList(),
            'projectLookup': facilityIds.map(projectFacilityIdForLookup).toList(),
            'matches': facilityIds
                .map((facilityId) => recipeMatchesFacility('FAC-0001', facilityId))
                .toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('production activity parity', () {
    for (final fixture in loadParityFixtures('production/activities')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final rows = db.activities
            .map(
              (activity) => <String, Object?>{
                'activityId': activity.activityId,
                'facilityId': facilityIdForActivity(db, activity.activityId),
                'standardProduction': isStandardProductionActivity(db, activity),
              },
            )
            .toList();
        expect(checkParity(fixture, {'rows': rows}), isNull);
      });
    }
  });

  group('available recipe parity', () {
    for (final fixture in loadParityFixtures('production/available')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final byActivity = fixture
            .inputField<List<Object?>>('activityIds')
            .map((value) => value! as String)
            .map(
              (activityId) => <String, Object?>{
                'activityId': activityId,
                'recipeIds': recipesForActivity(
                  db,
                  save,
                  activityId,
                ).map((recipe) => recipe.recipeId).toList(),
              },
            )
            .toList();
        expect(
          checkParity(fixture, {
            'byActivity': byActivity,
            'counts': <num>[
              inventoryCount(save, 'ITEM-0025'),
              inventoryCount(save, 'ITEM-0047'),
              inventoryCount(save, 'ITEM-9999'),
            ],
            'materialMax': <String>['RCP-0001', 'RCP-0002', 'RCP-0014'].map((recipeId) {
              final recipe = getRecipe(db, recipeId);
              return recipe == null ? null : maxCraftsFromMaterials(save, recipe);
            }).toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('quantity clamp parity', () {
    for (final fixture in loadParityFixtures('production/clamp')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final results = fixture.inputField<List<Object?>>('cases').map((value) {
          final entry = value! as List<Object?>;
          final recipe = getRecipe(db, entry[0]! as String);
          return recipe == null
              ? null
              : clampProductionQuantity(db, save, recipe, entry[1]! as num);
        }).toList();
        expect(checkParity(fixture, {'results': results}), isNull);
      });
    }
  });

  group('ingredient removal parity', () {
    // Ingredient lists live in the test rather than the fixture input: they name
    // items directly instead of coming from a recipe row.
    const cases = <(String, List<RecipeIngredient>, num)>[
      ('single', [RecipeIngredient(itemId: 'ITEM-0025', quantity: 1)], 1),
      ('exact-empty', [RecipeIngredient(itemId: 'ITEM-0048', quantity: 1)], 2),
      (
        'multi',
        [
          RecipeIngredient(itemId: 'ITEM-0025', quantity: 2),
          RecipeIngredient(itemId: 'ITEM-0047', quantity: 1),
        ],
        2,
      ),
      (
        'same-item-twice',
        [
          RecipeIngredient(itemId: 'ITEM-0025', quantity: 10),
          RecipeIngredient(itemId: 'ITEM-0025', quantity: 10),
        ],
        1,
      ),
      ('too-many', [RecipeIngredient(itemId: 'ITEM-0025', quantity: 100)], 1),
      ('missing-item', [RecipeIngredient(itemId: 'ITEM-9999', quantity: 1)], 1),
      ('zero-crafts', [RecipeIngredient(itemId: 'ITEM-0025', quantity: 1)], 0),
    ];

    for (final fixture in loadParityFixtures('production/remove-ingredients')) {
      test(fixture.name, () {
        final save = saveOf(fixture);
        final results = cases.map((entry) {
          final (name, ingredients, crafts) = entry;
          final next = removeIngredients(save, ingredients, crafts);
          return <String, Object?>{'name': name, 'save': next?.toJson()};
        }).toList();
        expect(checkParity(fixture, {'results': results}), isNull);
      });
    }
  });

  group('production queue parity', () {
    for (final fixture in loadParityFixtures('production/queue')) {
      test(fixture.name, () {
        final queued = beginProductionQueue(
          databaseOf(fixture),
          saveOf(fixture),
          fixture.inputField<String>('activityId'),
          fixture.inputField<String>('recipeId'),
          fixture.inputField<num>('quantity'),
          fixture.inputField<num>('nowMs'),
        );
        expect(checkParity(fixture, _queueJson(queued)), isNull);
      });
    }
  });

  group('craft completion parity', () {
    for (final fixture in loadParityFixtures('production/craft')) {
      test(fixture.name, () {
        final completed = completeProductionCraft(
          databaseOf(fixture),
          saveOf(fixture),
          fixture.inputField<num>('nowMs'),
        );
        // The no-queue case records only the flag, since there is nothing else.
        final actual = completed == null
            ? null
            : fixture.name == 'no-queue'
            ? <String, Object?>{'finishedQueue': completed.finishedQueue}
            : <String, Object?>{
                'save': completed.save.toJson(),
                'finishedQueue': completed.finishedQueue,
                'xpGained': completed.xpGained,
                'outputName': completed.outputName,
                'outputQty': completed.outputQty,
                'reward': completed.reward.toJson(),
              };
        expect(checkParity(fixture, actual), isNull);
      });
    }
  });

  group('production progress parity', () {
    for (final fixture in loadParityFixtures('production/progress')) {
      test(fixture.name, () {
        final resolved = resolveProductionProgress(
          databaseOf(fixture),
          saveOf(fixture),
          fixture.inputField<num>('nowMs'),
        );
        expect(checkParity(fixture, resolved.toJson()), isNull);
      });
    }
  });

  group('production cancel parity', () {
    for (final fixture in loadParityFixtures('production/cancel')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        expect(
          checkParity(fixture, {
            'save': cancelProductionActivity(db, saveOf(fixture)).toJson(),
            'cleared': clearProductionSave(saveOf(fixture)).toJson(),
          }),
          isNull,
        );
      });
    }
  });

  group('recipe knowledge parity', () {
    for (final fixture in loadParityFixtures('recipes/knowledge')) {
      if (fixture.name != 'all-rows') continue;
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        expect(
          checkParity(fixture, {
            'recipes': db.recipes
                .map(
                  (recipe) => <String, Object?>{
                    'recipeId': recipe.recipeId,
                    'known': knowsRecipe(save, db, recipe.recipeId),
                  },
                )
                .toList(),
            'projects': db.projects
                .map(
                  (project) => <String, Object?>{
                    'projectId': project.projectId,
                    'known': knowsProject(save, db, project.projectId),
                  },
                )
                .toList(),
            'unknownId': knowsRecipe(save, db, 'RCP-9999'),
          }),
          isNull,
        );
      });
    }

    for (final fixture in loadParityFixtures('recipes/knowledge')) {
      if (fixture.name != 'unlock') continue;
      test(fixture.name, () {
        final save = saveOf(fixture);
        final once = unlockRecipeId(save, 'RCP-0003');
        expect(
          checkParity(fixture, {
            'once': once.toJson(),
            'twice': unlockRecipeId(once, 'RCP-0003').toJson(),
            'blank': unlockRecipeId(save, '   ').toJson(),
          }),
          isNull,
        );
      });
    }
  });

  group('recipe book parity', () {
    for (final fixture in loadParityFixtures('recipes/book')) {
      test(fixture.name, () {
        final entries = listRecipeBookEntries(
          saveOf(fixture),
          databaseOf(fixture),
        ).map((entry) => entry.toJson()).toList();
        expect(checkParity(fixture, {'entries': entries}), isNull);
      });
    }
  });
}
