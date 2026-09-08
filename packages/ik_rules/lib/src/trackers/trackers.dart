import 'package:ik_content/ik_content.dart';

import '../activity/rewards.dart';
import '../save/generated/save_models.dart';

String lootTrackerKey(String kind, String sourceId) => '$kind:$sourceId';

/// Combat actions key by enemy so Cow and Bull stay separate.
({String kind, String sourceId}) lootSourceForAction(ActionRow action) {
  final targetId = action.targetId;
  if ((action.category == 'Combat' || action.targetType == 'Enemy') &&
      targetId != null &&
      targetId.isNotEmpty) {
    return (kind: 'enemy', sourceId: targetId);
  }
  return (kind: 'action', sourceId: action.actionId);
}

PlayerSave creditLootTracker(
  PlayerSave save,
  String kind,
  String sourceId,
  List<LootGrant> loot,
  num gold,
  num nowMs,
) {
  final key = lootTrackerKey(kind, sourceId);
  final existing = save.lootTrackers[key];
  final items = <String, num>{...?existing?.items};
  for (final grant in loot) {
    if (grant.itemId.isEmpty || grant.quantity <= 0) continue;
    items[grant.itemId] = (items[grant.itemId] ?? 0) + grant.quantity;
  }
  final next = LootTrackerEntry(
    key: key,
    kind: kind,
    sourceId: sourceId,
    startedAtMs: existing?.startedAtMs ?? nowMs,
    completions: (existing?.completions ?? 0) + 1,
    gold: (existing?.gold ?? 0) + gold,
    items: items,
  );
  return save.copyWith(lootTrackers: <String, LootTrackerEntry>{...save.lootTrackers, key: next});
}

PlayerSave creditXpTracker(PlayerSave save, String skillId, num xp, num nowMs) {
  if (xp <= 0) return save;
  final existing = save.xpTrackers[skillId];
  final next = XpTrackerEntry(
    skillId: skillId,
    startedAtMs: existing?.startedAtMs ?? nowMs,
    xpGained: (existing?.xpGained ?? 0) + xp,
  );
  return save.copyWith(xpTrackers: <String, XpTrackerEntry>{...save.xpTrackers, skillId: next});
}

PlayerSave creditXpAwards(PlayerSave save, List<({String skillId, num xp})> awards, num nowMs) {
  var next = save;
  num total = 0;
  for (final award in awards) {
    if (award.xp <= 0) continue;
    next = creditXpTracker(next, award.skillId, award.xp, nowMs);
    total += award.xp;
  }
  if (total > 0) next = creditXpTracker(next, totalXpTrackerId, total, nowMs);
  return next;
}

PlayerSave resetLootTracker(PlayerSave save, String key) {
  if (!save.lootTrackers.containsKey(key)) return save;
  return save.copyWith(
    lootTrackers: <String, LootTrackerEntry>{
      for (final entry in save.lootTrackers.entries)
        if (entry.key != key) entry.key: entry.value,
    },
  );
}

PlayerSave resetAllLootTrackers(PlayerSave save) {
  if (save.lootTrackers.isEmpty) return save;
  return save.copyWith(lootTrackers: const <String, LootTrackerEntry>{});
}

PlayerSave resetXpTracker(PlayerSave save, String skillId) {
  if (!save.xpTrackers.containsKey(skillId)) return save;
  return save.copyWith(
    xpTrackers: <String, XpTrackerEntry>{
      for (final entry in save.xpTrackers.entries)
        if (entry.key != skillId) entry.key: entry.value,
    },
  );
}

PlayerSave resetAllXpTrackers(PlayerSave save) {
  if (save.xpTrackers.isEmpty) return save;
  return save.copyWith(xpTrackers: const <String, XpTrackerEntry>{});
}

num xpPerHour(XpTrackerEntry entry, num nowMs) {
  final elapsed = nowMs - entry.startedAtMs;
  final window = elapsed < 1 ? 1 : elapsed;
  return (entry.xpGained / window) * 3600000;
}

List<LootTrackerEntry> sortedLootTrackers(PlayerSave save) {
  final rows = save.lootTrackers.values.toList();
  rows.sort((a, b) => a.startedAtMs.compareTo(b.startedAtMs));
  return rows;
}

List<XpTrackerEntry> sortedXpTrackers(PlayerSave save) {
  final rows = save.xpTrackers.values.toList();
  rows.sort((a, b) {
    if (a.skillId == totalXpTrackerId) return -1;
    if (b.skillId == totalXpTrackerId) return 1;
    return a.startedAtMs.compareTo(b.startedAtMs);
  });
  return rows;
}
