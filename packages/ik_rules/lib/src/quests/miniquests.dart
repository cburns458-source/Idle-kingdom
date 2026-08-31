import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import '../js_compat.dart';
import '../save/generated/save_models.dart';
import '../skills/totals.dart';
import '../time.dart';

const num _dayMs = 24 * 60 * 60 * 1000;

String? noteFieldValue(String? notes, String pattern) {
  return RegExp(pattern, caseSensitive: false).firstMatch(notes ?? '')?.group(1);
}

num requiredTotalLevelFromNotes(String? notes) {
  final raw = noteFieldValue(notes, r'RequiresTotalLevel:\s*(\d+)');
  if (raw == null) return 0;
  final level = num.tryParse(raw);
  return level != null && level.isFinite ? level : 0;
}

bool isMiniquest(Map<String, Object?> quest) {
  final notes = quest['Notes'] is String ? quest['Notes']! as String : '';
  return RegExp(r'(?:^|;)\s*Miniquest\b', caseSensitive: false).hasMatch(notes) ||
      RegExp(r'(?:^|;)\s*HideFromQuestLog\b', caseSensitive: false).hasMatch(notes);
}

bool hideFromQuestLog(Map<String, Object?> quest) => isMiniquest(quest);

num? miniquestRepeatMs(Map<String, Object?> quest) {
  final notes = quest['Notes'] is String ? quest['Notes']! as String : '';
  final days = noteFieldValue(notes, r'Repeatable:\s*(\d+)\s*d');
  if (days != null) {
    final count = num.tryParse(days);
    if (count != null && count.isFinite && count > 0) return count * _dayMs;
  }
  final weekly = jsString(quest['Repeatable']).toLowerCase();
  if (weekly == 'weekly' || weekly == 'yes') return 7 * _dayMs;
  return null;
}

bool meetsTotalLevelRequirement(PlayerSave save, String? notes) {
  final required = requiredTotalLevelFromNotes(notes);
  return required <= 0 || totalLevel(save) >= required;
}

num? miniquestLastCompletedAt(PlayerSave save, String questId) {
  final stamp = save.miniquestCompletedAt[questId];
  if (stamp == null) return null;
  final ms = jsDateParse(stamp);
  return ms.isFinite ? ms : null;
}

PlayerSave recordMiniquestCompletion(PlayerSave save, String questId, num nowMs) {
  return save.copyWith(
    miniquestCompletedAt: {...save.miniquestCompletedAt, questId: isoFromMs(nowMs)},
  );
}

String formatDurationRemaining(num ms) {
  final remaining = ms < 0 ? 0 : ms.floor();
  final days = (remaining / _dayMs).floor();
  final hours = ((remaining % _dayMs) / (60 * 60 * 1000)).floor();
  final minutes = ((remaining % (60 * 60 * 1000)) / (60 * 1000)).floor();
  if (days >= 1) {
    if (hours > 0) {
      return '$days day${days == 1 ? '' : 's'} $hours hour${hours == 1 ? '' : 's'}';
    }
    return '$days day${days == 1 ? '' : 's'}';
  }
  if (hours >= 1) return '$hours hour${hours == 1 ? '' : 's'}';
  final shown = minutes < 1 ? 1 : minutes;
  return '$shown minute${shown == 1 ? '' : 's'}';
}

num? miniquestRepeatReadyAt(PlayerSave save, Map<String, Object?> quest) {
  final last = miniquestLastCompletedAt(save, jsString(quest['Quest ID']));
  final repeatMs = miniquestRepeatMs(quest);
  if (last == null || repeatMs == null) return null;
  return last + repeatMs;
}

bool miniquestCanRepeat(PlayerSave save, Map<String, Object?> quest, num nowMs) {
  final readyAt = miniquestRepeatReadyAt(save, quest);
  return readyAt == null || nowMs >= readyAt;
}

class MiniQuestLogRow {
  const MiniQuestLogRow({
    required this.questId,
    required this.name,
    required this.detail,
    required this.repeatable,
    required this.repeatEveryLabel,
    required this.repeatLabel,
    required this.ready,
  });

  final String questId;
  final String name;
  final String detail;
  final bool repeatable;
  final String? repeatEveryLabel;
  final String repeatLabel;
  final bool ready;

  Map<String, Object?> toJson() => <String, Object?>{
    'questId': questId,
    'name': name,
    'detail': detail,
    'repeatable': repeatable,
    'repeatEveryLabel': repeatEveryLabel,
    'repeatLabel': repeatLabel,
    'ready': ready,
  };
}

String? _repeatEveryLabel(Map<String, Object?> quest) {
  final ms = miniquestRepeatMs(quest);
  if (ms == null) return null;
  if (ms == 7 * _dayMs) return 'Every 7 days';
  final days = (ms / _dayMs).round();
  if (days >= 1) return 'Every $days day${days == 1 ? '' : 's'}';
  return null;
}

List<MiniQuestLogRow> miniQuestLog(GameDatabase db, PlayerSave save, [num? nowMs]) {
  final clock = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  return db.quests
      .where(isMiniquest)
      .where((quest) {
        final notes = quest['Notes'] is String ? quest['Notes']! as String : null;
        return meetsTotalLevelRequirement(save, notes);
      })
      .map((quest) {
        final questId = jsString(quest['Quest ID']);
        final npc = db.npcs.firstWhereOrNull((row) => row.raw['NPC ID'] == quest['NPC ID']);
        final npcName = npc?.raw['Display Name'] is String
            ? npc!.raw['Display Name']! as String
            : 'NPC';
        final ready = miniquestCanRepeat(save, quest, clock);
        final readyAt = miniquestRepeatReadyAt(save, quest);
        final last = miniquestLastCompletedAt(save, questId);
        final repeatable = miniquestRepeatMs(quest) != null;
        var repeatLabel = 'Available now';
        if (repeatable && last != null && !ready && readyAt != null) {
          repeatLabel = 'Repeat in ${formatDurationRemaining(readyAt - clock)}';
        } else if (repeatable && last != null && ready) {
          repeatLabel = 'Can be repeated now';
        }
        final summary = quest['Summary'];
        return MiniQuestLogRow(
          questId: questId,
          name: jsString(quest['Display Name']),
          detail: '${summary is String ? summary : 'No summary.'} · $npcName',
          repeatable: repeatable,
          repeatEveryLabel: _repeatEveryLabel(quest),
          repeatLabel: repeatLabel,
          ready: ready,
        );
      })
      .toList();
}
