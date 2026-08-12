import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../save/generated/save_models.dart';

const String masterDwarfId = 'NPC-0003';
const String archmageId = 'NPC-0004';
const String smithingSkillId = 'SKL-0011';
const String arcanaSkillId = 'SKL-0013';

List<NpcRow> npcsAtLocation(GameDatabase db, String locationId) {
  return db.npcs.where((npc) => npc.raw['Location ID'] == locationId).toList();
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
  if (npcId != masterDwarfId && npcId != archmageId) {
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

String? shopIdForMerchant(GameDatabase db, NpcRow npc) {
  if (lowerOrEmpty(npc.raw['Role']) != 'merchant') return null;
  final shop = db.shops.firstWhereOrNull((row) => row.raw['Location ID'] == npc.raw['Location ID']);
  final shopId = shop?.raw['Shop ID'];
  return shopId is String ? shopId : null;
}
