import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../quests/objectives.dart';
import '../quests/quests.dart';
import '../save/generated/save_models.dart';
import 'knowledge.dart';

/// Copy the clients share, so a line only ever has to be reworded once.
const String merchantTipLine = 'Here\u2019s some tips about artisanry';
const String merchantTipSpentLine = 'I\u2019ve already shared what I know about artisanry.';
const String _defaultMerchantLine = 'Welcome to my shop.';
const String _defaultNpcDescription = 'An inhabitant of Idale.';

/// Quests the giver pitches in their own words before the quest list is shown.
///
/// A quest without a pitch is simply accepted from the list.
const Map<String, String> _questPitchLines = <String, String>{
  'QST-0002':
      'I\u2019m tired of working in the kitchen, I just saw a lot for sale down '
      'the street, I\u2019m thinking of starting the alchemy shop '
      'I\u2019ve always dreamed of\u2026',
};

String? questPitchLine(String questId) => _questPitchLines[questId];

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
    required this.pitchLine,
    required this.lines,
    required this.goldOwned,
    required this.goldRequired,
    required this.ready,
  });

  final String questId;
  final String name;
  final String? summary;
  final String status;

  /// Replaces the objective list once the quest is done.
  final String completedNote;
  final String acceptLabel;

  /// The giver's own words, shown before accepting. Null accepts straight away.
  final String? pitchLine;
  final List<QuestDeliverLine> lines;
  final num goldOwned;
  final num goldRequired;
  final bool ready;

  Map<String, Object?> toJson() => <String, Object?>{
    'questId': questId,
    'name': name,
    'summary': summary,
    'status': status,
    'completedNote': completedNote,
    'acceptLabel': acceptLabel,
    'pitchLine': pitchLine,
    'lines': lines.map((line) => line.toJson()).toList(),
    'goldOwned': goldOwned,
    'goldRequired': goldRequired,
    'ready': ready,
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

NpcQuestBlock _questBlock(GameDatabase db, PlayerSave save, QuestRow quest) {
  final questId = quest['Quest ID'] as String;
  final displayName = quest['Display Name'];
  final name = displayName is String ? displayName : questId;
  final objective = questObjectiveProgress(db, save, quest);
  final pitch = questPitchLine(questId);
  final summary = quest['Summary'];
  return NpcQuestBlock(
    questId: questId,
    name: name,
    summary: summary is String ? summary : null,
    status: getQuestProgress(save, questId).status,
    completedNote: _completedNote(db, quest),
    acceptLabel: pitch == null ? 'Accept quest' : 'Start quest: $name',
    pitchLine: pitch,
    lines: objective.lines,
    goldOwned: objective.goldOwned,
    goldRequired: objective.goldRequired,
    ready: objective.ready,
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
        line: merchantTipLine,
        detail: '${jsLocaleNumber(merchantTipXp)} ${_skillName(db, artisanrySkillId)} XP',
      );
    }
    final description = npc.raw['Description'];
    return MerchantGreeting(
      line: npcId == generalStoreMerchantId
          ? merchantTipSpentLine
          : description is String
          ? description
          : _defaultMerchantLine,
      detail: null,
    );
  }

  final pitched = quests.firstWhereOrNull(
    (quest) => quest.pitchLine != null && quest.status == 'inactive',
  );
  final line = pitched?.pitchLine;
  if (pitched == null || line == null) return null;
  return QuestPitchGreeting(questId: pitched.questId, line: line, acceptLabel: pitched.acceptLabel);
}

NpcConversation npcConversation(GameDatabase db, PlayerSave save, NpcRow npc) {
  final npcId = npc.raw['NPC ID'] as String;
  final quests = questsForNpc(db, npcId).map((quest) => _questBlock(db, save, quest)).toList();
  final displayName = npc.raw['Display Name'];
  final role = npc.raw['Role'];
  final description = npc.raw['Description'];
  return NpcConversation(
    npcId: npcId,
    name: displayName is String ? displayName : npcId,
    role: role is String ? role : null,
    description: description is String ? description : _defaultNpcDescription,
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
