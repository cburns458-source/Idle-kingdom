import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/game_controller.dart';
import 'package:idle_kingdoms/src/session/multiplayer_controller.dart';
import 'package:idle_kingdoms/src/ui/guild_hall_panel.dart';
import 'package:idle_kingdoms/src/ui/location_view.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('offers the hall at the Guild Hall and hides it in the Meadow', (tester) async {
    final hall = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: guildHallLocationId),
    );
    addTearDown(hall.dispose);
    await pumpPanel(
      tester,
      LocationView(controller: hall, multiplayer: buildMultiplayer(database), onOpenMap: () {}),
      size: const Size(900, 2400),
    );
    expect(find.text('Hall services'), findsOne);

    final meadow = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: 'LOC-0009'),
    );
    addTearDown(meadow.dispose);
    await pumpPanel(
      tester,
      LocationView(controller: meadow, multiplayer: buildMultiplayer(database), onOpenMap: () {}),
    );
    expect(find.text('Hall services'), findsNothing);
  });

  testWidgets('a signed-in guild leader can open the hall panel', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database)
          .copyWith(currentLocationId: guildHallLocationId, gold: guildHallDebtGold),
    );
    addTearDown(controller.dispose);
    final net = buildMultiplayer(database);
    addTearDown(net.dispose);
    final signed = await net.service.signUp('leader@example.com', 'Leader', 'secret');
    expect(signed.ok, isTrue);
    final created = await net.service.createGuild(
      CreateGuildInput(
        name: 'Oak',
        tag: 'OAK',
        description: '',
        emblem: const GuildEmblem(color: '#2f6b3a', symbol: 'tree'),
      ),
      controller.save.gold,
    );
    expect(created.ok, isTrue);
    await net.refresh(controller.save);

    await pumpPanel(tester, GuildHallPanel(controller: controller, multiplayer: net));
    await tester.pump();
    await tester.pump();
    expect(find.text('Guild Hall'), findsOne);
    expect(find.text('Debt'), findsOne);
    await tester.tap(find.text('Debt'));
    await tester.pump();
    expect(find.textContaining('Remaining:'), findsOne);
  });

  testWidgets('a new hall offers the store house and the debt, and nothing else', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: guildHallLocationId),
    );
    addTearDown(controller.dispose);
    final net = await _leaderOfANewGuild(database, controller.save);
    addTearDown(net.dispose);

    await pumpPanel(tester, GuildHallPanel(controller: controller, multiplayer: net));
    await tester.pump();
    await tester.pump();

    expect(find.text('Store House'), findsWidgets);
    expect(find.text('Debt'), findsOne);
    expect(find.text('Bank'), findsNothing);
    expect(find.text('Boxing'), findsNothing);

    // The first step is named, with its materials and how far along they are.
    expect(find.text('Build the Hall'), findsOne);
    expect(find.textContaining('Cedar Log 0 / 1,000'), findsOne);
  });

  testWidgets('the store house takes donations and never gives them back', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(
        currentLocationId: guildHallLocationId,
        inventory: const [InventoryStack(itemId: 'ITEM-0015', quantity: 400)],
      ),
    );
    addTearDown(controller.dispose);
    final net = await _leaderOfANewGuild(database, controller.save);
    addTearDown(net.dispose);

    await pumpPanel(tester, GuildHallPanel(controller: controller, multiplayer: net));
    await tester.pump();
    await tester.pump();

    expect(find.text('In'), findsOne);
    expect(find.text('Out'), findsNothing);

    await tester.tap(find.text('In'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Max'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contribute'));
    await tester.pumpAndSettle();

    expect(controller.save.inventory, isEmpty);
    expect(find.textContaining('Cedar Log 400 / 1,000'), findsOne);
    expect(find.text('Out'), findsNothing);
  });

  testWidgets('the store house hides In on a stack the next step does not want', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(
        currentLocationId: guildHallLocationId,
        inventory: const [InventoryStack(itemId: 'ITEM-0031', quantity: 4)],
      ),
    );
    addTearDown(controller.dispose);
    final net = await _leaderOfANewGuild(database, controller.save);
    addTearDown(net.dispose);

    await pumpPanel(tester, GuildHallPanel(controller: controller, multiplayer: net));
    await tester.pump();
    await tester.pump();

    expect(find.text('In'), findsNothing);
    expect(find.textContaining('Fernleaf'), findsNothing);
  });

  testWidgets('a finished counting room adds a Bank that opens the bank screen', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: guildHallLocationId),
    );
    addTearDown(controller.dispose);
    final net = await _leaderOfANewGuild(database, controller.save);
    addTearDown(net.dispose);
    // The first two tiers, paid for before the panel opens.
    await _donate(net, controller, const <InventoryStack>[
      InventoryStack(itemId: 'ITEM-0015', quantity: 1000),
      InventoryStack(itemId: 'ITEM-0095', quantity: 100),
      InventoryStack(itemId: 'ITEM-0017', quantity: 1000),
      InventoryStack(itemId: 'ITEM-0002', quantity: 200),
      InventoryStack(itemId: 'ITEM-0006', quantity: 100),
    ]);

    var opened = 0;
    await pumpPanel(
      tester,
      GuildHallPanel(controller: controller, multiplayer: net, onOpenBank: () => opened += 1),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Bank'), findsOne);
    // The ring waits on the third tier.
    expect(find.text('Boxing'), findsNothing);

    await tester.tap(find.text('Bank'));
    await tester.pump();
    await tester.tap(find.text('Open the bank'));
    await tester.pump();
    expect(opened, 1);
  });
}

/// Hands the whole list to the store house, a stack at a time.
Future<void> _donate(
  MultiplayerController net,
  GameController controller,
  List<InventoryStack> stacks,
) async {
  for (final stack in stacks) {
    controller.commit(controller.save.copyWith(inventory: <InventoryStack>[stack]));
    final result = await net.service.contributeHallItem(controller.save, 0, stack.quantity);
    expect(result.reason, isNull);
    controller.commit(result.save!);
  }
}

/// A signed-in leader whose brand new guild has an untouched hall.
Future<MultiplayerController> _leaderOfANewGuild(LoadedDatabase database, PlayerSave save) async {
  final net = buildMultiplayer(database);
  await net.service.signUp('leader@example.com', 'Leader', 'secret');
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
