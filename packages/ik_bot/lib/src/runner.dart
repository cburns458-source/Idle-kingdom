import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

import 'intent.dart';
import 'policy.dart';

/// Human race granted to a new bot character.
const String botRaceId = 'RACE-0001';

/// Applies [BotPolicy] intents to a [GameSession] after each tick.
class BotRunner {
  BotRunner({required this.session, this.policy = const BotPolicy()});

  final GameSession session;
  final BotPolicy policy;

  BotMemory memory = const BotMemory();

  /// Last intent [step] chose, for tests and logs.
  BotIntent? lastIntent;

  GameDatabase get db => session.db;

  num get nowMs => session.clock();

  /// Names a nameless save and grants the Human starter kit.
  void ensureHuman(String name) {
    final cleaned = normalizeCharacterName(name) ?? name;
    var next = session.save;
    if (next.characterName == null || next.characterName!.trim().isEmpty) {
      next = next.copyWith(characterName: cleaned, appearance: defaultAppearance(db));
    }
    if (next.raceId == null) {
      final sworn = assignRace(db, next, botRaceId);
      if (sworn.ok) {
        session.apply(sworn.save!);
        return;
      }
    }
    if (!identical(next, session.save)) session.apply(next);
  }

  /// Ticks the session, picks one intent, and applies it.
  BotIntent step() {
    session.tick();
    final intent = policy.decide(db, session.save, nowMs, memory);
    lastIntent = intent;
    applyIntent(intent);
    return intent;
  }

  /// Applies [intent] without ticking. Tests use this after seeding a save.
  void applyIntent(BotIntent intent) {
    switch (intent) {
      case BotWait():
        break;
      case BotTravel(:final locationId):
        _travel(locationId);
      case BotStartGather(:final activityId):
        _startGather(activityId);
      case BotStartProduction(:final activityId, :final recipeId, :final quantity):
        _startProduction(activityId, recipeId, quantity);
      case BotCompleteProject(:final projectId):
        _completeProject(projectId);
      case BotBuy(:final shopId, :final itemId):
        _buy(shopId, itemId);
      case BotAcceptQuest(:final questId):
        _acceptQuest(questId);
      case BotCompleteQuest(:final questId):
        _completeQuest(questId);
    }
  }

  void _travel(String locationId) {
    final dest = db.locations.where((row) => row.locationId == locationId).firstOrNull;
    if (dest == null) return;
    final plan = session.travelTo(locationId, getLocationMapId(dest));
    if (plan is TravelTimed) {
      session.arrive(locationId);
    }
  }

  void _startGather(String activityId) {
    var started = requestActivityStart(db, session.save, activityId, nowMs, session.random);
    if (!started.ok) {
      final proposal = proposeAutoEquipForActivity(db, session.save, activityId, started.reason!);
      if (proposal != null) {
        final equipped = applyAutoEquipProposal(db, session.save, proposal);
        if (equipped.ok) session.apply(equipped.save!);
        started = requestActivityStart(db, session.save, activityId, nowMs, session.random);
      }
    }
    if (started.ok) session.apply(started.save!);
  }

  void _startProduction(String activityId, String recipeId, num quantity) {
    final started = requestProductionStart(db, session.save, activityId, recipeId, quantity, nowMs);
    if (!started.ok) return;
    session.apply(started.save!);
    memory = memory.withProduction(session.save.playTimeMs);
  }

  void _completeProject(String projectId) {
    final result = completeSpecialProject(db, session.save, projectId, 1, nowMs: nowMs);
    if (result.ok) session.apply(result.save!);
  }

  void _buy(String shopId, String itemId) {
    final result = confirmShopOffer(
      db,
      session.save,
      shopId,
      ShopOffer(buys: <ShopOfferLine>[ShopOfferLine(itemId: itemId, quantity: 1)]),
      nowMs: nowMs,
    );
    if (!result.ok) return;
    session.apply(result.save!);
    final equipped = equipItemFromInventory(db, session.save, itemId);
    if (equipped.ok) session.apply(equipped.save!);
  }

  void _acceptQuest(String questId) {
    final result = acceptQuest(db, session.save, questId);
    if (result.ok) session.apply(result.save!);
  }

  void _completeQuest(String questId) {
    final result = completeQuest(db, session.save, questId);
    if (result.ok) session.apply(result.save!);
  }
}
