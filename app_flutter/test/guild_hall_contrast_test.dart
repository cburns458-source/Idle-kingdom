import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/multiplayer_controller.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/guild_hall_gold_bar.dart';
import 'package:idle_kingdoms/src/ui/guild_hall_panel.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  test('guild hall inks clear 4.5:1 on wood tan and stone ash', () {
    for (final chrome in [UiChrome.wood, UiChrome.stone]) {
      expect(contrastRatio(Palette.goldInk, chrome.panel), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(chrome.panelInk, chrome.panel), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(Palette.parchmentText, chrome.slot), greaterThanOrEqualTo(4.5));
    }
    expect(contrastRatio(Palette.muted, UiChrome.wood.panel), lessThan(4.5));
    expect(contrastRatio(Palette.muted, UiChrome.stone.panel), lessThan(4.5));
    expect(contrastRatio(Palette.gold, Palette.panelTan), lessThan(4.5));
    expect(contrastRatio(Palette.borderSelected, Palette.panelTan), lessThan(4.5));
  });

  testWidgets('hall labels use goldInk or dark ink on wood and stone, never tan or green', (
    tester,
  ) async {
    for (final chrome in [UiChrome.wood, UiChrome.stone]) {
      final controller = buildController(
        database,
        seed: startedCharacter(database).copyWith(currentLocationId: guildHallLocationId),
      );
      addTearDown(controller.dispose);
      final net = await _leaderOfANewGuild(
        database,
        controller.save,
        email: 'leader-${chrome.pack.name}@example.com',
      );
      addTearDown(net.dispose);

      await _pumpHall(
        tester,
        GuildHallPanel(key: UniqueKey(), controller: controller, multiplayer: net),
        chrome,
      );
      await tester.pumpAndSettle();

      final active = tester.widget<Text>(find.text('Build the Hall'));
      expect(active.style?.color, Palette.goldInk);
      expect(contrastRatio(active.style!.color!, chrome.panel), greaterThanOrEqualTo(4.5));

      final inactive = tester.widget<Text>(find.text('Boxing Ring'));
      expect(inactive.style?.color, chrome.panelInk);
      expect(inactive.style?.color, isNot(Palette.muted));
      expect(inactive.style?.color, isNot(Palette.borderSelected));
      expect(contrastRatio(inactive.style!.color!, chrome.panel), greaterThanOrEqualTo(4.5));

      final remaining = tester.widget<Text>(find.text('1,000,000'));
      expect(remaining.style?.color, Palette.goldInk);

      await tester.tap(find.text('Achievements'));
      await tester.pump();
      final locked = tester.widget<Text>(find.text('Deep pockets'));
      expect(locked.style?.color, chrome.panelInk);
      expect(contrastRatio(locked.style!.color!, chrome.panel), greaterThanOrEqualTo(4.5));
    }
  });

  testWidgets('gold remaining on the hall bar is gold ink, not currency gold', (tester) async {
    for (final chrome in [UiChrome.wood, UiChrome.stone]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: UiChromeScope(
            chrome: chrome,
            child: const Scaffold(body: GamePanel(child: GuildHallGoldBar(contributed: 0))),
          ),
        ),
      );
      final amount = tester.widget<Text>(find.text('1,000,000'));
      expect(amount.style?.color, Palette.goldInk);
      expect(contrastRatio(amount.style!.color!, chrome.panel), greaterThanOrEqualTo(4.5));
    }
  });
}

Future<void> _pumpHall(WidgetTester tester, Widget panel, UiChrome chrome) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: UiChromeScope(
        chrome: chrome,
        child: Scaffold(body: panel),
      ),
    ),
  );
}

Future<MultiplayerController> _leaderOfANewGuild(
  LoadedDatabase database,
  PlayerSave save, {
  String email = 'leader@example.com',
}) async {
  final net = buildMultiplayer(database);
  await net.service.signUp(email, 'Leader', 'secret');
  await net.service.createGuild(
    const CreateGuildInput(
      name: 'Oak',
      tag: 'OAK',
      description: '',
      emblem: GuildEmblem(color: '#2f6b3a', symbol: 'tree'),
    ),
    guildCreateGoldCost,
  );
  await net.refresh(save);
  return net;
}
