import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/hud_level_pref.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/format.dart';
import 'package:idle_kingdoms/src/ui/top_hud.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
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
    expect(find.text('Human'), findsOne);
    final hpLabel =
        '${formatThousands(controller.save.currentHp)}/'
        '${formatThousands(playerMaxHp(controller.db, controller.save))}';
    expect(find.text(hpLabel), findsOne);
    final hud = tester.getRect(find.byType(TopHud));
    final hp = tester.getRect(find.text(hpLabel));
    final bar = tester.getRect(
      find.descendant(of: find.byType(TopHud), matching: find.byType(PillBar)),
    );
    expect(bar.width, 88);
    expect(hp.right, closeTo(hud.right, 16));
    expect(bar.right, closeTo(hud.right, 16));
    expect(bar.top, greaterThan(hp.bottom - 1));
    expect(bar.bottom, closeTo(hud.bottom, 12));
    final portrait = tester.getRect(find.byType(HudPortrait));
    expect(portrait.width, HudPortrait.size);
    expect(portrait.height, HudPortrait.size);
    expect(portrait.bottom, closeTo(hud.bottom, 12));
  });

  testWidgets('hit points sit under the activity, on the right', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
    );
    addTearDown(controller.dispose);
    controller.startActivity('ACT-0012');
    await pumpShell(tester, controller);

    final hpLabel =
        '${formatThousands(controller.save.currentHp)}/'
        '${formatThousands(playerMaxHp(controller.db, controller.save))}';
    final hud = tester.getRect(find.byType(TopHud));
    final activity = tester.getRect(
      find.descendant(of: find.byType(TopHud), matching: find.text('Gather meadow supplies')),
    );
    final hp = tester.getRect(find.text(hpLabel));
    final bar = tester.getRect(
      find.descendant(of: find.byType(TopHud), matching: find.byType(PillBar)),
    );
    expect(hp.top, greaterThan(activity.bottom - 2));
    expect(hp.right, closeTo(activity.right, 8));
    expect(bar.top, greaterThan(hp.bottom - 1));
    expect(bar.right, closeTo(activity.right, 8));
    expect(bar.bottom, closeTo(hud.bottom, 12));
  });

  testWidgets('the HUD guild tag stays off until Settings turns it on', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(gold: guildCreateGoldCost),
    );
    final net = buildMultiplayer(database);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    final created = await net.service.createGuild(
      const CreateGuildInput(
        name: 'Developers',
        tag: 'DEV',
        emblem: GuildEmblem(color: '#3d5a80', symbol: 'shield'),
      ),
      guildCreateGoldCost,
    );
    expect(created.ok, isTrue, reason: created.reason);
    await net.refresh(controller.save);
    expect(net.guild?.tag, 'DEV');

    await pumpShell(tester, controller, multiplayer: net);
    expect(find.textContaining('Tester'), findsWidgets);
    expect(find.textContaining('[DEV]'), findsNothing);

    net.setShowHudGuildTag(true);
    await tester.pump();
    expect(find.textContaining('[DEV] Tester'), findsOne);
  });

  testWidgets('hiding the chat bubble removes the corner button', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    final net = buildMultiplayer(database);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    await pumpShell(tester, controller, multiplayer: net);

    expect(find.byTooltip('Open chat'), findsOne);
    net.setHideChatBubble(true);
    await tester.pump();
    expect(find.byTooltip('Open chat'), findsNothing);

    net.setHideChatBubble(false);
    await tester.pump();
    expect(find.byTooltip('Open chat'), findsOne);
  });
}
