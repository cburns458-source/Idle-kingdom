import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

import 'hud_level_pref.dart';
import 'hud_title_pref.dart';
import 'local_player_art.dart';
import 'map_travel_pref.dart';

/// A journey in progress, which the client animates itself.
class TravelInFlight {
  const TravelInFlight({
    required this.fromLocationId,
    required this.toLocationId,
    required this.startedAtMs,
    required this.durationMs,
  });

  final String fromLocationId;
  final String toLocationId;
  final num startedAtMs;
  final num durationMs;

  double progressAt(num nowMs) {
    if (durationMs <= 0) return 1;
    return math.min(1, math.max(0, (nowMs - startedAtMs) / durationMs));
  }
}

/// The last killing blow, kept so the stage can hold sprites before swapping.
class CombatOutcomeHold {
  const CombatOutcomeHold({
    required this.enemyId,
    required this.outcome,
    required this.startedAtMs,
    required this.playerHp,
    required this.enemyHp,
  });

  final String enemyId;

  /// `victory` or `defeat`.
  final String outcome;
  final num startedAtMs;
  final num playerHp;
  final num enemyHp;
}

/// A finished craft, held so the production stage can pop the item icon.
class CraftPopup {
  const CraftPopup({
    required this.itemId,
    required this.displayName,
    required this.seq,
    required this.shownAtMs,
  });

  final String itemId;
  final String displayName;

  /// Bumps each craft so a new pop can restart even when the item repeats.
  final int seq;

  /// When the pop appeared, so it can leave on its own.
  final num shownAtMs;
}

/// Food eaten after a win, held so the stage can float the heal.
class HealPopup {
  const HealPopup({required this.amount, required this.shownAtMs, required this.seq});

  final num amount;
  final num shownAtMs;

  /// Bumps each eat so a new pop can restart even when the amount repeats.
  final int seq;
}

/// The screen-facing half of the session.
///
/// The rules and the tick live in `ik_runtime`; this holds the things that are
/// only true of a screen — the last few reward lines, the current message, the
/// journey being animated — and notifies listeners once per frame. Player
/// intents call the shared rules and hand the result to [GameSession.apply], so
/// nothing on a screen can put a save into storage by another route.
class GameController extends ChangeNotifier {
  GameController({
    required this.database,
    required this.session,
    LocalPlayerArt? localArt,
    MapTravelPref? mapTravel,
    HudLevelPref? hudLevel,
    HudTitlePref? hudTitle,
  }) : localArt = localArt ?? LocalPlayerArt(),
       mapTravel = mapTravel ?? MapTravelPref(),
       hudLevel = hudLevel ?? HudLevelPref(),
       hudTitle = hudTitle ?? HudTitlePref();

  final LoadedDatabase database;

  /// The headless session: the save, the tick, and the write pipeline.
  final GameSession session;

  /// Client-only PNG override for this device's player sprite.
  final LocalPlayerArt localArt;

  /// Client-only toggle for the map-node travel tween.
  final MapTravelPref mapTravel;

  /// Client-only HUD toggle between total level and total XP.
  final HudLevelPref hudLevel;

  /// Client-only HUD toggle for the equipped character title.
  final HudTitlePref hudTitle;

  /// How many completed actions the reward strip keeps.
  static const int _rewardHistory = 3;

  final List<ActionRewardBundle> _recentRewards = <ActionRewardBundle>[];
  String? _message;
  String? _activityError;
  TravelInFlight? _travel;
  double _travelProgress = 0;
  UnattendedResult? _awaySummary;
  bool _returningFromAway = false;
  CosmeticUnlockNotice? _cosmeticUnlock;
  String? _discoveryNotice;
  List<QuestArrivalCompletion> _pendingQuestCompletions = <QuestArrivalCompletion>[];
  List<SkillLevelUpNotice> _pendingSkillLevelUps = <SkillLevelUpNotice>[];
  AutoEquipProposal? _autoEquip;
  CombatRoundEvent? _lastRound;
  num? _lastRoundAtMs;
  int _roundSeq = 0;
  CraftPopup? _craftPopup;
  HealPopup? _healPopup;
  CombatOutcomeHold? _outcomeHold;
  num? _liveEnemyHp;

  GameDatabase get db => database.launch;
  DatabaseIndexes get indexes => database.launchIndexes;
  PlayerSave get save => session.save;

  List<ActionRewardBundle> get recentRewards => List.unmodifiable(_recentRewards);
  String? get message => _message;
  String? get activityError => _activityError;

  /// Visit-complete quests waiting for the location-page reward popup.
  List<QuestArrivalCompletion> takePendingQuestCompletions() {
    final pending = List<QuestArrivalCompletion>.of(_pendingQuestCompletions);
    _pendingQuestCompletions = <QuestArrivalCompletion>[];
    return pending;
  }

  /// Skill gains waiting for the level-up popup.
  List<SkillLevelUpNotice> takePendingSkillLevelUps() {
    final pending = List<SkillLevelUpNotice>.of(_pendingSkillLevelUps);
    _pendingSkillLevelUps = <SkillLevelUpNotice>[];
    return pending;
  }

  void _queueSkillLevelUps(PlayerSave before, PlayerSave after) {
    _pendingSkillLevelUps.addAll(skillLevelUpsBetween(db, before, after));
  }

  /// Pressure the Guards: set the combat flag and start the fight when standing at the barracks.
  NpcActionResult chooseQuestCombat(String questId) {
    return chooseCombatForQuest(db, save, questId, session.clock(), _random);
  }

  /// Pushes a completed action or project onto the live reward strip.
  void noteReward(ActionRewardBundle bundle) {
    _recentRewards.insert(0, bundle);
    if (_recentRewards.length > _rewardHistory) _recentRewards.removeLast();
  }

  /// Instant projects toast a receipt and also land on the same strip as ticks.
  void noteProjectCompletion(ProjectCompleteResult result) {
    if (!result.ok || result.save == null) return;
    final skillId = result.skillId;
    final xp = skillId == null
        ? null
        : summarizeXpReward(db, result.save!, skillId, result.xpGained, result.leveledUpTo);
    final outputId = result.outputItemId;
    final loot = outputId == null || outputId.isEmpty
        ? const <LootGrant>[]
        : [
            LootGrant(
              itemId: outputId,
              quantity: result.outputQty,
              displayName: result.outputLabel ?? outputId,
            ),
          ];
    if (xp == null && loot.isEmpty) return;
    noteReward(
      ActionRewardBundle(
        id: 'project-${session.clock()}',
        xpRewards: [?xp],
        loot: loot,
        goldGained: 0,
      ),
    );
  }

  /// True while a Standard Production queue is waiting for bag space.
  bool get productionInventoryFull {
    final recipeId = save.productionRecipeId;
    if (recipeId == null) return false;
    final recipe = getRecipe(db, recipeId);
    if (recipe == null) return false;
    final itemId = recipe.raw['Output Item ID'];
    final qty = recipe.raw['Output Quantity'];
    final skillId = recipe.raw['Skill ID'];
    if (itemId is! String || qty is! num || skillId is! String) return false;
    return !canFitItemQuantity(save, itemId, productionOutputReservePerCraft(skillId, qty));
  }

  TravelInFlight? get travel => _travel;
  double get travelProgress => _travelProgress;

  /// The catch-up from the last boot, until the player dismisses it.
  UnattendedResult? get awaySummary => _awaySummary;

  /// True while the return overlay is covering the world after catch-up.
  bool get returningFromAway => _returningFromAway;

  /// How long the return overlay stays up before the away summary.
  static const int returningHoldMs = 700;

  /// A cosmetic that was just unlocked and has not been shown off yet.
  CosmeticUnlockNotice? get cosmeticUnlock => _cosmeticUnlock;

  /// A one-shot find (Kingswoods Sling) that has not been shown off yet.
  String? get discoveryNotice => _discoveryNotice;

  /// The tool an activity wants, offered rather than demanded.
  AutoEquipProposal? get autoEquip => _autoEquip;

  /// The last resolved combat round, kept so the stage can float damage.
  CombatRoundEvent? get lastRound => _lastRound;

  /// Bumps when [lastRound] is replaced, so a floater can restart its layout.
  int get lastRoundSeq => _roundSeq;

  /// How long craft, heal, and damage pops stay on the stage.
  static const int stagePopupHoldMs = 1000;

  /// How long a finished craft's item icon stays over the workstation.
  static const int craftPopupHoldMs = stagePopupHoldMs;

  /// How long the green heal pop stays after a victory eat.
  static const int healPopupHoldMs = stagePopupHoldMs;

  /// How long player and enemy hit numbers stay up.
  static const int combatFloaterHoldMs = stagePopupHoldMs;

  /// The last finished craft, or null once its second is up.
  CraftPopup? get craftPopup {
    final popup = _craftPopup;
    if (popup == null) return null;
    if (session.clock() - popup.shownAtMs >= craftPopupHoldMs) return null;
    return popup;
  }

  /// The last victory eat, or null once its second is up.
  HealPopup? get healPopup {
    final popup = _healPopup;
    if (popup == null) return null;
    if (session.clock() - popup.shownAtMs >= healPopupHoldMs) return null;
    return popup;
  }

  /// How long the killing blow stays on screen before "defeated" or Recovering.
  static const int combatBlowHoldMs = 500;

  /// How long "defeated" stays up after the blow hold. Total ~1s between kills.
  static const int combatDefeatedBannerMs = 500;

  num get _holdElapsedMs {
    final hold = _outcomeHold;
    if (hold == null) return double.infinity;
    return session.clock() - hold.startedAtMs;
  }

  /// True for the first half-second after a killing blow, while sprites stay up.
  bool get combatBlowHold {
    final hold = _outcomeHold;
    if (hold == null) return false;
    return _holdElapsedMs < combatBlowHoldMs;
  }

  /// True after the blow hold, while the "defeated" banner is up.
  bool get defeatedFlash {
    final hold = _outcomeHold;
    if (hold == null || hold.outcome != 'victory') return false;
    final elapsed = _holdElapsedMs;
    return elapsed >= combatBlowHoldMs && elapsed < combatBlowHoldMs + combatDefeatedBannerMs;
  }

  /// True while a death blow is still on screen, before Recovering replaces it.
  bool get showingDeathHold {
    final hold = _outcomeHold;
    return hold != null && hold.outcome == 'defeat' && combatBlowHold;
  }

  /// Recovering UI waits out the death-blow hold so the last hit is visible.
  bool get showRecoveringStage => isRecovering && !showingDeathHold;

  /// Enemy to draw during a hold or banner; otherwise the live save's foe.
  String? get stagedEnemyId {
    if (combatBlowHold || defeatedFlash) {
      return _outcomeHold?.enemyId ?? lastRound?.enemyId;
    }
    return save.combatEnemyId;
  }

  num get stagedPlayerHp {
    if (showingDeathHold) return _outcomeHold?.playerHp ?? 0;
    return save.currentHp;
  }

  num get stagedEnemyHp {
    if (combatBlowHold || defeatedFlash) return _outcomeHold?.enemyHp ?? 0;
    return save.combatEnemyHp ?? 0;
  }

  /// Damage numbers stay for one second, then drop.
  bool get showLastRoundFloaters {
    final round = _lastRound;
    final shownAt = _lastRoundAtMs;
    if (round == null || shownAt == null) return false;
    return session.clock() - shownAt < combatFloaterHoldMs;
  }

  /// How far the current combat round has run, from 0 to 1.
  ///
  /// Derived from `combatRoundStartedAt` and the configured round length; the
  /// shell's frame tick is what makes this move.
  double get combatRoundProgress {
    if (isRecovering || combatBlowHold || defeatedFlash) return 0;
    final startedAt = save.combatRoundStartedAt;
    if (startedAt == null || startedAt.isEmpty) return 0;
    final roundMs = configNumber(db, 'combat_round_duration', 4) * 1000;
    final started = jsDateParse(startedAt);
    if (!started.isFinite || roundMs <= 0) return 0;
    return ((session.clock() - started) / roundMs).clamp(0, 1).toDouble();
  }

  /// How far the death pause has run, from 0 to 1, matching the round bar.
  double get deathPauseProgress {
    final remaining = deathPauseRemainingMs;
    final total = configNumber(db, 'death_pause', 30) * 1000;
    if (total <= 0) return 1;
    return ((total - remaining) / total).clamp(0, 1).toDouble();
  }

  double get actionProgress => session.actionProgress.toDouble();
  num get deathPauseRemainingMs => session.deathPauseRemaining;
  bool get isRecovering => deathPauseRemainingMs > 0;

  LocationRow? get location => indexes.locationsById[save.currentLocationId];

  /// Bytes of the local PNG override, if this device has one.
  Uint8List? get localPlayerPng => localArt.bytes;

  /// Whether the map plays a short walk before the player arrives.
  bool get mapTravelAnimation => mapTravel.enabled;

  void setMapTravelAnimation(bool value) {
    if (mapTravel.enabled == value) return;
    mapTravel.setEnabled(value);
    notifyListeners();
  }

  /// Whether the HUD identity line shows total XP instead of total level.
  bool get hudShowTotalXp => hudLevel.showTotalXp;

  void toggleHudShowTotalXp() {
    hudLevel.toggle();
    notifyListeners();
  }

  bool get showEatButton => save.settings.showEatButton;

  void setShowEatButton(bool value) {
    if (save.settings.showEatButton == value) return;
    commit(save.copyWith(settings: save.settings.copyWith(showEatButton: value)));
  }

  num get eatHealthThresholdPercent =>
      clampEatHealthThresholdPercent(save.settings.eatHealthThresholdPercent);

  bool get eatHealthThresholdAsPercent => save.settings.eatHealthThresholdAsPercent;

  void setEatHealthThresholdPercent(num value) {
    final next = clampEatHealthThresholdPercent(value);
    if (save.settings.eatHealthThresholdPercent == next) return;
    commit(save.copyWith(settings: save.settings.copyWith(eatHealthThresholdPercent: next)));
  }

  void setEatHealthThresholdAsPercent(bool value) {
    if (save.settings.eatHealthThresholdAsPercent == value) return;
    commit(save.copyWith(settings: save.settings.copyWith(eatHealthThresholdAsPercent: value)));
  }

  void setEatHealthThresholdHp(num hp, num maxHp) {
    final cap = maxHp <= 0 ? 1 : maxHp;
    final percent = clampEatHealthThresholdPercent((hp / cap) * 100);
    setEatHealthThresholdPercent(percent);
  }

  /// Manual eat from the bag or food slot. Returns a refusal, or null on success.
  String? eatFood({int? inventoryIndex}) {
    final result = inventoryIndex == null
        ? eatEquippedFood(db, save)
        : eatInventoryFood(db, save, inventoryIndex);
    if (!result.ok) return result.reason;
    commit(result.save!);
    _healPopup = HealPopup(
      amount: result.healed,
      shownAtMs: session.clock(),
      seq: (_healPopup?.seq ?? 0) + 1,
    );
    notifyListeners();
    return null;
  }

  /// Whether the HUD identity line includes the equipped title.
  bool get showTitleOnHud => hudTitle.showTitle;

  void setShowTitleOnHud(bool value) {
    if (hudTitle.showTitle == value) return;
    hudTitle.setShowTitle(value);
    notifyListeners();
  }

  /// Stores a PNG for this client only. Returns a reason when it is refused.
  String? applyLocalPlayerPng(Uint8List bytes) {
    final error = localArt.setPng(bytes);
    if (error == null) notifyListeners();
    return error;
  }

  /// Drops the PNG override so the bundled adventurer shows again.
  void resetLocalPlayerPng() {
    if (!localArt.hasOverride) return;
    localArt.clear();
    notifyListeners();
  }

  /// Keeps the boot's catch-up if it actually credited something.
  ///
  /// A fresh character, or a return after a few seconds, has nothing to report
  /// and should not be met with a summary panel.
  void adoptBoot(SessionBoot boot) {
    final away = boot.unattended;
    _awaySummary = boot.created || !away.hasCreditedWork ? null : away;
    _returningFromAway = !boot.created && away.effectiveElapsedMs > 0;
    _offerKingswoodsSling();
  }

  /// Covers a long hide the same way a cold boot does, but only when catch-up
  /// actually finished work. A short lock never reaches here.
  void _adoptResumeCatchUp(UnattendedResult away) {
    _awaySummary = away.hasCreditedWork ? away : null;
    _returningFromAway = away.hasCreditedWork;
    _clearStageFx();
    _recentRewards.clear();
    _message = null;
    _offerKingswoodsSling();
  }

  void finishReturningFromAway() {
    if (!_returningFromAway) return;
    _returningFromAway = false;
    notifyListeners();
  }

  /// Loads the account save, including catch-up for time away.
  ///
  /// [nowMs] should be the server clock when playing hosted, so catch-up is
  /// fair against a skewed device clock.
  void adoptAccountSave(PlayerSave incoming, {num? nowMs}) {
    adoptBoot(session.adoptAccount(incoming, nowMs: nowMs));
    notifyListeners();
  }

  /// Drops the character after sign-out or a kick from another device.
  void resetUnsigned() {
    session.resetUnsigned();
    _awaySummary = null;
    _returningFromAway = false;
    _message = null;
    _activityError = null;
    notifyListeners();
  }

  void dismissAwaySummary() {
    _awaySummary = null;
    notifyListeners();
  }

  /// Queues the unlock popup for the first of [grants].
  ///
  /// One purchase can unlock several cosmetics, and popups stacked over each
  /// other read worse than one popup and a wardrobe holding the rest.
  void noteCosmeticUnlocks(List<ShopCosmeticGrant> grants) {
    if (grants.isEmpty) return;
    final grant = grants.first;
    _cosmeticUnlock = cosmeticUnlockNotice(db, grant.cosmeticId, grant.isFirstEver);
    notifyListeners();
  }

  void dismissCosmeticUnlock() {
    _cosmeticUnlock = null;
    notifyListeners();
  }

  void dismissDiscoveryNotice() {
    _discoveryNotice = null;
    notifyListeners();
  }

  void clearMessages() {
    _message = null;
    _activityError = null;
    notifyListeners();
  }

  /// Optional hook after a save lands (skill XP, combat, etc.).
  void Function(PlayerSave before, PlayerSave after)? onSaveCommitted;

  /// Stores the save a panel's intent produced, and repaints.
  ///
  /// Panels call the shared rules themselves and pass the result here, which is
  /// the only way a save reaches storage.
  void commit(PlayerSave next) {
    final previous = save;
    session.apply(next);
    _queueSkillLevelUps(previous, save);
    onSaveCommitted?.call(previous, save);
    notifyListeners();
  }

  /// Reports why an intent was refused, in the place activity errors appear.
  void report(String? reason) {
    _activityError = reason;
    notifyListeners();
  }

  /// Says what an intent did, in the place tick messages appear.
  void announce(String text) {
    _message = text;
    notifyListeners();
  }

  /// [commit] for anything that changed the loadout, so max HP follows the gear.
  void commitLoadout(PlayerSave next) =>
      commit(withRecalculatedVitals(db, trackActiveEquipmentPreset(next)));

  /// Advances the game by one frame. The shell drives this from a ticker, so it
  /// stops when the app is backgrounded. A long hide is batch-resolved like a
  /// boot and covered; a short lock stays on the live tick.
  void tick() {
    if (save.combatEnemyId != null) {
      _liveEnemyHp = save.combatEnemyHp;
    }
    final previous = save;
    final result = session.tick();
    if (result.awayCatchUp case final away?) {
      _adoptResumeCatchUp(away);
      _queueSkillLevelUps(previous, save);
      onSaveCommitted?.call(previous, save);
      notifyListeners();
      return;
    }
    for (final event in result.events) {
      _applyEvent(event);
    }
    _offerKingswoodsSling();
    _expireStageFx();
    _advanceTravel();
    _queueSkillLevelUps(previous, save);
    onSaveCommitted?.call(previous, save);
    // A frame always repaints: the progress bars and timers are read from the
    // clock, so they move even on the ticks where nothing was due.
    notifyListeners();
  }

  void _applyEvent(SessionEvent event) {
    switch (event) {
      case RewardsEvent(bundle: final bundle):
        noteReward(bundle);
      case MessageEvent(text: final text):
        _message = text;
      case ActivityStoppedEvent(reason: final reason):
        _activityError = reason;
        _clearStageFx();
      case InventoryFullEvent():
        _activityError = 'Inventory full — free a slot to keep crafting.';
      case CraftCompletedEvent(itemId: final itemId, displayName: final displayName):
        _craftPopup = CraftPopup(
          itemId: itemId,
          displayName: displayName,
          seq: (_craftPopup?.seq ?? 0) + 1,
          shownAtMs: session.clock(),
        );
      case FoodHealedEvent(healed: final healed):
        _healPopup = HealPopup(
          amount: healed,
          shownAtMs: session.clock(),
          seq: (_healPopup?.seq ?? 0) + 1,
        );
      case final CombatRoundEvent round:
        _lastRound = round;
        _lastRoundAtMs = session.clock();
        _roundSeq += 1;
        if (round.outcome == 'victory' || round.outcome == 'defeat') {
          _outcomeHold = CombatOutcomeHold(
            enemyId: round.enemyId,
            outcome: round.outcome,
            startedAtMs: session.clock(),
            playerHp: round.outcome == 'defeat' ? 0 : save.currentHp,
            enemyHp: round.outcome == 'victory' ? 0 : (_liveEnemyHp ?? 0),
          );
        } else {
          _outcomeHold = null;
        }
      case EnemyDefeatedEvent():
      case PlayerDefeatedEvent():
      case RecoveredEvent():
      case CritterSpawnedEvent():
        break;
    }
  }

  void _clearStageFx() {
    _lastRound = null;
    _lastRoundAtMs = null;
    _craftPopup = null;
    _healPopup = null;
    _outcomeHold = null;
    _liveEnemyHp = null;
  }

  void _expireStageFx() {
    final now = session.clock();
    if (_craftPopup != null && now - _craftPopup!.shownAtMs >= craftPopupHoldMs) {
      _craftPopup = null;
    }
    if (_healPopup != null && now - _healPopup!.shownAtMs >= healPopupHoldMs) {
      _healPopup = null;
    }
  }

  void _advanceTravel() {
    final journey = _travel;
    if (journey == null) return;
    final nowMs = session.clock();
    _travelProgress = journey.progressAt(nowMs);
    if (_travelProgress < 1) return;
    _travel = null;
    _travelProgress = 0;
    final claimedSling = save.claimedKingswoodsSling;
    final ownedSling = saveOwnsSling(save);
    _showArrival(session.arrive(journey.toLocationId));
    _noteKingswoodsSling(claimedBefore: claimedSling, ownedBefore: ownedSling);
  }

  /// Starts or replaces the primary activity at the current location.
  ///
  /// When the only thing missing is a tool the bag already holds, this asks
  /// rather than refuses: [autoEquip] carries the offer until it is answered.
  void startActivity(String activityId, {bool allowAutoEquip = true}) {
    final result = requestActivityStart(db, save, activityId, session.clock(), _random);
    if (!result.ok) {
      // Nothing is startable during a death pause, so there is nothing to offer.
      if (allowAutoEquip && !isRecovering) {
        final proposal = proposeAutoEquipForActivity(db, save, activityId, result.reason!);
        if (proposal != null) {
          _autoEquip = proposal;
          _activityError = null;
          notifyListeners();
          return;
        }
      }
      _activityError = result.reason;
      notifyListeners();
      return;
    }
    _autoEquip = null;
    session.apply(result.save!);
    _recentRewards.clear();
    _activityError = null;
    _message = null;
    _clearStageFx();
    notifyListeners();
  }

  /// Instant Temple heal. The location screen shows the result as a popup.
  BlessResult receiveBlessing() {
    final result = requestBlessing(db, save, session.clock());
    if (!result.ok) {
      _activityError = result.reason;
      notifyListeners();
      return result;
    }
    session.apply(result.save!);
    _activityError = null;
    notifyListeners();
    return result;
  }

  /// Equips the offered tool and starts what wanted it.
  ///
  /// The second start cannot ask again: the tool is on, and if that was not
  /// enough the player deserves the reason instead of another prompt.
  void confirmAutoEquip() {
    final proposal = _autoEquip;
    if (proposal == null) return;
    _autoEquip = null;
    final equipped = applyAutoEquipProposal(db, save, proposal);
    if (!equipped.ok) {
      _activityError = equipped.reason;
      notifyListeners();
      return;
    }
    session.apply(withRecalculatedVitals(db, equipped.save!));
    startActivity(proposal.activityId, allowAutoEquip: false);
  }

  /// Turns the offer down, leaving the refusal that prompted it on screen.
  void declineAutoEquip() {
    final proposal = _autoEquip;
    if (proposal == null) return;
    _autoEquip = null;
    _activityError = proposal.failureReason;
    notifyListeners();
  }

  /// Pockets whatever is loitering at the current location.
  void collectCritterHere() {
    final result = collectCritter(save, save.currentLocationId);
    if (!result.ok) return;
    commit(result.save!);
    announce(result.message!);
  }

  void toggleFavorite(String activityId) {
    commit(toggleFavoriteActivity(save, save.currentLocationId, activityId));
  }

  void stopActivity() {
    final result = requestActivityStop(db, save, session.clock());
    if (!result.ok) {
      _activityError = result.reason;
      notifyListeners();
      return;
    }
    session.apply(result.save!);
    _activityError = null;
    _clearStageFx();
    notifyListeners();
  }

  /// Travels to [destinationId], reporting whether the request was accepted.
  bool travelTo(String destinationId, String browseMapId) {
    if (_travel != null) return false;
    final nowMs = session.clock();
    final from = save.currentLocationId;
    final claimedSling = save.claimedKingswoodsSling;
    final ownedSling = saveOwnsSling(save);
    final plan = session.travelTo(destinationId, browseMapId);
    switch (plan) {
      case TravelBlocked():
        return false;
      case TravelInstant(arrival: final arrival):
        _recentRewards.clear();
        _showArrival(arrival);
        _noteKingswoodsSling(claimedBefore: claimedSling, ownedBefore: ownedSling);
      case TravelTimed(durationMs: final durationMs):
        _recentRewards.clear();
        _travel = TravelInFlight(
          fromLocationId: from,
          toLocationId: destinationId,
          startedAtMs: nowMs,
          durationMs: durationMs,
        );
        _travelProgress = 0;
        notifyListeners();
    }
    return true;
  }

  /// Travels into the player's guild hall from the Guilds screen.
  bool travelToGuildHall() {
    if (_travel != null) return false;
    final plan = session.travelToGuildHall();
    switch (plan) {
      case TravelBlocked():
        return false;
      case TravelInstant(arrival: final arrival):
        _recentRewards.clear();
        _showArrival(arrival);
      case TravelTimed():
        return false;
    }
    return true;
  }

  /// Forces the habitat Critter to appear at the current location.
  String? debugSpawnCritter() {
    final result = spawnCritterAtLocation(save, save.currentLocationId, session.clock());
    if (!result.ok) return result.reason;
    commit(result.save!);
    return '${result.critter!.displayName} appeared.';
  }

  /// Swaps race after the first pick. Does not re-grant a starter kit.
  String? debugChangeRace(String raceId) {
    final result = assignRace(db, save, raceId);
    if (!result.ok) return result.reason;
    commit(result.save!);
    return 'Race is now ${raceDisplayName(db, raceId) ?? raceId}.';
  }

  /// Adds [quantity] of [itemId], as many as the bag will take.
  String? debugGrantItem(String itemId, num quantity) {
    final name = indexes.itemsById[itemId]?.displayName ?? itemId;
    final before = _ownedQuantity(save, itemId);
    final next = addItemToInventory(save, itemId, quantity);
    final added = _ownedQuantity(next, itemId) - before;
    if (added <= 0) return 'Could not add $name.';
    commit(next);
    return 'Added $added $name.';
  }

  /// Raises [skillId] by [levels], stopping at the XP curve cap.
  String? debugAddSkillLevels(String skillId, num levels) {
    if (levels <= 0) return 'Pick how many levels to add.';
    final name = indexes.skillsById[skillId]?.displayName ?? skillId;
    final current = getSkillProgress(save, skillId);
    final target = current.level + levels;
    final result = raiseSkillToMinimumLevel(save, db, skillId, target);
    if (!result.raised) {
      return current.level >= _maxSkillLevel
          ? '$name is already at the level cap.'
          : 'Could not raise $name.';
    }
    commit(result.save);
    final next = getSkillProgress(result.save, skillId);
    return '$name is now level ${next.level}.';
  }

  /// Lowers [skillId] by [levels], stopping at 1.
  String? debugRemoveSkillLevels(String skillId, num levels) {
    if (levels <= 0) return 'Pick how many levels to remove.';
    final name = indexes.skillsById[skillId]?.displayName ?? skillId;
    final current = getSkillProgress(save, skillId);
    if (current.level <= 1) return '$name is already at level 1.';
    final target = current.level - levels < 1 ? 1 : current.level - levels;
    commit(_withSkillLevel(save, skillId, target));
    return '$name is now level $target.';
  }

  /// Sets every skill back to level 1.
  String? debugResetAllSkills() {
    var next = save;
    for (final skill in save.skills) {
      next = _withSkillLevel(next, skill.skillId, 1);
    }
    commit(next);
    return 'Every skill is back at level 1.';
  }

  num get _maxSkillLevel => db.xpCurve.isEmpty ? 1 : db.xpCurve.last.level;

  PlayerSave _withSkillLevel(PlayerSave current, String skillId, num level) {
    final target = level < 1 ? 1 : level;
    num xp = 0;
    for (final row in db.xpCurve) {
      if (row.level == target) {
        xp = row.totalXpAtLevel;
        break;
      }
    }
    final skills = [...current.skills];
    final index = skills.indexWhere((skill) => skill.skillId == skillId);
    final progress = SkillProgress(skillId: skillId, level: target, xp: xp);
    if (index < 0) {
      skills.add(progress);
    } else {
      skills[index] = progress;
    }
    return current.copyWith(skills: skills);
  }

  static num _ownedQuantity(PlayerSave current, String itemId) {
    return current.inventory.fold<num>(
      0,
      (sum, stack) => stack.itemId == itemId ? sum + stack.quantity : sum,
    );
  }

  /// Names a new character, gives them a look, and grants their race's kit.
  ///
  /// Returns the reason it was refused, or null on success.
  String? createCharacter(String name, String raceId, {PlayerAppearance? appearance}) {
    final cleaned = normalizeCharacterName(name);
    if (cleaned == null) return 'Enter a name to continue.';
    final named = save.copyWith(characterName: cleaned, appearance: appearance);
    final assigned = assignRace(db, named, raceId);
    if (!assigned.ok) return assigned.reason;
    session.apply(assigned.save!);
    notifyListeners();
    return null;
  }

  void _showArrival(TravelArrival arrival) {
    _message = arrival.forcedActivityId != null ? arrival.message : null;
    _activityError = arrival.blockedReason != null ? arrival.message : null;
    if (arrival.questCompletions.isNotEmpty) {
      _pendingQuestCompletions = List<QuestArrivalCompletion>.of(arrival.questCompletions);
      for (final completion in arrival.questCompletions) {
        final bundle = completion.rewardBundle;
        if (bundle != null) noteReward(bundle);
      }
    }
    notifyListeners();
  }

  void _offerKingswoodsSling() {
    final result = maybeGrantKingswoodsSling(db, save);
    if (result.granted) {
      session.apply(result.save);
      _discoveryNotice = result.message;
      return;
    }
    if (result.save.claimedKingswoodsSling != save.claimedKingswoodsSling) {
      session.apply(result.save);
    }
  }

  void _noteKingswoodsSling({required bool claimedBefore, required bool ownedBefore}) {
    if (claimedBefore || ownedBefore || !save.claimedKingswoodsSling || !saveOwnsSling(save)) {
      return;
    }
    _discoveryNotice = kingswoodsSlingFoundMessage;
    notifyListeners();
  }

  double _random() => _rng.nextDouble();
  final math.Random _rng = math.Random();
}
