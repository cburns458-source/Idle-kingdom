import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../config.dart';
import '../js_compat.dart';
import '../quests/objectives.dart';
import '../quests/progress.dart';
import '../quests/quests.dart';
import '../save/generated/save_models.dart';
import 'knowledge.dart';

const String _fallbackMerchantTip = 'Here\u2019s some tips about artisanry';
const String _fallbackMerchantTipSpent = 'I\u2019ve already shared what I know about artisanry.';
const String _fallbackMerchantLine = 'Welcome to my shop.';
const String _fallbackNpcDescription = 'An inhabitant of Idale.';
const String _fallbackQuestActivePrompt = 'What else do you need?';

String merchantTipLine(GameDatabase db) =>
    configString(db, 'copy.merchant_tip', _fallbackMerchantTip);

String merchantTipSpentLine(GameDatabase db) =>
    configString(db, 'copy.merchant_tip_spent', _fallbackMerchantTipSpent);

/// Quests the giver pitches in their own words before the quest list is shown.
///
/// A quest without a pitch is simply accepted from the list.
String? questPitchLine(GameDatabase db, String questId) {
  final pitch = db.quests
      .firstWhereOrNull((row) => row['Quest ID'] == questId)?['Pitch'];
  return pitch is String && pitch.isNotEmpty ? pitch : null;
}

String? questTalkLine(GameDatabase db, String questId, String npcId) {
  final line = db.questDialogue
      .firstWhereOrNull((row) => row.questId == questId && row.npcId == npcId)
      ?.line;
  return line != null && line.isNotEmpty ? line : null;
}

String? skillForKnowledgeNpc(String npcId) {
  if (npcId == masterDwarfId) return smithingSkillId;
  if (npcId == archmageId) return arcanaSkillId;
  return null;
}

String _skillName(GameDatabase db, String skillId) {
  final displayName = db.skills
      .firstWhereOrNull((skill) => skill.raw['Skill ID'] == skillId)
      ?.raw['Display Name'];
  return displayName is String ? displayName : 'skill';
}

String _locationName(GameDatabase db, String locationId) {
  final displayName = db.locations
      .firstWhereOrNull((row) => row.raw['Location ID'] == locationId)
      ?.raw['Display Name'];
  return displayName is String ? displayName : locationId;
}

String? _mapNameForLocation(GameDatabase db, String locationId) {
  final mapId = db.locations
      .firstWhereOrNull((row) => row.raw['Location ID'] == locationId)
      ?.raw['Map ID'];
  if (mapId is! String) return null;
  final displayName = db.maps
      .firstWhereOrNull((row) => row.raw['Map ID'] == mapId)
      ?.raw['Display Name'];
  return displayName is String ? displayName : null;
}

String? _npcName(GameDatabase db, String npcId) {
  final displayName = db.npcs
      .firstWhereOrNull((row) => row.raw['NPC ID'] == npcId)
      ?.raw['Display Name'];
  return displayName is String ? displayName : null;
}

/// The dialogue an NPC opens with, shown over the panel.
sealed class NpcGreeting {
  const NpcGreeting();

  Map<String, Object?> toJson();
}

class MerchantGreeting extends NpcGreeting {
  const MerchantGreeting({required this.line, required this.detail});

  final String line;

  /// What listening is worth, when there is anything left to learn.
  final String? detail;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'merchant',
    'line': line,
    'detail': detail,
  };
}

class QuestPitchGreeting extends NpcGreeting {
  const QuestPitchGreeting({required this.questId, required this.line, required this.acceptLabel});

  final String questId;
  final String line;
  final String acceptLabel;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'quest_pitch',
    'questId': questId,
    'line': line,
    'acceptLabel': acceptLabel,
  };
}

/// A mentor's one-off project knowledge, and how to describe it.
class NpcMentorBlock {
  const NpcMentorBlock({required this.known, required this.knownNote, required this.learnLabel});

  final bool known;

  /// Shown once the knowledge is held.
  final String knownNote;
  final String learnLabel;

  Map<String, Object?> toJson() => <String, Object?>{
    'known': known,
    'knownNote': knownNote,
    'learnLabel': learnLabel,
  };
}

class NpcQuestBlock {
  const NpcQuestBlock({
    required this.questId,
    required this.name,
    required this.summary,
    required this.status,
    required this.completedNote,
    required this.acceptLabel,
    required this.donateLabel,
    required this.pitchLine,
    required this.lines,
    required this.progressLines,
    required this.goldOwned,
    required this.goldRequired,
    required this.ready,
    required this.canAccept,
    required this.canDonate,
    required this.donated,
    required this.canTurnIn,
    required this.canTalk,
    required this.talkLabel,
    required this.talkLine,
    required this.canBribe,
    required this.bribeLabel,
    required this.canChooseCombat,
    required this.combatLabel,
    required this.idlePrompt,
  });

  final String questId;
  final String name;
  final String? summary;
  final String status;

  /// Replaces the objective list once the quest is done.
  final String completedNote;
  final String acceptLabel;
  final String donateLabel;

  /// The giver's own words, shown before accepting. Null accepts straight away.
  final String? pitchLine;
  final List<QuestDeliverLine> lines;
  final List<QuestProgressLine> progressLines;
  final num goldOwned;
  final num goldRequired;
  final bool ready;
  final bool canAccept;
  final bool canDonate;
  final bool donated;
  final bool canTurnIn;
  final bool canTalk;
  final String talkLabel;
  final String? talkLine;
  final bool canBribe;
  final String bribeLabel;
  final bool canChooseCombat;
  final String combatLabel;

  /// Shown while the quest is active and no Talk / Bribe / Combat button is up.
  final String idlePrompt;

  Map<String, Object?> toJson() => <String, Object?>{
    'questId': questId,
    'name': name,
    'summary': summary,
    'status': status,
    'completedNote': completedNote,
    'acceptLabel': acceptLabel,
    'donateLabel': donateLabel,
    'pitchLine': pitchLine,
    'lines': lines.map((line) => line.toJson()).toList(),
    'progressLines': progressLines.map((line) => line.toJson()).toList(),
    'goldOwned': goldOwned,
    'goldRequired': goldRequired,
    'ready': ready,
    'canAccept': canAccept,
    'canDonate': canDonate,
    'donated': donated,
    'canTurnIn': canTurnIn,
    'canTalk': canTalk,
    'talkLabel': talkLabel,
    'talkLine': talkLine,
    'canBribe': canBribe,
    'bribeLabel': bribeLabel,
    'canChooseCombat': canChooseCombat,
    'combatLabel': combatLabel,
    'idlePrompt': idlePrompt,
  };
}

/// Everything a client needs to draw one NPC, with no game rules left in it.
class NpcConversation {
  const NpcConversation({
    required this.npcId,
    required this.name,
    required this.role,
    required this.description,
    required this.isMerchant,
    required this.shopId,
    required this.greeting,
    required this.mentor,
    required this.quests,
  });

  final String npcId;
  final String name;
  final String? role;
  final String description;
  final bool isMerchant;
  final String? shopId;
  final NpcGreeting? greeting;
  final NpcMentorBlock? mentor;
  final List<NpcQuestBlock> quests;

  Map<String, Object?> toJson() => <String, Object?>{
    'npcId': npcId,
    'name': name,
    'role': role,
    'description': description,
    'isMerchant': isMerchant,
    'shopId': shopId,
    'greeting': greeting?.toJson(),
    'mentor': mentor?.toJson(),
    'quests': quests.map((quest) => quest.toJson()).toList(),
  };
}

String _completedNote(GameDatabase db, QuestRow quest) {
  final unlocked = parseStructuredObjectives(quest).unlockLocationIds;
  if (unlocked.isEmpty) return 'Completed.';
  final opened = unlocked
      .map((locationId) {
        final mapName = _mapNameForLocation(db, locationId);
        final where = mapName == null ? '' : ' on the $mapName';
        return '${_locationName(db, locationId)} is open$where';
      })
      .join(', ');
  return 'Completed \u2014 $opened.';
}

NpcQuestBlock _questBlock(GameDatabase db, PlayerSave save, QuestRow quest, String npcId) {
  final questId = quest['Quest ID'] as String;
  final displayName = quest['Display Name'];
  final name = displayName is String ? displayName : questId;
  final objective = questObjectiveProgress(db, save, quest);
  final pitch = questPitchLine(db, questId);
  final summary = quest['Summary'];
  final parsed = parseStructuredObjectives(quest);
  final status = getQuestProgress(save, questId).status;
  final isGiver = quest['NPC ID'] == npcId;
  final turnInId = parsed.turnInNpcId ?? quest['NPC ID'];
  final talked = hasQuestFlag(save, questId, 'talk:$npcId');
  final chose =
      hasQuestFlag(save, questId, 'choice:bribe') || hasQuestFlag(save, questId, 'choice:combat');
  final needsTalkFirst = parsed.talkNpcIds.contains(npcId) && !talked;
  final donated = hasQuestFlag(save, questId, acceptGoldFlag);
  final needsDonate = parsed.acceptGoldCost > 0 && !donated;
  String acceptLabel;
  if (parsed.acceptGoldCost > 0) {
    acceptLabel = 'Start the quest $name?';
  } else if (pitch == null) {
    acceptLabel = 'Accept quest';
  } else {
    acceptLabel = 'Start quest: $name';
  }
  return NpcQuestBlock(
    questId: questId,
    name: name,
    summary: summary is String ? summary : null,
    status: status,
    completedNote: _completedNote(db, quest),
    acceptLabel: acceptLabel,
    donateLabel: 'Donate ${jsLocaleNumber(parsed.acceptGoldCost)} gold',
    pitchLine: pitch,
    lines: objective.lines,
    progressLines: objective.progressLines,
    goldOwned: objective.goldOwned,
    goldRequired: objective.goldRequired,
    ready: objective.ready,
    canAccept: isGiver && status == 'inactive' && !needsDonate,
    canDonate: isGiver && status == 'inactive' && needsDonate,
    donated: donated,
    canTurnIn: turnInId == npcId && status == 'active',
    canTalk: status == 'active' && parsed.talkNpcIds.contains(npcId) && !talked,
    talkLabel: 'Talk',
    talkLine: questTalkLine(db, questId, npcId),
    idlePrompt: configString(db, 'copy.quest_active_prompt', _fallbackQuestActivePrompt),
    canBribe:
        status == 'active' &&
        parsed.choiceNpcId == npcId &&
        parsed.bribeGold > 0 &&
        !chose &&
        !needsTalkFirst,
    bribeLabel: 'Bribe ${jsLocaleNumber(parsed.bribeGold)} gold',
    canChooseCombat: status == 'active' && parsed.choiceNpcId == npcId && !chose && !needsTalkFirst,
    combatLabel: 'Pressure the Guards',
  );
}

NpcMentorBlock? _mentorBlock(GameDatabase db, PlayerSave save, String npcId) {
  final skillId = skillForKnowledgeNpc(npcId);
  if (skillId == null) return null;
  final name = _skillName(db, skillId);
  return NpcMentorBlock(
    known: hasNpcKnowledge(save, npcId),
    knownNote: '$name projects are unlocked.',
    learnLabel: 'Learn $name projects',
  );
}

NpcGreeting? _greetingFor(
  GameDatabase db,
  PlayerSave save,
  NpcRow npc,
  List<NpcQuestBlock> quests,
) {
  final npcId = npc.raw['NPC ID'] as String;
  if (lowerOrEmpty(npc.raw['Role']) == 'merchant') {
    if (offersMerchantTip(save, npcId)) {
      return MerchantGreeting(
        line: merchantTipLine(db),
        detail: '${jsLocaleNumber(merchantTipXp)} ${_skillName(db, artisanrySkillId)} XP',
      );
    }
    final description = npc.raw['Description'];
    return MerchantGreeting(
      line: npcId == generalStoreMerchantId
          ? merchantTipSpentLine(db)
          : description is String
          ? description
          : configString(db, 'copy.default_merchant_line', _fallbackMerchantLine),
      detail: null,
    );
  }

  final pitched = quests.firstWhereOrNull(
    (quest) => quest.pitchLine != null && quest.status == 'inactive',
  );
  final line = pitched?.pitchLine;
  if (pitched == null || line == null) return null;
  return QuestPitchGreeting(
    questId: pitched.questId,
    line: line,
    acceptLabel: pitched.canDonate ? pitched.donateLabel : pitched.acceptLabel,
  );
}

NpcConversation npcConversation(GameDatabase db, PlayerSave save, NpcRow npc) {
  final npcId = npc.raw['NPC ID'] as String;
  final quests = <NpcQuestBlock>[];
  for (final quest in questsTouchingNpc(db, npcId)) {
    final isGiver = quest['NPC ID'] == npcId;
    final status = getQuestProgress(save, jsString(quest['Quest ID'])).status;
    if (!isGiver && status != 'active') continue;
    quests.add(_questBlock(db, save, quest, npcId));
  }
  final displayName = npc.raw['Display Name'];
  final role = npc.raw['Role'];
  final description = npc.raw['Description'];
  return NpcConversation(
    npcId: npcId,
    name: displayName is String ? displayName : npcId,
    role: role is String ? role : null,
    description: description is String
        ? description
        : configString(db, 'copy.default_npc_description', _fallbackNpcDescription),
    isMerchant: lowerOrEmpty(role) == 'merchant',
    shopId: shopIdForMerchant(db, npc),
    greeting: _greetingFor(db, save, npc, quests),
    mentor: _mentorBlock(db, save, npcId),
    quests: quests,
  );
}

/// Either the updated save with a line to announce, or why nothing happened.
class NpcActionResult {
  const NpcActionResult.ok({required this.save, required this.message}) : reason = null;

  const NpcActionResult.failed(this.reason) : save = null, message = null;

  bool get ok => reason == null;
  final PlayerSave? save;

  /// The line to show the player, present whenever [ok] is true.
  final String? message;
  final String? reason;

  Map<String, Object?> toJson() => ok
      ? <String, Object?>{'ok': true, 'message': message, 'save': save!.toJson()}
      : <String, Object?>{'ok': false, 'reason': reason};
}

/// Learns a mentor's projects, with the line to announce it.
///
/// The caller does not need to know which mentor teaches what: the message
/// names the skill the same way the button that offered it did.
NpcActionResult learnMentorProjects(GameDatabase db, PlayerSave save, String npcId) {
  final result = unlockNpcKnowledge(save, npcId);
  if (!result.ok) return NpcActionResult.failed(result.reason!);
  final skillId = skillForKnowledgeNpc(npcId);
  final name = skillId == null ? 'these' : _skillName(db, skillId);
  return NpcActionResult.ok(
    save: result.save!,
    message: 'The ${_npcName(db, npcId) ?? 'mentor'} unlocks all $name projects.',
  );
}

/// Takes the merchant's advice when their dialogue is dismissed.
///
/// Returns null when there was nothing left to learn, which lets a caller
/// dismiss the dialogue the same way either way.
NpcActionResult? takeMerchantTip(GameDatabase db, PlayerSave save, String npcId) {
  final claimed = claimMerchantTip(db, save, npcId);
  if (claimed == null) return null;
  return NpcActionResult.ok(
    save: claimed.save,
    message: 'Learned artisanry tips (+${jsLocaleNumber(claimed.xp)} XP).',
  );
}

/// Accepts a quest from an NPC's list, with the line to announce it.
NpcActionResult acceptQuestFromNpc(GameDatabase db, PlayerSave save, String questId) {
  final result = acceptQuest(db, save, questId);
  if (!result.ok) return NpcActionResult.failed(result.reason!);
  final quest = getQuest(db, questId);
  final displayName = quest?['Display Name'];
  return NpcActionResult.ok(
    save: result.save!,
    message: 'Accepted: ${displayName is String ? displayName : 'quest'}.',
  );
}

/// Pays AcceptGold without starting the quest.
NpcActionResult donateForQuestFromNpc(GameDatabase db, PlayerSave save, String questId) {
  final result = donateForQuest(db, save, questId);
  if (!result.ok) return NpcActionResult.failed(result.reason!);
  final quest = getQuest(db, questId);
  final cost = parseStructuredObjectives(quest ?? const <String, Object?>{}).acceptGoldCost;
  return NpcActionResult.ok(
    save: result.save!,
    message: 'Donated ${jsLocaleNumber(cost)} gold.',
  );
}

NpcActionResult talkWithQuestNpc(GameDatabase db, PlayerSave save, String npcId) {
  final next = applyQuestTalkProgress(db, save, npcId);
  return NpcActionResult.ok(save: next, message: 'You hear them out.');
}

NpcActionResult bribeForQuest(GameDatabase db, PlayerSave save, String questId) {
  final result = bribeQuestNpc(db, save, questId);
  if (!result.ok) return NpcActionResult.failed(result.reason!);
  return NpcActionResult.ok(save: result.save!, message: 'The purse changes hands.');
}

NpcActionResult chooseCombatForQuest(PlayerSave save, String questId) {
  final result = chooseQuestCombatRoute(save, questId);
  if (!result.ok) return NpcActionResult.failed(result.reason!);
  return NpcActionResult.ok(
    save: result.save!,
    message: 'The guards look nervous. Pressure them nearby.',
  );
}

NpcActionResult assignQuestSkillXp(GameDatabase db, PlayerSave save, String skillId, num amount) {
  final result = applyQuestBranchSkillXp(db, save, skillId, amount);
  if (!result.ok) return NpcActionResult.failed(result.reason!);
  return NpcActionResult.ok(
    save: result.save!,
    message: 'Gained ${jsLocaleNumber(amount)} ${_skillName(db, skillId)} XP.',
  );
}
