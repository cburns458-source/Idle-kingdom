import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/game_controller.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/dialogue_text.dart';
import 'package:idle_kingdoms/src/ui/app_shell.dart';
import 'package:idle_kingdoms/src/ui/dialogue_window.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

/// The real content plus the SYS-01 parity patch: QST-9001 (King: hand in 10
/// Baked Potato + 10 Cooked Perch) and QST-9002 (Fennel: show 5 Baked Potato).
LoadedDatabase _patchedDatabase() {
  final raw = jsonDecode(
    File('../content/data/game-database.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final fixture = jsonDecode(
    File('../parity/fixtures/dialogue/engine/favourites.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final patch = (fixture['input']! as Map<String, Object?>)['patch']! as Map<String, Object?>;
  for (final entry in patch.entries) {
    raw[entry.key] = <Object?>[
      ...raw[entry.key]! as List<Object?>,
      ...entry.value! as List<Object?>,
    ];
  }
  return prepareDatabase(raw);
}

const _king = 'DLG-9001';
const _kingNode = 'DNODE-9001';
const _fennel = 'DLG-9002';
const _fennelNode = 'DNODE-9011';
const _gifts = 'DLG-9003';
const _potato = 'ITEM-0025';
const _bakedPotato = 'ITEM-0058';
const _cookedPerch = 'ITEM-0059';

void main() {
  late LoadedDatabase database;
  GameDatabase db() => database.launch;

  setUpAll(() => database = _patchedDatabase());

  /// Standing with the synthetic King and Fennel, who give their quests in person.
  PlayerSave character() => startedCharacter(database).copyWith(currentLocationId: 'LOC-0002');

  PlayerSave choose(PlayerSave save, String dialogueId, String nodeId, String choiceId) {
    final result = chooseDialogue(db(), save, dialogueId, nodeId, choiceId, useFavourites: true);
    expect(result.ok, isTrue, reason: '$choiceId: ${result.code}');
    return result.save;
  }

  PlayerSave stacks(PlayerSave save, String itemId, List<(num, bool)> piles) {
    return save.copyWith(
      inventory: [
        ...save.inventory.where((stack) => stack.itemId != itemId),
        for (final (quantity, favourite) in piles)
          InventoryStack(itemId: itemId, quantity: quantity, favorite: favourite ? true : null),
      ],
    );
  }

  PlayerSave bag(PlayerSave save, String itemId, num quantity) =>
      stacks(save, itemId, [if (quantity > 0) (quantity, false)]);

  PlayerSave fillBag(PlayerSave save, int free) {
    final inventory = [...save.inventory];
    for (var index = 0; inventory.length < inventorySlotLimit - free; index++) {
      inventory.add(InventoryStack(itemId: 'ITEM-FILL-$index', quantity: 1));
    }
    return save.copyWith(inventory: inventory);
  }

  /// QST-9001 on its hand-in step with 6 Baked Potato and all 10 Cooked Perch already handed in.
  PlayerSave feastSixHandedIn() {
    var save = choose(character(), _king, _kingNode, 'DCH-9001');
    save = bag(bag(save, _bakedPotato, 6), _cookedPerch, 10);
    return choose(save, _king, _kingNode, 'DCH-9002');
  }

  /// QST-9002 on its Show step.
  PlayerSave showing() => choose(character(), _fennel, _fennelNode, 'DCH-9011');

  Future<GameController> open(
    WidgetTester tester,
    PlayerSave seed,
    String dialogueId, {
    DialogueRequest? request,
    VoidCallback? onClose,
  }) async {
    final controller = buildController(database, seed: seed);
    addTearDown(controller.dispose);
    await pumpPanel(
      tester,
      StandaloneDialogueHost(
        controller: controller,
        dialogueId: dialogueId,
        onClose: onClose ?? () {},
        request: request,
      ),
    );
    return controller;
  }

  GameButton button(WidgetTester tester, String label) =>
      tester.widget<GameButton>(find.widgetWithText(GameButton, label).first);

  /// Every string on screen, popups included.
  List<String> shownText(WidgetTester tester) => [
    for (final widget in tester.widgetList<RichText>(find.byType(RichText)))
      widget.text.toPlainText(),
  ];

  void expectNoBank(WidgetTester tester) {
    for (final text in shownText(tester)) {
      expect(text.toLowerCase(), isNot(contains('bank')), reason: text);
    }
  }

  DialogueResult failed(
    PlayerSave save,
    String code, {
    List<DialogueItemDelta>? favourites,
    DialogueNoRoom? noRoom,
  }) {
    return DialogueResult(
      ok: false,
      reason: 'placeholder engine text',
      code: code,
      save: save,
      view: null,
      completed: false,
      message: null,
      favourites: favourites ?? const <DialogueItemDelta>[],
      noRoom: noRoom,
    );
  }

  group('hand-in step', () {
    testWidgets('shows handed-in progress and how many will be handed in', (tester) async {
      await open(tester, bag(feastSixHandedIn(), _bakedPotato, 7), _king);

      expect(find.text('Baked Potato 6/10 handed in'), findsOne);
      expect(find.text('Cooked Perch 10/10 handed in'), findsOne);
      // DCH-9002 (step_ready) and DCH-9006 (quest_active) both hand in.
      expect(find.text('Hand in 4 Baked Potato'), findsNWidgets(2));
      expect(button(tester, 'Hand in 4 Baked Potato').onPressed, isNotNull);
      expectNoBank(tester);
    });

    testWidgets('with none in the bag asks the player to bring them', (tester) async {
      final save = feastSixHandedIn().copyWith(
        bank: [const InventoryStack(itemId: _bakedPotato, quantity: 50)],
      );
      await open(tester, bag(save, _bakedPotato, 0), _king);

      expect(find.text('Baked Potato 6/10 handed in'), findsOne);
      expect(find.text('Bring Baked Potato (6/10 handed in)'), findsNWidgets(2));
      expect(find.textContaining('Hand in'), findsNothing);
      expectNoBank(tester);
    });

    testWidgets('a hand-in records the new count', (tester) async {
      final controller = await open(tester, bag(feastSixHandedIn(), _bakedPotato, 7), _king);

      await tester.tap(find.text('Hand in 4 Baked Potato').first);
      await tester.pump();

      expect(bagCount(controller.save, _bakedPotato), 3);
      expect(controller.message, contains('Baked Potato 10/10 handed in'));
      expectNoBank(tester);
    });
  });

  group('show step', () {
    testWidgets('shows the bag count and the amount to show, then Shown ✓', (tester) async {
      var closed = 0;
      final controller = await open(
        tester,
        bag(showing(), _bakedPotato, 3),
        _fennel,
        onClose: () => closed += 1,
      );

      expect(find.text('Baked Potato: you have 3/5'), findsOne);
      expect(find.text('Show 5 Baked Potato'), findsOne);

      await tester.tap(find.text('Show 5 Baked Potato'));
      await tester.pump();
      expect(find.text('You need 5 Baked Potato (you have 3).'), findsOne);
      expect(find.textContaining('placeholder'), findsNothing);
      expect(closed, 0);
      expectNoBank(tester);

      controller.commit(bag(controller.save, _bakedPotato, 5));
      await tester.pumpWidget(const SizedBox());
      final reopened = await open(tester, controller.save, _fennel, onClose: () => closed += 1);
      final ready = find.text('Show 5 Baked Potato');
      expect(find.text('Baked Potato: you have 5/5'), findsOne);
      await tester.tap(ready);
      await tester.pump();
      expect(closed, 1);
      expect(reopened.message, 'Shown ✓');
      expect(bagCount(reopened.save, _bakedPotato), 5);
    });

    testWidgets('a shown step reads Shown ✓ and is greyed out', (tester) async {
      final save = choose(bag(showing(), _bakedPotato, 5), _fennel, _fennelNode, 'DCH-9012');
      await open(tester, save, _fennel);

      expect(find.text('Baked Potato: Shown ✓'), findsOne);
      expect(find.text('Shown ✓'), findsOne);
      expect(button(tester, 'Shown ✓').onPressed, isNull);
      expect(find.text('Show 5 Baked Potato'), findsNothing);
    });

    testWidgets('only the bag counts', (tester) async {
      final save = showing().copyWith(
        bank: [const InventoryStack(itemId: _bakedPotato, quantity: 50)],
      );
      await open(tester, save, _fennel);

      expect(find.text('Baked Potato: you have 0/5'), findsOne);
      expectNoBank(tester);
    });
  });

  group('choices', () {
    testWidgets('disabled choices are greyed out and hidden ones are not shown', (tester) async {
      await open(tester, feastSixHandedIn(), _king);

      // DCH-9001: quest already active. DCH-9005: flag not set, not hidden.
      expect(button(tester, 'DCH-9001 label').onPressed, isNull);
      expect(button(tester, 'DCH-9005 label').onPressed, isNull);
      // DCH-9004: same condition, marked Hidden.
      expect(find.text('DCH-9004 label'), findsNothing);
      expect(button(tester, 'DCH-9003 label').onPressed, isNotNull);
    });

    testWidgets('a hidden locked choice in a view is never drawn', (tester) async {
      await pumpPanel(
        tester,
        DialogueWindow(
          view: const DialogueView(
            dialogueId: _king,
            nodeId: _kingNode,
            speakerName: 'King',
            npcId: 'NPC-9001',
            line: 'Well?',
            finished: false,
            choices: [
              DialogueChoiceView(choiceId: 'DCH-A', label: 'Open', enabled: true),
              DialogueChoiceView(choiceId: 'DCH-B', label: 'Secret', enabled: false, hidden: true),
              DialogueChoiceView(choiceId: 'DCH-C', label: 'Locked', enabled: false),
            ],
          ),
          text: DialogueText(db()),
          onChoose: (_) {},
          onClose: () {},
        ),
      );

      expect(find.text('Open'), findsOne);
      expect(find.text('Secret'), findsNothing);
      expect(button(tester, 'Locked').onPressed, isNull);
    });

    testWidgets('favourited items never grey out or hint a hand-in', (tester) async {
      var save = feastSixHandedIn();
      save = stacks(save, _bakedPotato, [(4, true)]);
      await open(tester, save, _king);

      expect(button(tester, 'Hand in 4 Baked Potato').onPressed, isNotNull);
      for (final text in shownText(tester)) {
        expect(text.toLowerCase(), isNot(contains('favour')), reason: text);
      }
    });

    testWidgets('a double tap sends one request', (tester) async {
      final pending = Completer<DialogueResult>();
      var calls = 0;
      final save = bag(feastSixHandedIn(), _bakedPotato, 7);
      await open(
        tester,
        save,
        _king,
        request: (view, choiceId, {required useFavourites}) {
          calls += 1;
          return pending.future;
        },
      );

      await tester.tap(find.text('Hand in 4 Baked Potato').first);
      await tester.tap(find.text('Hand in 4 Baked Potato').first);
      await tester.pump();
      expect(calls, 1);

      pending.complete(failed(save, 'not_available'));
      await tester.pump();
      await tester.tap(find.text('Hand in 4 Baked Potato').first);
      await tester.tap(find.text('Hand in 4 Baked Potato').first);
      await tester.pump();
      expect(calls, 2);
    });

    testWidgets('a double tap on the local engine hands in once', (tester) async {
      final controller = await open(tester, bag(feastSixHandedIn(), _bakedPotato, 7), _king);

      await tester.tap(find.text('Hand in 4 Baked Potato').first);
      await tester.tap(find.text('Hand in 4 Baked Potato').first);
      await tester.pump();

      expect(bagCount(controller.save, _bakedPotato), 3);
    });
  });

  group('full bag', () {
    testWidgets('names only the new slots the gifts need', (tester) async {
      // DCH-9025 grants Golden Spud, Potato and Baked Potato. Potato stacks onto
      // the bag, so 2 new slots are needed with 1 free.
      var save = bag(character(), _potato, 1);
      save = fillBag(save, 1);
      final controller = await open(tester, save, _gifts);
      final before = jsonEncode(controller.save.toJson());

      await tester.tap(find.text('DCH-9025 label'));
      await tester.pumpAndSettle();

      expect(find.text('Your bag is full. Make room for 2 more items and try again.'), findsOne);
      expect(jsonEncode(controller.save.toJson()), before);
      expectNoBank(tester);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Your bag is full'), findsNothing);
    });

    testWidgets('one missing slot reads singular', (tester) async {
      expect(DialogueText.bagFull(1), 'Your bag is full. Make room for 1 more item and try again.');
    });

    testWidgets('npcLine replaces the spoken line and keeps the count popup on top', (
      tester,
    ) async {
      const spoken = "Your pack's stuffed full, friend. Clear some space and come back to me.";
      var save = bag(character(), _potato, 1);
      save = fillBag(save, 1);
      await open(
        tester,
        save,
        _gifts,
        request: (view, choiceId, {required useFavourites}) async {
          return failed(
            save,
            'no_room',
            noRoom: const DialogueNoRoom(slotsNeeded: 2, slotsFree: 0, npcLine: spoken),
          );
        },
      );

      expect(find.text('DNODE-9021 line'), findsOne);
      await tester.tap(find.text('DCH-9025 label'));
      await tester.pumpAndSettle();

      expect(find.text(spoken), findsOne);
      expect(find.text(DialogueText.bagFull(2)), findsOne);
      expect(find.text('DNODE-9021 line'), findsNothing);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text(spoken), findsOne);
      expect(find.text(DialogueText.bagFull(2)), findsNothing);
      expect(find.text('DNODE-9021 line'), findsNothing);
    });

    testWidgets(
      'missing, empty, or whitespace npcLine leaves the spoken line and shows the popup',
      (tester) async {
        var save = bag(character(), _potato, 1);
        save = fillBag(save, 1);
        for (final npcLine in [null, '', '   ']) {
          await tester.pumpWidget(const SizedBox());
          await open(
            tester,
            save,
            _gifts,
            request: (view, choiceId, {required useFavourites}) async {
              return failed(
                save,
                'no_room',
                noRoom: DialogueNoRoom(slotsNeeded: 2, slotsFree: 0, npcLine: npcLine),
              );
            },
          );

          expect(find.text('DNODE-9021 line'), findsOne);
          await tester.tap(find.text('DCH-9025 label'));
          await tester.pumpAndSettle();

          expect(find.text('DNODE-9021 line'), findsOne);
          expect(find.text(DialogueText.bagFull(2)), findsOne);
          expect(find.textContaining("pack's stuffed"), findsNothing);
        }
      },
    );

    testWidgets('stack_full says the stack is full and never names a count', (tester) async {
      var save = bag(character(), _potato, 1);
      save = fillBag(save, 1);
      await open(
        tester,
        save,
        _gifts,
        request: (view, choiceId, {required useFavourites}) async {
          return failed(save, 'no_room', noRoom: const DialogueNoRoom(reason: 'stack_full'));
        },
      );

      await tester.tap(find.text('DCH-9025 label'));
      await tester.pumpAndSettle();

      expect(find.text(DialogueText.stackFull), findsOne);
      expect(find.textContaining('Make room'), findsNothing);
      expect(find.textContaining('cannot hold'), findsNothing);
    });
  });

  group('favourites', () {
    const prompt = DialogueText.favouritesPrompt;

    PlayerSave favouriteFeast() {
      var save = choose(character(), _king, _kingNode, 'DCH-9001');
      save = bag(save, _bakedPotato, 6);
      save = choose(save, _king, _kingNode, 'DCH-9002');
      save = stacks(save, _bakedPotato, [(4, true)]);
      return stacks(save, _cookedPerch, [(2, true)]);
    }

    testWidgets('asks first and lists every favourited item; No does nothing', (tester) async {
      final controller = await open(tester, favouriteFeast(), _king);
      final before = jsonEncode(controller.save.toJson());

      await tester.tap(find.text('Hand in 4 Baked Potato and 2 Cooked Perch').first);
      await tester.pumpAndSettle();

      expect(find.textContaining(prompt), findsOne);
      expect(find.textContaining('Baked Potato x4, Cooked Perch x2'), findsOne);
      expect(jsonEncode(controller.save.toJson()), before);
      expectNoBank(tester);

      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();

      expect(find.textContaining(prompt), findsNothing);
      expect(jsonEncode(controller.save.toJson()), before);
      expect(find.text('Baked Potato 6/10 handed in'), findsOne);
      expect(
        find.byWidgetPredicate((w) => w is Text && w.style?.color == Palette.danger),
        findsNothing,
      );
    });

    testWidgets('Yes resends the same choice with useFavourites for that request only', (
      tester,
    ) async {
      final sent = <(String, bool)>[];
      var save = favouriteFeast();
      late GameController controller;
      controller = await open(
        tester,
        save,
        _king,
        request: (view, choiceId, {required useFavourites}) async {
          sent.add((choiceId, useFavourites));
          final result = chooseDialogue(
            db(),
            controller.save,
            view.dialogueId,
            view.nodeId,
            choiceId,
            useFavourites: useFavourites,
          );
          if (result.ok) controller.commit(result.save);
          return result;
        },
      );

      await tester.tap(find.text('Hand in 4 Baked Potato and 2 Cooked Perch').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();

      expect(sent, [('DCH-9002', false), ('DCH-9002', true)]);
      expect(bagCount(controller.save, _bakedPotato), 0);
      expect(jsonEncode(controller.save.toJson()), isNot(contains('useFavourites')));

      // The yes is not remembered: the next favourited hand-in asks again.
      save = stacks(controller.save, _cookedPerch, [(3, true)]);
      controller.commit(save);
      await tester.pumpWidget(const SizedBox());
      sent.clear();
      controller = await open(
        tester,
        save,
        _king,
        request: (view, choiceId, {required useFavourites}) async {
          sent.add((choiceId, useFavourites));
          return chooseDialogue(
            db(),
            save,
            view.dialogueId,
            view.nodeId,
            choiceId,
            useFavourites: useFavourites,
          );
        },
      );
      await tester.tap(find.text('Hand in 3 Cooked Perch').first);
      await tester.pumpAndSettle();
      expect(sent, [('DCH-9002', false)]);
      expect(find.textContaining(prompt), findsOne);
    });

    testWidgets('Yes on the local engine commits the hand-in', (tester) async {
      final controller = await open(tester, favouriteFeast(), _king);

      await tester.tap(find.text('Hand in 4 Baked Potato and 2 Cooked Perch').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();

      expect(bagCount(controller.save, _bakedPotato), 0);
      expect(bagCount(controller.save, _cookedPerch), 0);
      expect(find.textContaining(prompt), findsNothing);
    });

    testWidgets('a full bag after Yes shows the bag popup, not the prompt again', (tester) async {
      final save = favouriteFeast();
      var calls = 0;
      await open(
        tester,
        save,
        _king,
        request: (view, choiceId, {required useFavourites}) async {
          calls += 1;
          return useFavourites
              ? failed(save, 'no_room', noRoom: const DialogueNoRoom(slotsNeeded: 3, slotsFree: 0))
              : failed(
                  save,
                  'confirm_favourites',
                  favourites: const [DialogueItemDelta(itemId: _bakedPotato, qty: 4)],
                );
        },
      );

      await tester.tap(find.text('Hand in 4 Baked Potato and 2 Cooked Perch').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(find.text('Your bag is full. Make room for 3 more items and try again.'), findsOne);
      expect(find.textContaining(prompt), findsNothing);
    });

    testWidgets('the prompt lists every entry the engine returns', (tester) async {
      final save = favouriteFeast();
      await open(
        tester,
        save,
        _king,
        request: (view, choiceId, {required useFavourites}) async => failed(
          save,
          'confirm_favourites',
          favourites: const [
            DialogueItemDelta(itemId: _bakedPotato, qty: 4),
            DialogueItemDelta(itemId: _cookedPerch, qty: 2),
            DialogueItemDelta(itemId: _potato, qty: 7),
          ],
        ),
      );

      await tester.tap(find.text('Hand in 4 Baked Potato and 2 Cooked Perch').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('Baked Potato x4, Cooked Perch x2, Potato x7'), findsOne);
    });
  });

  group('result codes', () {
    late PlayerSave save;
    setUp(() => save = bag(feastSixHandedIn(), _bakedPotato, 7));

    for (final (code, expected) in const [
      ('not_available', 'That isn’t available right now.'),
      ('action_failed', 'That can’t be done right now.'),
      ('invalid', 'That conversation can’t go on right now.'),
    ]) {
      testWidgets('$code is worded by the UI', (tester) async {
        await open(
          tester,
          save,
          _king,
          request: (view, choiceId, {required useFavourites}) async => failed(save, code),
        );
        await tester.tap(find.text('Hand in 4 Baked Potato').first);
        await tester.pump();
        expect(find.text(expected), findsOne);
        expect(find.textContaining('placeholder'), findsNothing);
      });
    }

    testWidgets('nothing_to_hand_in names what is still wanted', (tester) async {
      await open(tester, bag(feastSixHandedIn(), _bakedPotato, 0), _king);

      // DCH-9006 is enabled on quest_active alone, so it reaches the engine.
      final enabled = find.byWidgetPredicate(
        (w) => w is GameButton && w.label.startsWith('Bring') && w.onPressed != null,
      );
      await tester.tap(enabled);
      await tester.pump();
      expect(find.text('You have no Baked Potato to hand in.'), findsOne);
      expectNoBank(tester);
    });
  });

  test('no dialogue screen string mentions the bank', () {
    for (final path in ['lib/src/ui/dialogue_window.dart', 'lib/src/ui/dialogue_text.dart']) {
      expect(File(path).readAsStringSync().toLowerCase(), isNot(contains('bank')), reason: path);
    }
  });

  testWidgets('the reward popup shows before the wardrobe notice', (tester) async {
    final controller = buildController(database, seed: bag(feastSixHandedIn(), _bakedPotato, 7));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(420, 900));
    await tester.pump();
    expect(find.text('You found a Cosmetic!'), findsNothing);
    expect(find.text('Thank you'), findsNothing);

    final nav = tester.element(find.byType(AppShell));
    unawaited(
      showDialog<void>(
        context: nav,
        builder: (context) => Dialog(
          child: StandaloneDialogueHost(
            controller: controller,
            dialogueId: _king,
            onClose: () => Navigator.of(context).pop(),
            request: (view, choiceId, {required useFavourites}) async {
              final granted = grantCosmetic(controller.save, 'COS-0002');
              expect(granted.granted, isTrue);
              const completions = <QuestArrivalCompletion>[
                QuestArrivalCompletion(
                  questId: 'QST-9001',
                  questName: 'The feast',
                  rewards: <String>['Golden Spud'],
                  pendingSkillXp: 0,
                  message: 'Thank you.',
                ),
              ];
              // Same order as the local `_send` path: queue the reward, then commit.
              controller.noteDialogueQuestCompletions(completions);
              controller.commit(granted.save);
              return DialogueResult(
                ok: true,
                reason: '',
                save: granted.save,
                view: view,
                completed: true,
                message: null,
                questCompletions: completions,
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Hand in 4 Baked Potato').first);
    await tester.pump();
    for (var i = 0; i < 20 && find.text('Collect').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Thank you'), findsOne);
    expect(find.text('The feast'), findsOne);
    expect(find.text('Collect'), findsOne);
    await tester.tap(find.widgetWithText(GameButton, 'Collect'));
    await tester.pump();
    for (var i = 0; i < 20 && find.text('Collect').evaluate().isNotEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Collect'), findsNothing);
    expect(find.text('You found a Cosmetic!'), findsOne);
    expect(find.text('New Cosmetic'), findsOne);
  });
}
