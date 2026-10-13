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

/// Rose's apothecary quest: delivers four items x5 and 1000 gold, pays a Chef's Hat.
const _rose = 'NPC-0005';
const _kitchen = 'LOC-0023';
const _apothecary = 'QST-0002';
const _rabbitsFoot = 'ITEM-0038';
const _fernleaf = 'ITEM-0031';
const _delivered = ['ITEM-0038', 'ITEM-0031', 'ITEM-0028', 'ITEM-0042'];

/// The Old Forester's Through the Thicket completes on its own on the last talk.
const _forester = 'NPC-0017';
const _thicket = 'QST-0010';

void main() {
  late LoadedDatabase database;
  GameDatabase db() => database.launch;

  setUpAll(() => database = loadDatabaseFromRepo());

  NpcRow npcOf(String npcId) => db().npcs.firstWhere((row) => row.raw['NPC ID'] == npcId);

  String name(String itemId) => DialogueText(db()).itemName(itemId);

  PlayerSave fillBag(PlayerSave save, {int free = 0}) {
    final inventory = [...save.inventory];
    for (var index = 0; inventory.length < inventorySlotLimit - free; index++) {
      inventory.add(InventoryStack(itemId: 'ITEM-FILL-$index', quantity: 1));
    }
    return save.copyWith(inventory: inventory);
  }

  /// Rose's quest active and ready, with [quantity] of each delivery item.
  /// [favourite] items sit in hearted stacks.
  PlayerSave roseReady({num quantity = 5, Set<String> favourite = const {}}) {
    return startedCharacter(database).copyWith(
      currentLocationId: _kitchen,
      gold: 1500,
      inventory: [
        for (final itemId in _delivered)
          InventoryStack(
            itemId: itemId,
            quantity: quantity,
            favorite: favourite.contains(itemId) ? true : null,
          ),
      ],
      quests: const [
        QuestProgress(
          questId: _apothecary,
          status: 'active',
          progress: 0,
          counters: {'talk:$_rose': 1},
        ),
      ],
    );
  }

  QuestCompletion failed(
    String code, {
    NoRoom? noRoom,
    List<DialogueItemDelta> favourites = const <DialogueItemDelta>[],
  }) => QuestCompletion.failed(
    'placeholder engine text',
    code: code,
    noRoom: noRoom,
    favourites: favourites,
  );

  Future<GameController> open(
    WidgetTester tester,
    PlayerSave seed, {
    String npcId = _rose,
    QuestTurnInRequest? request,
  }) async {
    final controller = buildController(database, seed: seed);
    addTearDown(controller.dispose);
    await pumpPanel(
      tester,
      NpcPanel(controller: controller, npc: npcOf(npcId), onClose: () {}, turnInRequest: request),
    );
    return controller;
  }

  /// A request on the local rules that records each `useFavourites` it was sent.
  QuestTurnInRequest recording(List<bool> sent, GameController Function() controller) {
    return (questId, {required useFavourites}) async {
      sent.add(useFavourites);
      final result = completeQuest(db(), controller().save, questId, useFavourites: useFavourites);
      if (result.ok) controller().commit(result.save!);
      return result;
    };
  }

  String saveJson(GameController controller) => jsonEncode(controller.save.toJson());

  List<String> shownText(WidgetTester tester) => [
    for (final widget in tester.widgetList<RichText>(find.byType(RichText)))
      widget.text.toPlainText(),
  ];

  void expectNoBank(WidgetTester tester) {
    for (final text in shownText(tester)) {
      expect(text.toLowerCase(), isNot(contains('bank')), reason: text);
    }
  }

  Finder turnIn() => find.widgetWithText(GameButton, 'Turn in');

  const prompt = DialogueText.favouritesPrompt;

  group('full bag', () {
    testWidgets('a turn-in into a full bag shows the popup with new slots only', (tester) async {
      // Six of each keeps every delivery stack, so the Chef's Hat needs one new slot.
      final controller = await open(tester, fillBag(roseReady(quantity: 6)));
      final before = saveJson(controller);

      await tester.tap(turnIn());
      await tester.pumpAndSettle();

      expect(find.text('Your bag is full. Make room for 1 more item and try again.'), findsOne);
      expect(find.textContaining('placeholder'), findsNothing);
      expect(find.text('Collect'), findsNothing);
      expect(saveJson(controller), before);
      expectNoBank(tester);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(saveJson(controller), before);
      expect(turnIn(), findsOne);
    });

    testWidgets('N is the engine’s slotsNeeded, not the free count', (tester) async {
      var calls = 0;
      await open(
        tester,
        roseReady(),
        request: (questId, {required useFavourites}) async {
          calls += 1;
          return failed('no_room', noRoom: const NoRoom(slotsNeeded: 3, slotsFree: 1));
        },
      );

      await tester.tap(turnIn());
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(find.text('Your bag is full. Make room for 3 more items and try again.'), findsOne);
    });

    testWidgets('a quest that completes on its own into a full bag waits, with no popup', (
      tester,
    ) async {
      final full = fillBag(_thicketLastTalk(db(), startedCharacter(database)));
      final controller = await open(tester, full, npcId: _forester);

      await tester.tap(find.widgetWithText(GameButton, 'Continue'));
      await tester.pumpAndSettle();

      expect(getQuestProgress(controller.save, _thicket).status, 'active');
      expect(find.textContaining('Your bag is full'), findsNothing);
      expect(find.text('Collect'), findsNothing);
      expect(find.byType(Dialog), findsNothing);

      // With room on the next visit, the same talk finishes it.
      final roomy = fillBag(_thicketLastTalk(db(), startedCharacter(database)), free: 1);
      await tester.pumpWidget(const SizedBox());
      final next = await open(tester, roomy, npcId: _forester);
      await tester.tap(find.widgetWithText(GameButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(getQuestProgress(next.save, _thicket).status, 'completed');
    });
  });

  group('favourites', () {
    testWidgets('Turn in is never greyed out because of favourites', (tester) async {
      await open(tester, roseReady(favourite: _delivered.toSet()));

      expect(turnIn(), findsOne);
      expect(tester.widget<GameButton>(turnIn()).onPressed, isNotNull);
    });

    testWidgets('asks first and lists every favourite; No does nothing', (tester) async {
      final sent = <bool>[];
      late GameController controller;
      controller = await open(
        tester,
        roseReady(favourite: {_rabbitsFoot, _fernleaf}),
        request: recording(sent, () => controller),
      );
      final before = saveJson(controller);

      await tester.tap(turnIn());
      await tester.pumpAndSettle();

      expect(find.textContaining(prompt), findsOne);
      expect(find.textContaining('${name(_rabbitsFoot)} x5, ${name(_fernleaf)} x5'), findsOne);
      expect(saveJson(controller), before);
      expectNoBank(tester);

      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();

      expect(sent, [false]);
      expect(find.textContaining(prompt), findsNothing);
      expect(find.text('Collect'), findsNothing);
      expect(saveJson(controller), before);
      expect(
        find.byWidgetPredicate((w) => w is Text && w.style?.color == Palette.danger),
        findsNothing,
      );
      expect(turnIn(), findsOne);
    });

    testWidgets('Yes resends once with useFavourites, and it is never saved', (tester) async {
      final sent = <bool>[];
      late GameController controller;
      controller = await open(
        tester,
        roseReady(favourite: {_rabbitsFoot}),
        request: recording(sent, () => controller),
      );

      await tester.tap(turnIn());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();

      expect(sent, [false, true]);
      expect(getQuestProgress(controller.save, _apothecary).status, 'completed');
      expect(bagCount(controller.save, _rabbitsFoot), 0);
      expect(find.text('Collect'), findsOne);
      expect(saveJson(controller), isNot(contains('useFavourites')));
    });

    testWidgets('Yes on the local rules commits the turn-in', (tester) async {
      final controller = await open(tester, roseReady(favourite: {_rabbitsFoot}));

      await tester.tap(turnIn());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();

      expect(getQuestProgress(controller.save, _apothecary).status, 'completed');
      expect(controller.save.gold, 500);
      expect(find.text('Collect'), findsOne);
    });

    testWidgets('a full bag after Yes shows the bag popup, not the prompt again', (tester) async {
      final sent = <bool>[];
      final controller = await open(
        tester,
        roseReady(favourite: {_rabbitsFoot}),
        request: (questId, {required useFavourites}) async {
          sent.add(useFavourites);
          return useFavourites
              ? failed('no_room', noRoom: const NoRoom(slotsNeeded: 2, slotsFree: 0))
              : failed(
                  'confirm_favourites',
                  favourites: const [DialogueItemDelta(itemId: _rabbitsFoot, qty: 5)],
                );
        },
      );
      final before = saveJson(controller);

      await tester.tap(turnIn());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();

      expect(sent, [false, true]);
      expect(find.text('Your bag is full. Make room for 2 more items and try again.'), findsOne);
      expect(find.textContaining(prompt), findsNothing);
      expect(saveJson(controller), before);
    });

    testWidgets('the prompt lists several favourites in the engine’s order', (tester) async {
      await open(
        tester,
        roseReady(),
        request: (questId, {required useFavourites}) async => failed(
          'confirm_favourites',
          favourites: const [
            DialogueItemDelta(itemId: 'ITEM-0042', qty: 2),
            DialogueItemDelta(itemId: _rabbitsFoot, qty: 5),
            DialogueItemDelta(itemId: _fernleaf, qty: 1),
          ],
        ),
      );

      await tester.tap(turnIn());
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          '${name('ITEM-0042')} x2, ${name(_rabbitsFoot)} x5, ${name(_fernleaf)} x1',
        ),
        findsOne,
      );
    });
  });

  group('one request at a time', () {
    testWidgets('a double tap while a turn-in is pending sends one request', (tester) async {
      final pending = Completer<QuestCompletion>();
      var calls = 0;
      await open(
        tester,
        roseReady(),
        request: (questId, {required useFavourites}) {
          calls += 1;
          return pending.future;
        },
      );

      await tester.tap(turnIn());
      await tester.tap(turnIn());
      await tester.pump();
      expect(calls, 1);

      pending.complete(failed('no_room', noRoom: const NoRoom(slotsNeeded: 1, slotsFree: 0)));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Your bag is full. Make room for 1 more item and try again.'), findsOne);
    });

    testWidgets('a double tap on the local rules turns in once', (tester) async {
      final controller = await open(tester, roseReady());

      await tester.tap(turnIn());
      await tester.tap(turnIn(), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(controller.save.gold, 500);
      expect(find.text('Collect'), findsOne);
    });
  });

  test('no NPC panel string mentions the bank', () {
    final source = File('lib/src/ui/npc_panel.dart').readAsStringSync().toLowerCase();
    expect(source, isNot(contains('bank')));
  });
}

/// Through the Thicket with every step done but the Old Forester's last talk.
PlayerSave _thicketLastTalk(GameDatabase db, PlayerSave start) {
  var save = raiseSkillToMinimumLevel(
    start.copyWith(currentLocationId: 'LOC-0040'),
    db,
    'SKL-0006',
    40,
  ).save;
  save = raiseSkillToMinimumLevel(save, db, 'SKL-0014', 35).save;
  save = acceptQuest(db, save, _thicket).save!;
  save = applyQuestActionProgress(db, save, 'ACN-0179', 50);
  save = talkWithQuestNpc(db, save, _forester).save!;
  save = applyQuestActionProgress(db, save, 'ACN-0231', 10);
  save = applyQuestActionProgress(db, save, 'ACN-0232', 10);
  save = applyQuestActionProgress(db, save, 'ACN-0233', 10);
  save = talkWithQuestNpc(db, save, _forester).save!;
  save = applyQuestProcessProgress(db, save, 'RCP-0071', 4);
  save = addItemToInventory(save, 'ITEM-0405', 4);
  for (final locationId in ['LOC-0044', 'LOC-0051', 'LOC-0018', 'LOC-0050']) {
    save = applyQuestLocationProgressResult(db, save, locationId).save;
  }
  return save;
}
