import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/multiplayer_controller.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  /// A character standing in a Citadel district with the hour's board finished:
  /// counters filled for what is counted, bag stocked for what is delivered.
  PlayerSave atDistrict(String locationId, {bool boardDone = false}) {
    final board = hourlyBountyBoard(testStartMs);
    final save = startedCharacter(database).copyWith(currentLocationId: locationId);
    if (!boardDone) return save;
    return save.copyWith(
      bountyHourKey: board.hourKey,
      bountyProgress: <String, num>{for (final bounty in board.bounties) bounty.id: bounty.amount},
      bountyClaimedIds: const <String>[],
      inventory: <InventoryStack>[
        for (final bounty in board.bounties)
          if (bounty.kind == 'gather_deliver')
            InventoryStack(itemId: bounty.targetId, quantity: bounty.amount),
      ],
    );
  }

  Future<MultiplayerController> signedIn(MultiplayerController net) async {
    final result = await net.service.signUp('hero@example.com', 'Hero', 'secret');
    expect(result.ok, isTrue);
    return net;
  }

  testWidgets('the plaza offers the bounty board and not the bazaar', (tester) async {
    final controller = buildController(database, seed: atDistrict(citadelPlazaId));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(900, 2400));

    expect(find.text('Hourly Bounties'), findsOne);
    expect(find.text('Grand Bazaar'), findsNothing);
  });

  testWidgets('the market district offers the bazaar and not the bounty board', (tester) async {
    final controller = buildController(database, seed: atDistrict(citadelMarketId));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(900, 2400));

    expect(find.text('Message board'), findsWidgets);
    expect(find.text('Grand Bazaar'), findsWidgets);
    expect(find.text('Hourly Bounties'), findsNothing);
  });

  testWidgets('an unsigned player cannot open the bounty board', (tester) async {
    final controller = buildController(database, seed: atDistrict(citadelPlazaId));
    final net = buildMultiplayer(database, signedIn: false);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    await pumpShell(tester, controller, multiplayer: net, size: const Size(900, 2400));

    expect(find.text('Sign in to play'), findsOne);
    expect(find.text('Hourly Bounties'), findsNothing);
    expect(find.text(bountySignInNotice), findsNothing);
  });

  testWidgets('a finished bounty pays out and then reads as claimed', (tester) async {
    final controller = buildController(database, seed: atDistrict(citadelPlazaId, boardDone: true));
    addTearDown(controller.dispose);
    final net = await signedIn(buildMultiplayer(database));
    addTearDown(net.dispose);
    await pumpShell(tester, controller, multiplayer: net, size: const Size(900, 2400));

    await tapVisible(tester, find.byTooltip('Expand list'));
    await tapVisible(tester, find.text('Open'));
    await tester.pump();

    expect(find.text('Turn in'), findsWidgets);
    final goldBefore = controller.save.gold;

    await tester.tap(find.text('Turn in').first);
    await tester.pump();
    await tester.pump();

    expect(controller.save.gold, greaterThan(goldBefore));
    expect(find.textContaining('First completer! +'), findsOne);
    expect(find.text('Claimed'), findsOne);
  });

  testWidgets('a bazaar post appears on the board it was written to', (tester) async {
    final controller = buildController(database, seed: atDistrict(citadelMarketId));
    addTearDown(controller.dispose);
    final net = await signedIn(buildMultiplayer(database));
    addTearDown(net.dispose);
    await pumpShell(tester, controller, multiplayer: net, size: const Size(900, 2400));

    await tapVisible(tester, find.byTooltip('Expand list'));
    await tapVisible(tester, find.text('Post').first);
    await tester.pump();

    expect(find.text(bazaarEmptyHeading), findsOne);

    await tester.enterText(find.byType(TextField), 'Selling copper ore');
    await tester.tap(find.byKey(const Key('bazaar-post')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Hero · message'), findsOne);
    expect(find.text('Selling copper ore'), findsOne);
    expect(find.text(bazaarPostedNotice), findsOne);
    await tester.tap(find.text('OK'));
    await tester.pump();
  });
}
