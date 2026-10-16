import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/game_controller.dart';
import 'package:idle_kingdoms/src/session/multiplayer_controller.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/guild_bank_view.dart';
import 'package:idle_kingdoms/src/ui/guild_hall_gold_bar.dart';
import 'package:idle_kingdoms/src/ui/guild_hall_panel.dart';
import 'package:idle_kingdoms/src/ui/guild_log_list.dart';
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
    expect(find.text('Chip in'), findsOne);
    expect(find.text('Debt'), findsNothing);
    await tester.tap(find.text('Chip in'));
    await tester.pump();
    expect(find.widgetWithText(GameButton, 'Chip in'), findsWidgets);
  });

  testWidgets('a new hall offers the store house and chip-in, and nothing else', (tester) async {
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
    expect(find.text('Chip in'), findsOne);
    expect(find.text('Debt'), findsNothing);
    expect(find.text('Bank'), findsNothing);
    expect(find.text('Boxing'), findsNothing);
    expect(find.text('Build the Hall'), findsOne);
    expect(find.textContaining('Cedar log 0 / 1,000'), findsOne);
    expect(find.text('Counting Room'), findsOne);
    expect(find.text('Boxing Ring'), findsOne);
    expect(find.text('Indoor Garden'), findsOne);
    expect(find.text('Arcana Station'), findsOne);
    expect(find.text('Monster Cage'), findsOne);
  });

  test('chip-in max is leftover to 1M or the purse, whichever is smaller', () {
    expect(guildHallGoldPayMax(0, 50), 50);
    expect(guildHallGoldPayMax(999900, 500), 100);
    expect(guildHallGoldPayMax(guildHallGoldCap, 500), 0);
    expect(guildHallGoldPayMax(0, 0), 0);
    expect(guildHallGoldPayMax(0, 2000000), guildHallGoldCap);
  });

  testWidgets('the gold bar has Sys marks and counts remaining gold down', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database)
          .copyWith(currentLocationId: guildHallLocationId, gold: 25000),
    );
    addTearDown(controller.dispose);
    final net = await _leaderOfANewGuild(database, controller.save);
    addTearDown(net.dispose);

    await pumpPanel(tester, GuildHallPanel(controller: controller, multiplayer: net));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('guild-gold-bar')), findsOne);
    expect(find.byKey(const Key('guild-gold-mark-10000')), findsOne);
    expect(find.byKey(const Key('guild-gold-mark-40000')), findsOne);
    expect(find.byKey(const Key('guild-gold-mark-130000')), findsOne);
    expect(find.byKey(const Key('guild-gold-mark-400000')), findsOne);
    expect(find.byKey(const Key('guild-gold-mark-1000000')), findsOne);
    expect(find.byKey(const Key('guild-gold-remaining')), findsOne);
    expect(guildHallGoldRemainingLabel(0), '1,000,000');
    expect(tester.widget<GuildHallGoldBar>(find.byType(GuildHallGoldBar)).contributed, 0);

    final chipped = await net.service.payGuildDebt(controller.save, 10000);
    expect(chipped.ok, isTrue, reason: chipped.reason);
    expect(chipped.hall!.goldContributed, 10000);
    expect(guildHallGoldRemainingLabel(chipped.hall!.goldContributed), '990,000');

    await pumpPanel(tester, const GuildHallGoldBar(contributed: 10000));
    expect(tester.widget<GuildHallGoldBar>(find.byType(GuildHallGoldBar)).contributed, 10000);
    expect(find.text('990,000'), findsOne);
  });

  testWidgets('Chip in is disabled when the hall is at the 1M cap', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database)
          .copyWith(currentLocationId: guildHallLocationId, gold: guildHallGoldCap),
    );
    addTearDown(controller.dispose);
    final net = await _leaderOfANewGuild(database, controller.save);
    addTearDown(net.dispose);
    final chipped = await net.service.payGuildDebt(controller.save, guildHallGoldCap.floor());
    expect(chipped.ok, isTrue, reason: chipped.reason);
    controller.commit(chipped.save!);

    await pumpPanel(tester, GuildHallPanel(controller: controller, multiplayer: net));
    await tester.pump();
    await tester.pump();

    final chip = tester.widget<GameButton>(find.byKey(const Key('guild-gold-chip-in')));
    expect(chip.onPressed, isNull);
    expect(guildHallGoldPayMax(chipped.hall!.goldContributed, controller.save.gold), 0);
  });

  testWidgets('Chip in is disabled when the player has no gold', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: guildHallLocationId, gold: 0),
    );
    addTearDown(controller.dispose);
    final net = await _leaderOfANewGuild(database, controller.save);
    addTearDown(net.dispose);

    await pumpPanel(tester, GuildHallPanel(controller: controller, multiplayer: net));
    await tester.pump();
    await tester.pump();

    final chip = tester.widget<GameButton>(find.byKey(const Key('guild-gold-chip-in')));
    expect(chip.onPressed, isNull);
  });

  testWidgets('chip-in keypad and Max stop at leftover to 1M', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database)
          .copyWith(currentLocationId: guildHallLocationId, gold: 2000000),
    );
    addTearDown(controller.dispose);
    final net = await _leaderOfANewGuild(database, controller.save);
    addTearDown(net.dispose);
    final chipped = await net.service.payGuildDebt(controller.save, 999900);
    expect(chipped.ok, isTrue, reason: chipped.reason);
    controller.commit(chipped.save!);

    await pumpPanel(tester, GuildHallPanel(controller: controller, multiplayer: net));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('guild-gold-chip-in')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(GameButton, '9'));
    await tester.pump();
    await tester.tap(find.widgetWithText(GameButton, '9'));
    await tester.pump();
    await tester.tap(find.widgetWithText(GameButton, '9'));
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('quantity-input'))).data, '100');

    await tester.tap(find.text('Max'));
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('quantity-input'))).data, '100');
  });

  testWidgets('chip-in keypad and Max stop at the player purse', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(currentLocationId: guildHallLocationId, gold: 40),
    );
    addTearDown(controller.dispose);
    final net = await _leaderOfANewGuild(database, controller.save);
    addTearDown(net.dispose);

    await pumpPanel(tester, GuildHallPanel(controller: controller, multiplayer: net));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('guild-gold-chip-in')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(GameButton, '9'));
    await tester.pump();
    await tester.tap(find.widgetWithText(GameButton, '9'));
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('quantity-input'))).data, '40');

    await tester.tap(find.text('Max'));
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('quantity-input'))).data, '40');
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
    expect(find.textContaining('Cedar log 400 / 1,000'), findsOne);
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

  testWidgets('a finished counting room adds a Bank tab with Up for grabs', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database)
          .copyWith(currentLocationId: guildHallLocationId, gold: 20000),
    );
    addTearDown(controller.dispose);
    final net = await _leaderOfANewGuild(database, controller.save);
    addTearDown(net.dispose);
    await _donate(net, controller, const <InventoryStack>[
      InventoryStack(itemId: 'ITEM-0015', quantity: 1000),
      InventoryStack(itemId: 'ITEM-0095', quantity: 100),
    ]);
    final chipped = await net.service.payGuildDebt(controller.save, 10000);
    expect(chipped.reason, isNull);
    controller.commit(chipped.save!);
    await _donate(net, controller, const <InventoryStack>[
      InventoryStack(itemId: 'ITEM-0017', quantity: 24000),
      InventoryStack(itemId: 'ITEM-0002', quantity: 10000),
      InventoryStack(itemId: 'ITEM-0006', quantity: 6320),
    ]);

    await pumpPanel(tester, GuildHallPanel(controller: controller, multiplayer: net));
    await tester.pump();
    await tester.pump();

    expect(find.text('Bank'), findsOne);
    expect(find.text('Boxing'), findsNothing);

    await tester.tap(find.text('Bank'));
    await tester.pump();
    expect(find.text('Up for grabs'), findsOne);
    expect(find.text('Open the bank'), findsNothing);
  });

  testWidgets('guild bank greys Out and Move when the player cannot use them', (tester) async {
    final controller = buildController(
      database,
      seed: startedCharacter(database).copyWith(
        currentLocationId: guildHallLocationId,
        inventory: const [InventoryStack(itemId: 'ITEM-0026', quantity: 2)],
      ),
    );
    addTearDown(controller.dispose);
    final net = await _leaderOfANewGuild(database, controller.save);
    addTearDown(net.dispose);
    final hall = GuildHallState(
      guildId: net.guildId ?? 'g1',
      goldContributed: 10000,
      goldContributedBy: const <String, num>{},
      storehouse: const <InventoryStack>[],
      completedTiers: const <String>[guildHallTierBuild, guildHallTierBank],
      bank: const GuildBankState(
        items: <GuildBankItem>[
          GuildBankItem(id: 'gb1', itemId: 'ITEM-0026', quantity: 3, section: guildBankSectionMain),
        ],
      ),
    );

    await pumpPanel(
      tester,
      GamePanel(
        child: SizedBox(
          height: 600,
          child: GuildBankView(
            controller: controller,
            multiplayer: net,
            hall: hall,
            canDeposit: false,
            canWithdraw: false,
            canMove: false,
            onHallChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    final out = tester.widget<GameButton>(find.byKey(const Key('guild-bank-out-gb1')));
    final move = tester.widget<GameButton>(find.byKey(const Key('guild-bank-move-gb1')));
    final inn = tester.widget<GameButton>(find.byKey(const Key('guild-bank-in-0')));
    expect(out.onPressed, isNull);
    expect(move.onPressed, isNull);
    expect(inn.onPressed, isNull);
    expect(find.text('Reach total level 200'), findsNothing);
    expect(find.textContaining('cannot'), findsNothing);
  });

  testWidgets('the guild log lists newest first with an icon per kind', (tester) async {
    await pumpPanel(
      tester,
      const GamePanel(
        child: SizedBox(
          height: 400,
          child: GuildLogList(
            entries: <GuildLogEntry>[
              GuildLogEntry(
                id: 'old',
                guildId: 'g1',
                kind: guildLogKindJoin,
                createdAt: '2026-10-16T01:00:00.000Z',
                actorUsername: 'Ash',
                message: 'Ash joined the guild.',
              ),
              GuildLogEntry(
                id: 'new',
                guildId: 'g1',
                kind: guildLogKindTierComplete,
                createdAt: '2026-10-16T03:00:00.000Z',
                actorUsername: 'Ash',
                message: 'The counting room is open for business.',
                tierId: guildHallTierBank,
              ),
              GuildLogEntry(
                id: 'mid',
                guildId: 'g1',
                kind: guildLogKindDonation,
                createdAt: '2026-10-16T02:00:00.000Z',
                actorUsername: 'Ash',
                message: 'Ash chipped in gold.',
                gold: 400,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('guild-log-list')), findsOne);
    expect(find.byKey(const Key('guild-log-icon-tier_complete')), findsOne);
    expect(find.byKey(const Key('guild-log-icon-donation')), findsOne);
    expect(find.byKey(const Key('guild-log-icon-join')), findsOne);
    final newest = tester.getTopLeft(find.text('The counting room is open for business.'));
    final oldest = tester.getTopLeft(find.text('Ash joined the guild.'));
    expect(newest.dy, lessThan(oldest.dy));
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
