import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/arena_panel.dart';
import 'package:idle_kingdoms/src/ui/bank_panel.dart';
import 'package:idle_kingdoms/src/ui/bazaar_view.dart';
import 'package:idle_kingdoms/src/ui/citadel_hub_panel.dart';
import 'package:idle_kingdoms/src/ui/guild_hall_panel.dart';
import 'package:idle_kingdoms/src/ui/inventory_view.dart';
import 'package:idle_kingdoms/src/ui/item_detail_sheet.dart';
import 'package:idle_kingdoms/src/ui/library_view.dart';
import 'package:idle_kingdoms/src/ui/log_view.dart';
import 'package:idle_kingdoms/src/ui/nearby_panel.dart';
import 'package:idle_kingdoms/src/ui/player_gear_sheet.dart';
import 'package:idle_kingdoms/src/ui/production_panel.dart';
import 'package:idle_kingdoms/src/ui/project_panel.dart';
import 'package:idle_kingdoms/src/ui/shop_panel.dart';
import 'package:idle_kingdoms/src/ui/skills_view.dart';
import 'package:idle_kingdoms/src/ui/tanner_panel.dart';
import 'package:idle_kingdoms/src/ui/tracker_view.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  const phone = Size(360, 740);
  const kitchenActivityId = 'ACT-0017';
  const kitchenLocationId = 'LOC-0023';
  const forgeLocationId = 'LOC-0025';
  const generalStoreId = 'SHP-0001';

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  void expectCloseChipsFit(WidgetTester tester) {
    expect(tester.takeException(), isNull);
    final buttons = tester.widgetList(find.byType(GameCloseButton)).toList();
    expect(buttons, isNotEmpty);
    for (final button in buttons) {
      final size = tester.getSize(find.byWidget(button));
      expect(size.width, greaterThanOrEqualTo(gameCloseTapTarget));
      expect(size.height, greaterThanOrEqualTo(gameCloseTapTarget));
    }
    final stale = find.byWidgetPredicate(
      (widget) =>
          widget is GameIconButton &&
          widget.icon == Icons.close &&
          widget.tooltip == 'Close' &&
          (widget.tapTarget == null || widget.tapTarget! < gameCloseTapTarget),
    );
    expect(stale, findsNothing);
  }

  testWidgets('every close chip is at least 48px at a 360px-wide screen with no overflow', (
    tester,
  ) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(
        currentLocationId: kitchenLocationId,
        gold: 250,
        inventory: const [InventoryStack(itemId: 'ITEM-0003', quantity: 2)],
      ),
    );
    addTearDown(controller.dispose);
    final net = buildMultiplayer(database);
    addTearDown(net.dispose);
    void close() {}

    ActivityRow kitchen() => database.launchIndexes.activitiesById[kitchenActivityId]!;
    SpecialProductionStation forge() {
      return specialProductionStationsAt(
        database.launch,
        forgeLocationId,
      ).firstWhere((station) => station.skillId == 'SKL-0011');
    }

    NpcRow tanner() {
      return database.launch.npcs.firstWhere((row) => row.raw['NPC ID'] == 'NPC-0018');
    }

    Future<void> check(Widget panel) async {
      await pumpPanel(tester, panel, size: phone);
      expectCloseChipsFit(tester);
    }

    await check(ShopPanel(controller: controller, shopId: generalStoreId, onClose: close));
    await check(BankPanel(controller: controller, onClose: close));
    await check(ArenaPanel(controller: controller, multiplayer: net, onClose: close));
    await check(TannerPanel(controller: controller, npc: tanner(), onClose: close));
    await check(ProductionPicker(controller: controller, activity: kitchen(), onClose: close));
    await tester.tap(find.widgetWithText(GameButton, 'Recipe book'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expectCloseChipsFit(tester);

    await check(ProjectPicker(controller: controller, station: forge(), onClose: close));
    await check(GuildHallPanel(controller: controller, multiplayer: net, onClose: close));
    await check(
      CitadelHubPanel(
        tab: CitadelHubTab.bounties,
        controller: controller,
        multiplayer: net,
        onClose: close,
      ),
    );
    await check(ItemDetailSheet(controller: controller, itemId: 'ITEM-0003', quantity: 2));
    await check(InventoryView(controller: controller, onClose: close));
    await check(LogView(controller: controller, onClose: close));
    await check(SkillsView(controller: controller, onClose: close));

    await check(LibraryView(controller: controller, onClose: close));
    await check(NearbyPanel(controller: controller, multiplayer: net, onClose: close));
    await check(TrackerView(controller: controller, kind: TrackerKind.xp, onClose: close));
    await check(BazaarView(controller: controller, multiplayer: net, onClose: close));
    await check(PlayerGearSheet(controller: controller, username: 'Mira', equipment: const []));
  });
}
