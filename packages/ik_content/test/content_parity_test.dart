import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:test/test.dart';

import 'support/summaries.dart';

void main() {
  group('validateDatabase parity', () {
    for (final fixture in loadParityFixtures('content/validate')) {
      test(fixture.name, () {
        final db = assertGameDatabaseShape(resolveDatabaseInput(fixture));
        expect(checkParity(fixture, issuesOutput(db)), isNull);
      });
    }
  });

  group('prepareDatabase parity', () {
    for (final fixture in loadParityFixtures('content/prepare')) {
      test(fixture.name, () {
        expect(checkParity(fixture, prepareOutput(resolveDatabaseInput(fixture))), isNull);
      });
    }
  });

  group('countNeedsData parity', () {
    for (final fixture in loadParityFixtures('content/needs-data')) {
      test(fixture.name, () {
        final db = assertGameDatabaseShape(resolveDatabaseInput(fixture));
        expect(checkParity(fixture, {'needsDataCount': countNeedsData(db)}), isNull);
      });
    }
  });

  group('assertGameDatabaseShape parity', () {
    for (final fixture in loadParityFixtures('content/shape')) {
      test(fixture.name, () {
        expect(checkParity(fixture, shapeOutput(resolveDatabaseInput(fixture))), isNull);
      });
    }
  });

  group('filterLaunchContent parity', () {
    for (final fixture in loadParityFixtures('content/launch')) {
      test(fixture.name, () {
        final db = assertGameDatabaseShape(resolveDatabaseInput(fixture));
        final filtered = filterLaunchContent(db);
        final actual = switch (fixture.name) {
          'phase-filtering' => <String, Object?>{
            'skills': idsOf(filtered.rowsOf('Skills'), 'Skill ID'),
            'races': idsOf(filtered.rowsOf('Races'), 'Race ID'),
            'raceBonuses': idsOf(filtered.rowsOf('RaceBonuses'), 'Race Bonus ID'),
            'counts': tableCounts(filtered),
          },
          _ => tableCounts(filtered),
        };
        expect(checkParity(fixture, actual), isNull);
      });
    }
  });

  group('buildIndexes parity', () {
    for (final fixture in loadParityFixtures('content/indexes')) {
      test(fixture.name, () {
        final db = assertGameDatabaseShape(resolveDatabaseInput(fixture));
        final target = fixture.name.endsWith('-launch') ? filterLaunchContent(db) : db;
        final indexes = buildIndexes(target);
        final actual = fixture.name == 'synthetic-database'
            ? indexSummary(indexes)
            : compactIndexSummary(indexes);
        expect(checkParity(fixture, actual), isNull);
      });
    }
  });

  test('database rows keep unknown columns', () {
    final db = assertGameDatabaseShape(resolveDatabaseInput(_contentFixture()));
    final shop = db.shops.first;
    // Shops carry dynamic `Entry N ...` columns that no accessor names.
    expect(shop.raw.keys.where((key) => key.startsWith('Entry ')), isNotEmpty);
    expect(shop.toJson(), same(shop.raw));
  });
}

ParityFixture _contentFixture() =>
    loadParityFixtures('content/validate').firstWhere((f) => f.name == 'real-database');
