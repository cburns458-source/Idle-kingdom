import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/multiplayer_controller.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/account_panel.dart';
import 'package:idle_kingdoms/src/ui/game_image.dart';
import 'package:idle_kingdoms/src/ui/player_profile_sheet.dart';
import 'package:idle_kingdoms/src/ui/social_bits.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  Future<void> signIn(MultiplayerController net) async {
    final result = await net.service.signUp('hero@example.com', 'Hero', 'secret');
    expect(result.ok, isTrue);
  }

  testWidgets('nearby at the meadow lists Mira from The Watch', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: demoMiraLocationId),
    );
    final net = buildMultiplayer(database);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await signIn(net);
    await net.refresh(controller.save);
    await pumpShell(tester, controller, multiplayer: net, size: const Size(900, 2400));
    await tester.pump();

    await tester.tap(find.byTooltip('Nearby adventurers'));
    await tester.pump();
    await tester.pump();

    expect(find.text('[WCH]Mira'), findsOne);
    expect(find.textContaining('The Watch'), findsNothing);

    await tester.tap(find.text('[WCH]Mira'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Friend request'), findsOne);
    expect(find.text('Ignore'), findsOne);

    await tester.tap(find.text('Ignore'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Ignored.'), findsOne);
    expect(find.text('OK'), findsOne);
    await tester.tap(find.text('OK'));
    await tester.pump();
    expect(find.text('Unignore'), findsOne);
  });

  Color nearbyChipRim(WidgetTester tester) {
    final material = tester
        .widgetList<Material>(
          find.descendant(
            of: find.byTooltip('Nearby adventurers'),
            matching: find.byType(Material),
          ),
        )
        .firstWhere((row) {
          final shape = row.shape;
          return shape is PixelSteppedBorder || shape is RoundedRectangleBorder;
        });
    final shape = material.shape!;
    if (shape is PixelSteppedBorder) return shape.side.color;
    return (shape as RoundedRectangleBorder).side.color;
  }

  testWidgets('nearby chip is gold for strangers and green for guildmates', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: demoMiraLocationId),
    );
    final net = buildMultiplayer(database);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    await signIn(net);
    await net.refresh(controller.save);
    await pumpShell(tester, controller, multiplayer: net, size: const Size(900, 2400));
    await tester.pump();

    expect(net.peers, isNotEmpty);
    expect(net.nearbyHasAllies, isFalse);
    expect(nearbyChipRim(tester), Palette.gold);

    await net.applyToGuild(demoGuildId, 'Reporting in', controller.save);
    await tester.pump();
    await net.refresh(controller.save);
    await tester.pump();

    expect(net.nearbyHasAllies, isTrue);
    expect(nearbyChipRim(tester), Palette.softGreen);
  });

  testWidgets('a nearby profile shows the player\'s equipped items', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: demoMiraLocationId),
    );
    final net = buildMultiplayer(database);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await signIn(net);
    await net.refresh(controller.save);
    await pumpPanel(
      tester,
      PlayerProfileSheet(controller: controller, multiplayer: net, userId: demoMiraId),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Gear'), findsOne);
    await tester.tap(find.byTooltip('Gear'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Wooden Sword'), findsOne);
    expect(find.byTooltip('Wooden Shield'), findsOne);
  });

  testWidgets('a profile shows a tall bust with skills beside it', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: demoMiraLocationId),
    );
    final net = buildMultiplayer(database);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    await signIn(net);
    await pumpPanel(
      tester,
      PlayerProfileSheet(controller: controller, multiplayer: net, userId: demoMiraId),
    );
    await tester.pumpAndSettle();

    final art = tester.getRect(find.byType(SocialPortrait));
    expect(art.width, 156);
    expect(art.height, 156);
    final portrait = tester.widget<GameImage>(
      find.descendant(of: find.byType(SocialPortrait), matching: find.byType(GameImage)),
    );
    expect(portrait.path, contains('player_wood_elf_feminine'));

    final beside = find.byType(GameImage).evaluate().any((element) {
      final box = tester.getRect(find.byWidget(element.widget));
      return box.left > art.right && box.top < art.bottom;
    });
    expect(beside, isTrue);
  });

  testWidgets('guild search shows The Watch, and a recruit can join and leave', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    final net = buildMultiplayer(database);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await signIn(net);
    await pumpShell(tester, controller, multiplayer: net, size: const Size(900, 2400));

    await openChinScreen(tester, 'Guilds');
    await tester.pump();

    expect(find.text('[WCH] The Watch'), findsOne);
    await tester.tap(find.text('[WCH] The Watch'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Join'), findsOne);
    await tester.tap(find.text('Join'));
    await tester.pump();
    await tester.pump();
    // Action results are alerts now, not a sticky banner.
    expect(find.text('OK'), findsOne);
    await tester.tap(find.text('OK'));
    await tester.pump();
    await tester.pump();

    // Leave the roster detail; the guild home now owns the panel.
    await tester.tap(find.widgetWithText(GameButton, 'Close'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Mira'), findsWidgets);
    expect(find.textContaining('Bram'), findsWidgets);
    expect(find.textContaining('Kael'), findsWidgets);
    expect(find.text('Leave guild'), findsOne);

    await tester.tap(find.text('Leave guild'));
    await tester.pump();
    await tester.tap(find.text('Leave'));
    await tester.pump();
    await tester.pump();
    expect(find.text('OK'), findsOne);
    await tester.tap(find.text('OK'));
    await tester.pump();
    await tester.pump();

    expect(find.text('[WCH] The Watch'), findsOne);
    await tester.tap(find.text('[WCH] The Watch'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Join'), findsOne);
  });

  testWidgets('guest The Watch without joining the roster', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    final net = buildMultiplayer(database);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await signIn(net);
    await pumpShell(tester, controller, multiplayer: net, size: const Size(900, 2400));

    await openChinScreen(tester, 'Guilds');
    await tester.pump();

    expect(find.text('[WCH] The Watch'), findsOne);
    await tester.tap(find.text('[WCH] The Watch'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Guest'), findsOne);
    await tester.tap(find.text('Guest'));
    await tester.pump();
    await tester.pump();
    expect(find.text('OK'), findsOne);
    await tester.tap(find.text('OK'));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.widgetWithText(GameButton, 'Close'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Guest of [WCH] The Watch'), findsOne);
    expect(find.text('Leave guest'), findsOne);
    expect(find.text('Leave guild'), findsNothing);
  });

  testWidgets('Account lists friends and ignored players', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    final net = buildMultiplayer(database);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await signIn(net);
    await net.sendFriendRequest(demoMiraId);
    final local = net.service as LocalMultiplayerService;
    local.backend.sendFriendRequest(demoMiraId, net.session!.userId);
    await net.sendFriendRequest(demoMiraId);
    await net.ignorePlayer(demoBramId);
    await net.refresh(controller.save);
    await pumpPanel(
      tester,
      ListenableBuilder(
        listenable: net,
        builder: (context, _) => AccountPanel(controller: controller, multiplayer: net),
      ),
    );

    expect(find.text('Friends'), findsOne);
    expect(find.text('Mira'), findsOne);
    expect(find.textContaining('The Watch ·'), findsOne);
    expect(find.text('Sent requests'), findsNothing);
    expect(find.text('Ignored'), findsOne);
    expect(find.text('Bram'), findsOne);
  });

  testWidgets('Settings Account lists a player after they are ignored', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    final net = buildMultiplayer(database);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await signIn(net);
    await net.ignorePlayer(demoBramId);
    net.announce(null);
    await pumpShell(tester, controller, multiplayer: net, size: const Size(900, 2400));

    await openChinScreen(tester, 'Settings');
    await tester.pump(const Duration(milliseconds: 280));
    await tester.tap(find.widgetWithText(GameButton, 'Account'));
    await tester.pump();
    await tester.ensureVisible(find.text('Bram'));

    expect(find.text('Ignored'), findsOne);
    expect(find.text('Bram'), findsOne);
    expect(find.widgetWithText(GameButton, 'Unignore'), findsOne);
  });
}
