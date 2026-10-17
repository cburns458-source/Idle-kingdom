import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/game_controller.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/dialogue_text.dart';
import 'package:idle_kingdoms/src/ui/npc_panel.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

/// Rose's kitchen, the legacy NPC quest panel's Turn in.
const _roseId = 'NPC-0005';
const _kitchen = 'LOC-0023';
const _roseQuest = 'QST-0002';
const _rabbitsFoot = 'ITEM-0038';
const _fernleaf = 'ITEM-0031';
const _wildBerries = 'ITEM-0028';
const _weaselTail = 'ITEM-0042';
const _potato = 'ITEM-0025';
const _bakedPotato = 'ITEM-0058';
const _cookedPerch = 'ITEM-0059';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  NpcRow rose() {
    return database.launch.npcs.firstWhere((row) => row.raw['NPC ID'] == _roseId);
  }

  PlayerSave roseReady({bool favourite = false}) {
    InventoryStack stack(String itemId) =>
        InventoryStack(itemId: itemId, quantity: 5, favorite: favourite ? true : null);
    return startedCharacter(database).copyWith(
      currentLocationId: _kitchen,
      gold: 1500,
      inventory: [stack(_rabbitsFoot), stack(_fernleaf), stack(_wildBerries), stack(_weaselTail)],
      quests: const [QuestProgress(questId: _roseQuest, status: 'active', progress: 0)],
    );
  }

  Future<GameController> openTurnIn(
    WidgetTester tester,
    PlayerSave seed, {
    NpcQuestPanelRequest? turnInRequest,
  }) async {
    final controller = buildController(database, seed: seed);
    addTearDown(controller.dispose);
    await pumpPanel(
      tester,
      NpcPanel(controller: controller, npc: rose(), onClose: () {}, turnInRequest: turnInRequest),
    );
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Turn in'), findsOne);
    return controller;
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

  QuestCompletion failed(String code, {List<DialogueItemDelta>? favourites, NoRoom? noRoom}) {
    return QuestCompletion.failed(
      'placeholder engine text',
      code: code,
      favourites: favourites ?? const <DialogueItemDelta>[],
      noRoom: noRoom,
    );
  }

  group('full bag', () {
    testWidgets('names only the new slots the rewards need', (tester) async {
      final seed = roseReady();
      final controller = await openTurnIn(
        tester,
        seed,
        turnInRequest: ({required questId, required useFavourites}) async {
          return failed('no_room', noRoom: const NoRoom(slotsNeeded: 2, slotsFree: 0));
        },
      );
      final before = jsonEncode(controller.save.toJson());

      await tester.tap(find.text('Turn in'));
      await tester.pumpAndSettle();

      expect(find.text('Your bag is full. Make room for 2 more items and try again.'), findsOne);
      expect(find.textContaining('placeholder'), findsNothing);
      expect(jsonEncode(controller.save.toJson()), before);
      expect(getQuestProgress(controller.save, _roseQuest).status, 'active');
      expectNoBank(tester);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Your bag is full'), findsNothing);
    });

    testWidgets('npcLine stays off the quest panel; the count popup still shows', (tester) async {
      const spoken = "You've no space left for a royal gift. Clear some room and return to me.";
      await openTurnIn(
        tester,
        roseReady(),
        turnInRequest: ({required questId, required useFavourites}) async {
          return failed(
            'no_room',
            noRoom: const NoRoom(slotsNeeded: 2, slotsFree: 0, npcLine: spoken),
          );
        },
      );

      await tester.tap(find.text('Turn in'));
      await tester.pumpAndSettle();

      expect(find.text(DialogueText.bagFull(2)), findsOne);
      expect(find.text(spoken), findsNothing);
    });

    testWidgets('stack_full says the stack is full and never names a count', (tester) async {
      final seed = roseReady();
      await openTurnIn(
        tester,
        seed,
        turnInRequest: ({required questId, required useFavourites}) async {
          return failed('no_room', noRoom: const NoRoom(reason: 'stack_full'));
        },
      );

      await tester.tap(find.text('Turn in'));
      await tester.pumpAndSettle();

      expect(find.text(DialogueText.stackFull), findsOne);
      expect(find.textContaining('Make room'), findsNothing);
      expect(find.textContaining('cannot hold'), findsNothing);
      expect(find.textContaining('placeholder'), findsNothing);
    });
  });

  group('favourites', () {
    const prompt = DialogueText.favouritesPrompt;

    testWidgets('asks first and lists every favourited item; No does nothing', (tester) async {
      final controller = await openTurnIn(
        tester,
        roseReady(),
        turnInRequest: ({required questId, required useFavourites}) async {
          return failed(
            'confirm_favourites',
            favourites: const [
              DialogueItemDelta(itemId: _bakedPotato, qty: 4),
              DialogueItemDelta(itemId: _cookedPerch, qty: 2),
            ],
          );
        },
      );
      final before = jsonEncode(controller.save.toJson());

      await tester.tap(find.text('Turn in'));
      await tester.pumpAndSettle();

      expect(find.textContaining(prompt), findsOne);
      expect(find.textContaining('Baked potato x4, Perch fillet x2'), findsOne);
      expect(jsonEncode(controller.save.toJson()), before);
      expectNoBank(tester);

      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();

      expect(find.textContaining(prompt), findsNothing);
      expect(jsonEncode(controller.save.toJson()), before);
      expect(find.text('Turn in'), findsOne);
      expect(find.textContaining('placeholder'), findsNothing);
    });

    testWidgets('Yes resends the same request with useFavourites exactly once', (tester) async {
      final sent = <(String, bool)>[];
      late GameController controller;
      controller = await openTurnIn(
        tester,
        roseReady(),
        turnInRequest: ({required questId, required useFavourites}) async {
          sent.add((questId, useFavourites));
          if (!useFavourites) {
            return failed(
              'confirm_favourites',
              favourites: const [DialogueItemDelta(itemId: _bakedPotato, qty: 4)],
            );
          }
          return const QuestCompletion.failed('not completing');
        },
      );

      await tester.tap(find.text('Turn in'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();

      expect(sent, [(_roseQuest, false), (_roseQuest, true)]);
      expect(jsonEncode(controller.save.toJson()), isNot(contains('useFavourites')));

      sent.clear();
      await tester.tap(find.text('Turn in'));
      await tester.pumpAndSettle();
      expect(sent, [(_roseQuest, false)]);
      expect(find.textContaining(prompt), findsOne);
    });

    testWidgets('a full bag after Yes shows the bag popup, not the prompt again', (tester) async {
      var calls = 0;
      await openTurnIn(
        tester,
        roseReady(),
        turnInRequest: ({required questId, required useFavourites}) async {
          calls += 1;
          return useFavourites
              ? failed('no_room', noRoom: const NoRoom(slotsNeeded: 3, slotsFree: 0))
              : failed(
                  'confirm_favourites',
                  favourites: const [DialogueItemDelta(itemId: _bakedPotato, qty: 4)],
                );
        },
      );

      await tester.tap(find.text('Turn in'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(find.text('Your bag is full. Make room for 3 more items and try again.'), findsOne);
      expect(find.textContaining(prompt), findsNothing);
    });

    testWidgets('the prompt lists every entry the engine returns', (tester) async {
      await openTurnIn(
        tester,
        roseReady(),
        turnInRequest: ({required questId, required useFavourites}) async {
          return failed(
            'confirm_favourites',
            favourites: const [
              DialogueItemDelta(itemId: _bakedPotato, qty: 4),
              DialogueItemDelta(itemId: _cookedPerch, qty: 2),
              DialogueItemDelta(itemId: _potato, qty: 7),
            ],
          );
        },
      );

      await tester.tap(find.text('Turn in'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Baked potato x4, Perch fillet x2, Potato x7'), findsOne);
    });

    testWidgets('favourited items never grey out Turn in; No leaves the bag alone', (tester) async {
      final controller = await openTurnIn(tester, roseReady(favourite: true));
      final before = jsonEncode(controller.save.toJson());

      expect(button(tester, 'Turn in').onPressed, isNotNull);
      for (final text in shownText(tester)) {
        expect(text.toLowerCase(), isNot(contains('favour')), reason: text);
      }

      await tester.tap(find.text('Turn in'));
      await tester.pumpAndSettle();

      expect(find.textContaining(prompt), findsOne);
      expect(
        find.textContaining("Rabbit's foot x5, Fernleaf x5, Wild berries x5, Weasel tail x5"),
        findsOne,
      );
      expectNoBank(tester);

      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();

      expect(jsonEncode(controller.save.toJson()), before);
      expect(getQuestProgress(controller.save, _roseQuest).status, 'active');
      expect(controller.save.gold, 1500);
    });
  });

  group('one request at a time', () {
    testWidgets('a double tap sends one request', (tester) async {
      final pending = Completer<QuestCompletion>();
      var calls = 0;
      await openTurnIn(
        tester,
        roseReady(),
        turnInRequest: ({required questId, required useFavourites}) {
          calls += 1;
          return pending.future;
        },
      );

      await tester.tap(find.text('Turn in'));
      await tester.tap(find.text('Turn in'));
      await tester.pump();
      expect(calls, 1);

      pending.complete(failed('no_room', noRoom: const NoRoom(slotsNeeded: 1, slotsFree: 0)));
      await tester.pumpAndSettle();
      expect(find.text('Your bag is full. Make room for 1 more item and try again.'), findsOne);
    });
  });

  test('no quest-panel popup string mentions stored piles outside the bag', () {
    for (final path in [
      'lib/src/ui/npc_panel.dart',
      'lib/src/ui/dialogue_window.dart',
      'lib/src/ui/dialogue_text.dart',
    ]) {
      expect(File(path).readAsStringSync().toLowerCase(), isNot(contains('bank')), reason: path);
    }
  });
}
