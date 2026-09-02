import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../activity/xp.dart';
import '../js_compat.dart';
import '../quests/miniquests.dart';
import '../quests/quests.dart';
import '../save/generated/save_models.dart';
import 'roaming.dart';

const String masterDwarfId = 'NPC-0003';
const String archmageId = 'NPC-0004';
const String quillId = 'NPC-0002';
const String smithingSkillId = 'SKL-0011';
const String arcanaSkillId = 'SKL-0013';

/// The general store merchant, who points travelers toward Quill.
const String generalStoreMerchantId = 'NPC-0007';
const String artisanrySkillId = 'SKL-0012';
const num merchantTipXp = 11000;

const String quillLockedReason =
    'Locked — find Quill to learn how to make bows and quivers. '
    'The General Store merchant knows where he was last seen.';

const String quillMissingReason = 'Speak with Quill to learn how to make bows and quivers.';

const String fennelId = 'NPC-0014';
const String gettingStartedQuestId = 'QST-0006';
const String wizardStudiesQuestId = 'QST-0005';
const String archmageHmph = 'Hmph.';
const String fennelWelcome =
    'Welcome to the lands. I am Fennel. This farm is a good place to start — harvest, cook, and fight are all close by. Come talk to me when you want to learn the rest.';

String? npcHideAfterQuestId(NpcRow npc) {
  final notes = npc.notes ?? '';
  final match = RegExp(r'HideAfterQuest:\s*(QST-\d+)', caseSensitive: false).firstMatch(notes);
  return match?.group(1)?.toUpperCase();
}

bool npcVisibleForSave(NpcRow npc, PlayerSave save) {
  if (!meetsTotalLevelRequirement(save, npc.notes)) return false;
  final questId = npcHideAfterQuestId(npc);
  if (questId == null) return true;
  return getQuestProgress(save, questId).status != 'completed';
}

List<NpcRow> npcsAtLocation(GameDatabase db, String locationId, [num? nowMs]) {
  final clock = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  return db.npcs.where((npc) => npcLocationAt(npc, clock) == locationId).toList();
}

List<NpcRow> npcsAtLocationForSave(
  GameDatabase db,
  PlayerSave save,
  String locationId, [
  num? nowMs,
]) {
  return npcsAtLocation(
    db,
    locationId,
    nowMs,
  ).where((npc) => npcVisibleForSave(npc, save)).toList();
}

bool fennelIntroPending(PlayerSave save) {
  return !save.hasSeenFennelIntro && save.currentLocationId == 'LOC-0001' && save.raceId != null;
}

bool hasNpcKnowledge(PlayerSave save, String npcId) => save.unlockedNpcIds.contains(npcId);

class UnlockNpcResult {
  const UnlockNpcResult.ok(this.save, {required this.alreadyHad}) : reason = null;

  const UnlockNpcResult.failed(this.reason) : save = null, alreadyHad = false;

  bool get ok => reason == null;
  final PlayerSave? save;
  final bool alreadyHad;
  final String? reason;
}

UnlockNpcResult unlockNpcKnowledge(PlayerSave save, String npcId) {
  if (npcId != masterDwarfId && npcId != archmageId && npcId != quillId) {
    return const UnlockNpcResult.failed('This NPC does not teach projects.');
  }
  if (hasNpcKnowledge(save, npcId)) {
    return UnlockNpcResult.ok(save, alreadyHad: true);
  }
  return UnlockNpcResult.ok(
    save.copyWith(unlockedNpcIds: [...save.unlockedNpcIds, npcId]),
    alreadyHad: false,
  );
}

String? knowledgeNpcForSkill(String skillId) {
  if (skillId == smithingSkillId) return masterDwarfId;
  if (skillId == arcanaSkillId) return archmageId;
  return null;
}

/// Whether the mentor for a skill has been met, and who to look for if not.
class ProjectKnowledge {
  const ProjectKnowledge.ok() : npcId = null, npcName = null;

  const ProjectKnowledge.missing({required this.npcId, required this.npcName});

  bool get ok => npcId == null;
  final String? npcId;
  final String? npcName;
}

ProjectKnowledge hasProjectKnowledge(GameDatabase db, PlayerSave save, String skillId) {
  final npcId = knowledgeNpcForSkill(skillId);
  if (npcId == null) return const ProjectKnowledge.ok();
  if (hasNpcKnowledge(save, npcId)) return const ProjectKnowledge.ok();
  final npc = db.npcs.firstWhereOrNull((row) => row.raw['NPC ID'] == npcId);
  final displayName = npc?.raw['Display Name'];
  return ProjectKnowledge.missing(
    npcId: npcId,
    npcName: displayName is String ? displayName : 'mentor',
  );
}

/// Bow and quiver artisanry, taught by Quill rather than a skill-wide mentor.
bool isQuillTaughtName(String displayName) {
  final name = displayName.trim().toLowerCase();
  return name == 'quiver' || name.endsWith(' quiver') || name == 'bow' || name.endsWith(' bow');
}

bool isQuillTaughtProject(ProjectRow project) {
  final name = project.raw['Display Name'];
  return name is String && isQuillTaughtName(name);
}

bool hasQuillProjectKnowledge(PlayerSave save, ProjectRow project) {
  return !isQuillTaughtProject(project) || hasNpcKnowledge(save, quillId);
}

bool hasClaimedMerchantTip(PlayerSave save, String npcId) {
  return save.claimedMerchantTipIds.contains(npcId);
}

/// The general store no longer teaches artisanry; Quill does that now.
bool offersMerchantTip(PlayerSave save, String npcId) {
  return npcId == generalStoreMerchantId && !hasClaimedMerchantTip(save, npcId) && false;
}

/// The XP a merchant's advice was worth, and the save that records the claim.
class MerchantTipResult {
  const MerchantTipResult({required this.save, required this.xp});

  final PlayerSave save;
  final num xp;

  Map<String, Object?> toJson() => <String, Object?>{'save': save.toJson(), 'xp': xp};
}

/// Takes the merchant's one-off artisanry advice.
///
/// Grants the XP and records the claim together, so listening twice cannot pay
/// twice. Returns null when there was nothing to claim, which is what a caller
/// that dismisses the dialogue unconditionally relies on.
MerchantTipResult? claimMerchantTip(GameDatabase db, PlayerSave save, String npcId) {
  if (!offersMerchantTip(save, npcId)) return null;
  final applied = applyXp(save, db, artisanrySkillId, merchantTipXp);
  return MerchantTipResult(
    save: applied.save.copyWith(claimedMerchantTipIds: [...save.claimedMerchantTipIds, npcId]),
    xp: merchantTipXp,
  );
}

String? shopIdForMerchant(GameDatabase db, NpcRow npc) {
  if (lowerOrEmpty(npc.raw['Role']) != 'merchant') return null;
  final shop = db.shops.firstWhereOrNull((row) => row.raw['Location ID'] == npc.raw['Location ID']);
  final shopId = shop?.raw['Shop ID'];
  return shopId is String ? shopId : null;
}
