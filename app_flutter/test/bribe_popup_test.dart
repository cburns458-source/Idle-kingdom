import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/game_controller.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/dialogue_text.dart';
import 'package:idle_kingdoms/src/ui/npc_panel.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

const _questId = 'QST-0003';
const _purseId = 'ITEM-0299';
const _guardId = 'NPC-0012';
const _beggarId = 'NPC-0011';
const _barracks = 'LOC-0017';
const _purseName = 'Stolen Coin Purse';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  List<InventoryStack> filledBag() {
    return [
      for (var index = 0; index < inventorySlotLimit; index++)
        InventoryStack(itemId: 'FILL-$index', quantity: 1),
    ];
  }

  PlayerSave guardReady({num gold = 300, List<InventoryStack> inventory = const []}) {
    final seed = startedCharacter(database).copyWith(
      currentLocationId: _barracks,
      gold: gold,
      inventory: inventory,
      quests: const [QuestProgress(questId: _questId, status: 'active', progress: 0)],
    );
    return applyQuestTalkProgress(database.launch, seed, _beggarId);
  }

  NpcRow guard() {
    return database.launch.npcs.firstWhere((row) => row.raw['NPC ID'] == _guardId);
  }

  Future<GameController> openBribe(
    WidgetTester tester,
    PlayerSave seed, {
    bool? hostedPlay,
    Future<String?> Function(String command, [Map<String, Object?> args])? submitGameCommand,
    HostedCommandSubmit? submitHostedCommand,
  }) async {
    final controller = buildController(database, seed: seed);
    addTearDown(controller.dispose);
    if (hostedPlay != null) controller.hostedPlay = () => hostedPlay;
    await pumpPanel(tester, NpcPanel(controller: controller, npc: guard(), onClose: () {}));
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Bribe 200 gold'), findsOne);
    if (submitGameCommand != null) controller.submitGameCommand = submitGameCommand;
    if (submitHostedCommand != null) controller.submitHostedCommand = submitHostedCommand;
    return controller;
  }

  /// What the hosted `quest_bribe` answers with: the server pays from its own
  /// copy of [save], which may hold gold the client has not seen yet.
  HostedCommandReceipt serverBribe(PlayerSave save, {num extraGold = 0}) {
    final paid = bribeForQuest(
      database.launch,
      save.copyWith(gold: save.gold + extraGold),
      _questId,
    );
    if (!paid.ok) {
      return HostedCommandReceipt(reason: paid.reason, code: paid.code, noRoom: paid.noRoom);
    }
    return HostedCommandReceipt(save: paid.save);
  }

  Future<void> openConfirm(WidgetTester tester) async {
    await tester.tap(find.text('Bribe 200 gold'));
    await tester.pumpAndSettle();
  }

  GameButton button(WidgetTester tester, String label) =>
      tester.widget<GameButton>(find.widgetWithText(GameButton, label).first);

  List<String> shownText(WidgetTester tester) => [
    for (final widget in tester.widgetList<RichText>(find.byType(RichText)))
      widget.text.toPlainText(),
  ];

  void expectNoBank(WidgetTester tester) {
    for (final text in shownText(tester)) {
      expect(text.toLowerCase(), isNot(contains('bank')), reason: text);
    }
  }

  testWidgets('tapping Bribe opens the confirm popup with cost and gold, no purse list', (
    tester,
  ) async {
    final quest = getQuest(database.launch, _questId)!;
    final parsed = parseStructuredObjectives(quest);
    await openBribe(tester, guardReady(gold: 300));
    await openConfirm(tester);

    expect(find.text('Pay the bribe?'), findsOne);
    expect(find.text('${parsed.bribeGold.round()} gold'), findsWidgets);
    expect(find.text('You have 300 gold'), findsOne);
    expect(find.text('· $_purseName'), findsNothing);
    expect(find.textContaining(_purseName), findsNothing);
    expect(find.text('This is a one-time choice. If you pay, the fight is off.'), findsNothing);
    expect(find.textContaining('worth'), findsNothing);
    expect(find.textContaining('profit'), findsNothing);
    expect(find.text('Pay'), findsOne);
    expect(find.text('Cancel'), findsOne);
    expect(button(tester, 'Pay').onPressed, isNotNull);
  });

  testWidgets('Cancel changes nothing', (tester) async {
    final commands = <String>[];
    final controller = await openBribe(
      tester,
      guardReady(),
      submitGameCommand: (command, [args = const <String, Object?>{}]) async {
        commands.add(command);
        return null;
      },
    );
    final before = jsonEncode(controller.save.toJson());
    await openConfirm(tester);

    await tester.tap(find.byKey(const Key('bribe-cancel')));
    await tester.pumpAndSettle();

    expect(find.text('Pay the bribe?'), findsNothing);
    expect(jsonEncode(controller.save.toJson()), before);
    expect(controller.save.gold, 300);
    expect(hasQuestFlag(controller.save, _questId, 'choice:bribe'), isFalse);
    expect(commands, isEmpty);
    expect(controller.message, isNull);
  });

  testWidgets('Pay commits quest_bribe', (tester) async {
    final commands = <String>[];
    final args = <Map<String, Object?>>[];
    final controller = await openBribe(
      tester,
      guardReady(),
      submitGameCommand: (command, [commandArgs = const <String, Object?>{}]) async {
        commands.add(command);
        args.add(commandArgs);
        return null;
      },
    );
    await openConfirm(tester);

    await tester.tap(find.byKey(const Key('bribe-pay')));
    await tester.pumpAndSettle();

    expect(commands, ['quest_bribe']);
    expect(args.single['questId'], _questId);
    expect(controller.save.gold, 100);
    expect(inventoryCount(controller.save, _purseId), 1);
    expect(hasQuestFlag(controller.save, _questId, 'choice:bribe'), isTrue);
    expect(controller.message, 'The purse changes hands.');
    expect(find.text('Pay the bribe?'), findsNothing);
  });

  testWidgets('Pay is disabled when gold is short and shows Need N gold', (tester) async {
    final commands = <String>[];
    final controller = await openBribe(
      tester,
      guardReady(gold: 50),
      submitGameCommand: (command, [args = const <String, Object?>{}]) async {
        commands.add(command);
        return null;
      },
    );
    final before = jsonEncode(controller.save.toJson());
    await openConfirm(tester);

    expect(find.text('Need 200 gold.'), findsOne);
    expect(button(tester, 'Pay').onPressed, isNull);

    await tester.tap(find.byKey(const Key('bribe-pay')));
    await tester.pump();

    expect(commands, isEmpty);
    expect(jsonEncode(controller.save.toJson()), before);
    expect(controller.save.gold, 50);
    expect(find.text('Pay the bribe?'), findsOne);
  });

  testWidgets('a full bag shows the bag popup before the confirm popup', (tester) async {
    final commands = <String>[];
    final controller = await openBribe(
      tester,
      guardReady(inventory: filledBag()),
      submitGameCommand: (command, [args = const <String, Object?>{}]) async {
        commands.add(command);
        return null;
      },
    );
    final before = jsonEncode(controller.save.toJson());

    await tester.tap(find.text('Bribe 200 gold'));
    await tester.pumpAndSettle();

    expect(find.text(DialogueText.bagFull(1)), findsOne);
    expect(find.text('Pay the bribe?'), findsNothing);
    expectNoBank(tester);
    expect(commands, isEmpty);
    expect(jsonEncode(controller.save.toJson()), before);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Pay the bribe?'), findsNothing);
    expect(controller.save.gold, 300);
  });

  testWidgets('not_enough_gold after Pay keeps in-flight XP/items and writes nothing back', (
    tester,
  ) async {
    final commands = <String>[];
    final queued = <String>[];
    final gate = Completer<HostedCommandReceipt>();
    final controller = await openBribe(
      tester,
      guardReady(),
      hostedPlay: true,
      submitGameCommand: (command, [args = const <String, Object?>{}]) async {
        queued.add(command);
        return null;
      },
      submitHostedCommand: (command, [args = const <String, Object?>{}]) {
        commands.add(command);
        return gate.future;
      },
    );
    await openConfirm(tester);
    await tester.tap(find.byKey(const Key('bribe-pay')));
    await tester.pump();

    expect(commands, ['quest_bribe']);
    expect(queued, isEmpty);
    expect(controller.save.gold, 300);

    final first = controller.save.skills.first;
    const flightItemId = 'ITEM-FLIGHT';
    controller.commit(
      controller.save.copyWith(
        skills: [
          first.copyWith(xp: first.xp + 25),
          ...controller.save.skills.skip(1),
        ],
        inventory: [
          ...controller.save.inventory,
          const InventoryStack(itemId: flightItemId, quantity: 3),
        ],
      ),
    );
    gate.complete(const HostedCommandReceipt(reason: 'Need 200 gold.', code: 'not_enough_gold'));
    await tester.pumpAndSettle();

    expect(commands, ['quest_bribe']);
    expect(queued, isEmpty);
    expect(controller.save.skills.first.xp, first.xp + 25);
    expect(inventoryCount(controller.save, flightItemId), 3);
    expect(controller.save.gold, 300);
    expect(inventoryCount(controller.save, _purseId), 0);
    expect(hasQuestFlag(controller.save, _questId, 'choice:bribe'), isFalse);
    expect(find.text('Need 200 gold.'), findsOne);
    expect(controller.message, isNull);
  });

  testWidgets('double tap on Pay sends one quest_bribe', (tester) async {
    final commands = <String>[];
    final gate = Completer<HostedCommandReceipt>();
    final controller = await openBribe(
      tester,
      guardReady(),
      hostedPlay: true,
      submitHostedCommand: (command, [args = const <String, Object?>{}]) {
        commands.add(command);
        return gate.future;
      },
    );
    await openConfirm(tester);
    await tester.tap(find.byKey(const Key('bribe-pay')));
    await tester.pump();
    if (find.byKey(const Key('bribe-pay')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('bribe-pay')), warnIfMissed: false);
      await tester.pump();
    }
    if (find.text('Bribe 200 gold').evaluate().isNotEmpty) {
      await tester.tap(find.text('Bribe 200 gold'));
      await tester.pump();
    }

    expect(commands, ['quest_bribe']);
    expect(controller.save.gold, 300);

    gate.complete(serverBribe(controller.save));
    await tester.pumpAndSettle();

    expect(commands, ['quest_bribe']);
    expect(controller.save.gold, 100);
    expect(inventoryCount(controller.save, _purseId), 1);
    expect(controller.message, 'The purse changes hands.');
  });

  testWidgets('a hosted Pay takes the server save as is, with commands still queued behind it', (
    tester,
  ) async {
    final hostedCalls = <String>[];
    final queued = <String>[];
    final queuedGate = Completer<String?>();
    final bribeGate = Completer<HostedCommandReceipt>();
    final controller = await openBribe(
      tester,
      guardReady(),
      hostedPlay: true,
      submitGameCommand: (command, [args = const <String, Object?>{}]) {
        queued.add(command);
        return queuedGate.future;
      },
      submitHostedCommand: (command, [args = const <String, Object?>{}]) {
        hostedCalls.add(command);
        return bribeGate.future;
      },
    );
    // A meta change is applied locally and still waiting on the server when
    // the bribe goes out, which is when the sync layer leaves adopting the
    // bribe's answer to the panel.
    controller.commit(
      controller.save.copyWith(motto: 'Paid in full'),
      command: 'set_meta',
      args: <String, Object?>{'motto': 'Paid in full'},
    );
    expect(queued, ['set_meta']);

    await openConfirm(tester);
    await tester.tap(find.byKey(const Key('bribe-pay')));
    await tester.pump();
    expect(hostedCalls, ['quest_bribe']);
    expect(controller.save.gold, 300);
    expect(inventoryCount(controller.save, _purseId), 0);

    // The server's copy held 50 gold the client had not seen. It pays from
    // that, so the answer is the only place the right balance exists.
    bribeGate.complete(serverBribe(controller.save, extraGold: 50));
    await tester.pumpAndSettle();

    expect(controller.save.gold, 150);
    expect(inventoryCount(controller.save, _purseId), 1);
    expect(hasQuestFlag(controller.save, _questId, 'choice:bribe'), isTrue);
    expect(controller.save.motto, 'Paid in full');
    expect(controller.message, 'The purse changes hands.');
    expect(hostedCalls, ['quest_bribe']);
    expect(queued, ['set_meta']);
    expect(find.text('Bribe 200 gold'), findsNothing);
    expect(find.text('Pay the bribe?'), findsNothing);

    queuedGate.complete(null);
    await tester.pumpAndSettle();
    expect(controller.save.gold, 150);
    expect(inventoryCount(controller.save, _purseId), 1);
  });

  testWidgets('offline and signed out still pay locally', (tester) async {
    final commands = <String>[];
    final controller = await openBribe(
      tester,
      guardReady(),
      hostedPlay: false,
      submitGameCommand: (command, [args = const <String, Object?>{}]) async {
        commands.add(command);
        return 'Sign in to play.';
      },
    );
    await openConfirm(tester);
    expect(find.textContaining('connection to the server'), findsNothing);

    await tester.tap(find.byKey(const Key('bribe-pay')));
    await tester.pumpAndSettle();

    expect(commands, ['quest_bribe']);
    expect(controller.save.gold, 100);
    expect(inventoryCount(controller.save, _purseId), 1);
    expect(controller.message, 'The purse changes hands.');
  });
}
