import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/game_controller.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/dialogue_text.dart';
import 'package:idle_kingdoms/src/ui/npc_panel.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

/// Rose's kitchen, driven through [NpcPanel]'s default `completeQuest` + commit
/// path. These tests never pass [NpcPanel.turnInRequest].
const _roseId = 'NPC-0005';
const _kitchen = 'LOC-0023';
const _roseQuest = 'QST-0002';
const _rabbitsFoot = 'ITEM-0038';
const _fernleaf = 'ITEM-0031';
const _wildBerries = 'ITEM-0028';
const _weaselTail = 'ITEM-0042';
const _chefHat = 'ITEM-0165';
const _alchemy = 'SKL-0010';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  NpcRow rose() {
    return database.launch.npcs.firstWhere((row) => row.raw['NPC ID'] == _roseId);
  }

  InventoryStack stack(String itemId, {required int quantity, bool favourite = false}) =>
      InventoryStack(itemId: itemId, quantity: quantity, favorite: favourite ? true : null);

  PlayerSave roseReady({bool favourite = false, int deliverQty = 5}) {
    return startedCharacter(database).copyWith(
      currentLocationId: _kitchen,
      gold: 1500,
      inventory: [
        stack(_rabbitsFoot, quantity: deliverQty, favourite: favourite),
        stack(_fernleaf, quantity: deliverQty, favourite: favourite),
        stack(_wildBerries, quantity: deliverQty, favourite: favourite),
        stack(_weaselTail, quantity: deliverQty, favourite: favourite),
      ],
      quests: const [QuestProgress(questId: _roseQuest, status: 'active', progress: 0)],
    );
  }

  /// Keeps the four delivery piles (so turning in does not free a slot) and
  /// pads the rest of the bag. [free] empty slots remain.
  PlayerSave fillBag(PlayerSave save, int free) {
    final inventory = [...save.inventory.where((stack) => !stack.itemId.startsWith('ITEM-FILL-'))];
    for (var index = 0; inventory.length < inventorySlotLimit - free; index++) {
      inventory.add(InventoryStack(itemId: 'ITEM-FILL-$index', quantity: 1));
    }
    return save.copyWith(inventory: inventory);
  }

  /// Opens the panel and talks through Rose's first step so Turn in is showing.
  /// Does not pass [NpcPanel.turnInRequest], so [_sendTurnIn] runs `completeQuest`
  /// and `controller.commit` itself.
  Future<GameController> openTurnIn(WidgetTester tester, PlayerSave seed) async {
    final controller = buildController(database, seed: seed);
    addTearDown(controller.dispose);
    await pumpPanel(tester, NpcPanel(controller: controller, npc: rose(), onClose: () {}));
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Turn in'), findsOne);
    return controller;
  }

  /// Watches the default commit path. [NpcPanel] still applies the save locally;
  /// [submitGameCommand] is only a log (hosted play stays off).
  _CommitLog watchCommits(GameController controller) {
    final log = _CommitLog();
    controller.onSaveCommitted = (before, after) {
      log.saves.add(_snapshot(after));
    };
    controller.submitGameCommand = (command, [args = const <String, Object?>{}]) async {
      log.commands.add((command, Map<String, Object?>.of(args)));
      return null;
    };
    return log;
  }

  List<Map<String, Object?>> questCompleteArgs(_CommitLog log) => [
    for (final entry in log.commands)
      if (entry.$1 == 'quest_complete') entry.$2,
  ];

  num hatQty(PlayerSave save) => save.inventory
      .where((stack) => stack.itemId == _chefHat)
      .fold<num>(0, (sum, stack) => sum + stack.quantity);

  num alchemyXp(PlayerSave save) => getSkillProgress(save, _alchemy).xp;

  group('default commit path', () {
    testWidgets('an ok Turn in pays out once, even when the button is double-tapped', (
      tester,
    ) async {
      final controller = await openTurnIn(tester, roseReady());
      final log = watchCommits(controller);
      final alchemyBefore = alchemyXp(controller.save);

      // Two presses in the same turn, before the reward popup covers the
      // button. The second hits `_busy` rather than a second `completeQuest`.
      final turnIn = tester.widget<GameButton>(find.widgetWithText(GameButton, 'Turn in'));
      turnIn.onPressed!();
      turnIn.onPressed!();
      await tester.pumpAndSettle();

      expect(questCompleteArgs(log), [
        <String, Object?>{'questId': _roseQuest},
      ]);
      expect(log.saves, hasLength(1));
      expect(controller.save.gold, 500);
      expect(hatQty(controller.save), 1);
      expect(alchemyXp(controller.save), greaterThan(alchemyBefore));
      expect(getQuestProgress(controller.save, _roseQuest).status, 'completed');
      expect(controller.save.inventory.any((stack) => stack.itemId == _rabbitsFoot), isFalse);
      expect(controller.recentRewards, hasLength(1));
      expect(find.textContaining('Alchemy XP'), findsOne);
      expect(find.textContaining("Chef's hat"), findsOne);
      expect(find.text('Collect'), findsOne);
      expect(jsonEncode(controller.save.toJson()), isNot(contains('useFavourites')));

      await tester.tap(find.text('Collect'));
      await tester.pumpAndSettle();
      expect(questCompleteArgs(log), hasLength(1));
      expect(hatQty(controller.save), 1);
      expect(controller.save.gold, 500);
    });

    testWidgets('no_room names the slots the rewards need and commits nothing', (tester) async {
      // Qty 6 leaves each delivery pile in place, so turning in frees no slot.
      // Chef's hat then needs one new slot against a full bag.
      final seed = fillBag(roseReady(deliverQty: 6), 0);
      final controller = await openTurnIn(tester, seed);
      final log = watchCommits(controller);
      final before = _snapshot(controller.save);
      final inventoryBefore = jsonEncode([
        for (final stack in controller.save.inventory) stack.toJson(),
      ]);

      await tester.tap(find.text('Turn in'));
      await tester.pumpAndSettle();

      expect(find.text('Your bag is full. Make room for 1 more item and try again.'), findsOne);
      expect(_snapshot(controller.save), before);
      expect(
        jsonEncode([for (final stack in controller.save.inventory) stack.toJson()]),
        inventoryBefore,
      );
      expect(getQuestProgress(controller.save, _roseQuest).status, 'active');
      expect(controller.save.gold, 1500);
      expect(hatQty(controller.save), 0);
      expect(log.saves, isEmpty);
      expect(questCompleteArgs(log), isEmpty);
      expect(controller.recentRewards, isEmpty);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Your bag is full'), findsNothing);
      expect(_snapshot(controller.save), before);
      expect(log.saves, isEmpty);
    });

    testWidgets(
      'confirm_favourites: No commits nothing; Yes sends useFavourites once; the flag does not carry',
      (tester) async {
        final controller = await openTurnIn(tester, roseReady(favourite: true));
        final log = watchCommits(controller);
        final before = _snapshot(controller.save);

        await tester.tap(find.text('Turn in'));
        await tester.pumpAndSettle();
        expect(find.textContaining(DialogueText.favouritesPrompt), findsOne);
        expect(
          find.textContaining("Rabbit's foot x5, Fernleaf x5, Wild berries x5, Weasel tail x5"),
          findsOne,
        );
        expect(questCompleteArgs(log), isEmpty);
        expect(log.saves, isEmpty);

        await tester.tap(find.text('No'));
        await tester.pumpAndSettle();
        expect(_snapshot(controller.save), before);
        expect(getQuestProgress(controller.save, _roseQuest).status, 'active');
        expect(controller.save.gold, 1500);
        expect(hatQty(controller.save), 0);
        expect(questCompleteArgs(log), isEmpty);
        expect(log.saves, isEmpty);
        expect(find.text('Turn in'), findsOne);

        // A stored yes would skip the prompt on the next tap.
        await tester.tap(find.text('Turn in'));
        await tester.pumpAndSettle();
        expect(find.textContaining(DialogueText.favouritesPrompt), findsOne);
        expect(questCompleteArgs(log), isEmpty);

        await tester.tap(find.text('Yes'));
        await tester.pumpAndSettle();

        expect(questCompleteArgs(log), [
          <String, Object?>{'questId': _roseQuest, 'useFavourites': true},
        ]);
        expect(log.saves, hasLength(1));
        expect(controller.save.gold, 500);
        expect(hatQty(controller.save), 1);
        expect(getQuestProgress(controller.save, _roseQuest).status, 'completed');
        expect(jsonEncode(controller.save.toJson()), isNot(contains('useFavourites')));
        expect(find.text('Collect'), findsOne);
      },
    );
  });

  group('default commit path — more than one reward slot', () {
    late LoadedDatabase twoRewardDb;

    setUpAll(() {
      final raw = jsonDecode(
        File('../content/data/game-database.json').readAsStringSync(),
      ) as Map<String, Object?>;
      raw['Quests'] = [
        for (final row in raw['Quests']! as List)
          if (row is Map && row['Quest ID'] == _roseQuest)
            <String, Object?>{
              ...Map<String, Object?>.from(row),
              'Notes': '${row['Notes']}; RewardItem: ITEM-0026 x1',
            }
          else
            row,
      ];
      twoRewardDb = prepareDatabase(raw);
    });

    NpcRow roseTwo() {
      return twoRewardDb.launch.npcs.firstWhere((row) => row.raw['NPC ID'] == _roseId);
    }

    testWidgets('a Turn in needing more than one bag slot shows N more items', (tester) async {
      // Chef's hat plus Golden spud need two new slots. Qty 6 leaves each
      // delivery pile in place, so turning in frees none.
      var seed = startedCharacter(twoRewardDb).copyWith(
        currentLocationId: _kitchen,
        gold: 1500,
        inventory: [
          stack(_rabbitsFoot, quantity: 6),
          stack(_fernleaf, quantity: 6),
          stack(_wildBerries, quantity: 6),
          stack(_weaselTail, quantity: 6),
        ],
        quests: const [QuestProgress(questId: _roseQuest, status: 'active', progress: 0)],
      );
      seed = fillBag(seed, 0);
      final controller = buildController(twoRewardDb, seed: seed);
      addTearDown(controller.dispose);
      await pumpPanel(tester, NpcPanel(controller: controller, npc: roseTwo(), onClose: () {}));
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(find.text('Turn in'), findsOne);
      final log = watchCommits(controller);
      final before = _snapshot(controller.save);

      await tester.tap(find.text('Turn in'));
      await tester.pumpAndSettle();

      expect(find.text('Your bag is full. Make room for 2 more items and try again.'), findsOne);
      expect(_snapshot(controller.save), before);
      expect(getQuestProgress(controller.save, _roseQuest).status, 'active');
      expect(log.saves, isEmpty);
      expect(questCompleteArgs(log), isEmpty);
    });
  });
}

class _CommitLog {
  final List<(String, Map<String, Object?>)> commands = [];
  final List<String> saves = [];
}

String _snapshot(PlayerSave save) => jsonEncode(save.toJson());
