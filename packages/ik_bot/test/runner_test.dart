import 'package:ik_bot/ik_bot.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';
import 'package:test/test.dart';

GameDatabase contentDatabase() => assertGameDatabaseShape(contentDatabaseJson());

const num startMs = 1767225600000;
const String farmFields = 'ACT-0021';
const String farmPasture = 'ACT-0001';
const String potato = 'ITEM-0025';
const String bakedPotato = 'ITEM-0058';

void main() {
  late GameDatabase db;
  late num now;
  late MemorySaveStorage storage;
  late GameSession session;
  late BotRunner runner;

  setUp(() {
    db = contentDatabase();
    now = startMs;
    storage = MemorySaveStorage();
    session = GameSession(
      db: db,
      repository: SaveRepository(storage: storage, clock: () => now),
      clock: () => now,
      random: () => 0,
    );
    runner = BotRunner(session: session);
  });

  List<BotIntent> playUntil(bool Function() ready, {int limit = 80}) {
    final intents = <BotIntent>[];
    for (var pass = 0; pass < limit; pass++) {
      intents.add(runner.step());
      if (ready()) return intents;
      now += 5000;
    }
    fail('the bot never reached the state this step was waiting for');
  }

  void bootHuman() {
    session.boot();
    runner.ensureHuman('Wanderer0001');
  }

  test('a new human starts the farm fields, not the pasture fight', () {
    bootHuman();
    final intents = playUntil(
      () => session.save.currentActivityId == farmFields || runner.lastIntent is BotStartGather,
    );
    expect(intents.whereType<BotStartGather>(), isNotEmpty);
    final gather = intents.whereType<BotStartGather>().first;
    expect(gather.activityId, farmFields);
    expect(
      intents.whereType<BotStartGather>().map((row) => row.activityId),
      isNot(contains(farmPasture)),
    );
    expect(session.save.currentActivityId, isNot(farmPasture));
  });

  test('never starts a combat activity from the farm', () {
    bootHuman();
    final started = <String>[];
    for (var pass = 0; pass < 40; pass++) {
      final intent = runner.step();
      if (intent is BotStartGather) started.add(intent.activityId);
      now += 5000;
    }
    for (final activityId in started) {
      final activity = db.activities.firstWhere((row) => row.activityId == activityId);
      expect(activity.dangerWarningCombatLevel ?? 0, 0);
      final poolId = activity.poolId;
      if (poolId == null || poolId.isEmpty) continue;
      expect(
        eligiblePoolEntries(db, poolId).any((entry) => entry.action.category == 'Combat'),
        isFalse,
        reason: '$activityId is combat',
      );
    }
    expect(started, isNot(contains(farmPasture)));
  });

  test('travels to the Citadel and queues a cook when materials and play time exist', () {
    bootHuman();
    session.apply(addItemsToInventory(session.save, potato, 8).save);
    session.apply(session.save.copyWith(playTimeMs: citadelProductionIntervalMs));
    final intents = playUntil(
      () => runner.lastIntent is BotStartProduction || session.save.productionRecipeId != null,
    );
    expect(intents.whereType<BotTravel>(), isNotEmpty);
    expect(intents.whereType<BotTravel>().map((row) => row.locationId), contains(citadelGatewayId));
    final produce = intents.whereType<BotStartProduction>().first;
    expect(produce.activityId, 'ACT-0028');
    expect(produce.quantity, greaterThan(0));
    expect(session.save.currentLocationId, citadelProcessingId);
    expect(session.save.productionRecipeId, isNotNull);
  });

  test('buys a gather or production tool when gold covers it', () {
    bootHuman();
    session.apply(session.save.copyWith(gold: 2000));
    final intents = playUntil(() {
      return speedToolItemIds.any(
        (itemId) =>
            session.save.inventory.any((stack) => stack.itemId == itemId && stack.quantity > 0) ||
            session.save.equipment.slots.values.any((slot) => slot?.itemId == itemId),
      );
    });
    expect(intents.whereType<BotBuy>(), isNotEmpty);
    final buy = intents.whereType<BotBuy>().first;
    expect(speedToolItemIds, contains(buy.itemId));
    expect(
      session.save.inventory.any((stack) => speedToolItemIds.contains(stack.itemId)) ||
          session.save.equipment.slots.values.any(
            (slot) => slot != null && speedToolItemIds.contains(slot.itemId),
          ),
      isTrue,
    );
  });

  test('turns in a ready quest at the giver', () {
    bootHuman();
    session.apply(addItemsToInventory(session.save, bakedPotato, 10).save);
    session.apply(
      session.save.copyWith(
        quests: const <QuestProgress>[
          QuestProgress(questId: 'QST-0001', status: 'active', progress: 0),
        ],
      ),
    );
    final intents = playUntil(
      () => getQuestProgress(session.save, 'QST-0001').status == 'completed',
    );
    expect(intents.whereType<BotCompleteQuest>(), isNotEmpty);
    expect(intents.whereType<BotCompleteQuest>().first.questId, 'QST-0001');
    expect(session.save.currentLocationId, 'LOC-0016');
  });

  test('accepts Fennel\'s quest at the farm before gathering', () {
    bootHuman();
    playUntil(
      () =>
          getQuestProgress(session.save, 'QST-0006').status == 'active' ||
          runner.lastIntent is BotStartGather,
    );
    expect(getQuestProgress(session.save, 'QST-0006').status, 'active');
  });
}
