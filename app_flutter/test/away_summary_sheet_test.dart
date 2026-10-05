import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/ui/away_summary_sheet.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('hides mid-fight swings and keeps finished fight lines', (tester) async {
    final summary = UnattendedResult(
      save: createNewSave(database.launch, 0),
      changed: true,
      messages: const [
        'Won 2 fights while away.',
        'You hit 12. Cow hits 8.',
        'Defeated Cow',
        'You crit for 40. Seagull hits 3.',
        'Mother Squid releases squidlings! Defeat them to continue.',
        'Defeated Seagull',
      ],
      gatheringActions: 0,
      craftsCompleted: 0,
      combatVictories: 2,
      combatDeaths: 0,
      crittersSpawned: 0,
      effectiveElapsedMs: 180000,
    );

    await pumpPanel(tester, AwaySummarySheet(summary: summary, onDismiss: () {}));

    expect(find.text('While you were away'), findsOneWidget);
    expect(find.text('• 2 enemies defeated'), findsOneWidget);
    expect(find.text('You hit 12. Cow hits 8.'), findsNothing);
    expect(find.textContaining('releases squidlings'), findsNothing);
    expect(find.text('Defeated Cow'), findsOneWidget);
    expect(find.text('Defeated Seagull'), findsOneWidget);
  });
}
