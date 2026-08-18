import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/hud_level_pref.dart';
import 'package:idle_kingdoms/src/ui/format.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  test('the HUD XP toggle stays on this device', () {
    final storage = MemorySaveStorage();
    final pref = HudLevelPref.load(storage);
    expect(pref.showTotalXp, isFalse);

    pref.toggle();
    expect(pref.showTotalXp, isTrue);
    expect(storage.getItem(HudLevelPref.storageKey), '1');
    expect(HudLevelPref.load(storage).showTotalXp, isTrue);

    pref.toggle();
    expect(pref.showTotalXp, isFalse);
    expect(storage.getItem(HudLevelPref.storageKey), '0');
  });

  testWidgets('tapping the HUD identity line switches level and experience', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    final level = 'Lv ${formatThousands(totalLevel(controller.save))}';
    final xp = 'XP ${formatThousands(totalSkillXp(controller.save))}';
    expect(find.textContaining(level), findsOne);
    expect(find.textContaining(xp), findsNothing);

    await tester.tap(find.textContaining(level));
    await tester.pump();

    expect(controller.hudShowTotalXp, isTrue);
    expect(find.textContaining(xp), findsOne);
    expect(find.textContaining(level), findsNothing);

    await tester.tap(find.textContaining(xp));
    await tester.pump();

    expect(controller.hudShowTotalXp, isFalse);
    expect(find.textContaining(level), findsOne);
  });
}
