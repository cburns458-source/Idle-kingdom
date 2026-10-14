import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/game_controller.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/bank_panel.dart';
import 'package:idle_kingdoms/src/ui/location_view.dart';
import 'package:idle_kingdoms/src/ui/npc_panel.dart';
import 'package:idle_kingdoms/src/ui/reward_strip.dart';
import 'package:idle_kingdoms/src/ui/shop_panel.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

/// Town Bank: a bank counter and the Beggar on one tile.
const _townBank = 'LOC-0034';

/// Combat Training Grounds: the Armory counter.
const _trainingGrounds = 'LOC-0032';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  Future<GameController> pumpLocation(WidgetTester tester, String locationId) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: locationId),
    );
    addTearDown(controller.dispose);
    controller.noteReward(
      const ActionRewardBundle(
        id: 'strip',
        xpRewards: [],
        loot: [LootGrant(itemId: 'ITEM-0025', quantity: 1, displayName: 'Potato')],
        goldGained: 7,
      ),
    );
    await pumpPanel(
      tester,
      ListenableBuilder(
        listenable: controller,
        builder: (context, _) => LocationView(
          controller: controller,
          multiplayer: buildMultiplayer(database),
          onOpenMap: () {},
        ),
      ),
      size: const Size(900, 2400),
    );
    return controller;
  }

  /// The strip is drawn, and a tap where it sits would land on it.
  void expectStripOnTop(WidgetTester tester) {
    expect(find.byType(RewardStrip), findsOne);
    expect(find.byType(RewardStrip).hitTestable(), findsOne);
    expect(find.text('+7').hitTestable(), findsOne);
  }

  /// The strip is still drawn, but [panel] sits over it and takes the tap.
  void expectStripUnder(WidgetTester tester, Finder panel) {
    expect(panel, findsOne);
    expect(find.byType(RewardStrip), findsOne);
    final strip = tester.getRect(find.byType(RewardStrip));
    expect(tester.getRect(panel).contains(strip.center), isTrue);
    expect(find.byType(RewardStrip).hitTestable(), findsNothing);
    expect(find.text('+7').hitTestable(), findsNothing);
  }

  testWidgets('the strip shows over the stage while nothing is open', (tester) async {
    await pumpLocation(tester, _townBank);
    expectStripOnTop(tester);
  });

  testWidgets('the bank covers the strip, and closing it brings the strip back', (tester) async {
    await pumpLocation(tester, _townBank);
    await selectLocationBandTab(tester, 'Bank');
    await tester.tap(find.widgetWithText(GameButton, 'Bank').last);
    await tester.pump();

    expectStripUnder(tester, find.byType(BankPanel));

    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    expect(find.byType(BankPanel), findsNothing);
    expectStripOnTop(tester);
  });

  testWidgets('an NPC covers the strip', (tester) async {
    await pumpLocation(tester, _townBank);
    await selectLocationBandTab(tester, 'People');
    await tester.tap(find.widgetWithText(GameButton, 'Talk').first);
    await tester.pump();

    expectStripUnder(tester, find.byType(NpcPanel));
  });

  testWidgets('a shop covers the strip', (tester) async {
    await pumpLocation(tester, _trainingGrounds);
    await selectLocationBandTab(tester, 'Shops');
    await tester.tap(find.widgetWithText(GameButton, 'Shop').last);
    await tester.pump();

    expectStripUnder(tester, find.byType(ShopPanel));
  });
}
