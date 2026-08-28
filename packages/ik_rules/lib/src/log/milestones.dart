import 'package:ik_content/ik_content.dart';

import '../activity/xp.dart';
import '../js_compat.dart';
import '../save/generated/save_models.dart';

const String gatheringActionsStat = 'gathering_actions_completed';

const List<num> _skillThresholds = <num>[25, 50, 75, 100];
const List<num> _countThresholds = <num>[10000, 100000, 1000000, 1000000000];

class MilestoneLogRow {
  const MilestoneLogRow({
    required this.milestoneId,
    required this.track,
    required this.name,
    required this.note,
    required this.current,
    required this.required,
    required this.unlocked,
  });

  final String milestoneId;
  final String track;
  final String name;
  final String note;
  final num current;
  final num required;
  final bool unlocked;

  Map<String, Object?> toJson() => <String, Object?>{
    'milestoneId': milestoneId,
    'track': track,
    'name': name,
    'note': note,
    'current': current,
    'required': required,
    'unlocked': unlocked,
  };
}

String _formatCount(num value) {
  final whole = value.round();
  final text = jsNumberToString(whole);
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final fromEnd = text.length - i;
    if (i > 0 && fromEnd % 3 == 0) buffer.write(',');
    buffer.write(text[i]);
  }
  return buffer.toString();
}

num _lowestSkillLevel(GameDatabase db, PlayerSave save) {
  if (db.skills.isEmpty) return 0;
  return db.skills
      .map((skill) => getSkillProgress(save, jsString(skill.raw['Skill ID'])).level)
      .reduce((left, right) => left < right ? left : right);
}

MilestoneLogRow _countRow({
  required String track,
  required String Function(num threshold) nameFor,
  required num current,
  required num threshold,
}) {
  final unlocked = current >= threshold;
  return MilestoneLogRow(
    milestoneId: '$track-${jsNumberToString(threshold)}',
    track: track,
    name: nameFor(threshold),
    note: unlocked ? 'Reached' : '${_formatCount(current)} / ${_formatCount(threshold)}',
    current: current,
    required: threshold,
    unlocked: unlocked,
  );
}

List<MilestoneLogRow> milestoneLog(GameDatabase db, PlayerSave save) {
  final lowest = _lowestSkillLevel(db, save);
  final kills = jsNumber(save.statistics.values['monsters_killed'] ?? 0);
  final gold = jsNumber(save.statistics.values['gold_earned'] ?? 0);
  final gatherings = jsNumber(save.statistics.values[gatheringActionsStat] ?? 0);

  return [
    for (final threshold in _skillThresholds)
      MilestoneLogRow(
        milestoneId: 'skills-${jsNumberToString(threshold)}',
        track: 'skills',
        name: 'Every skill ${jsNumberToString(threshold)}',
        note: lowest >= threshold
            ? 'Reached'
            : 'Reach level ${jsNumberToString(threshold)} in every skill',
        current: lowest,
        required: threshold,
        unlocked: lowest >= threshold,
      ),
    for (final threshold in _countThresholds)
      _countRow(
        track: 'kills',
        nameFor: (n) => '${_formatCount(n)} monsters slain',
        current: kills,
        threshold: threshold,
      ),
    for (final threshold in _countThresholds)
      _countRow(
        track: 'gold',
        nameFor: (n) => '${_formatCount(n)} gold earned',
        current: gold,
        threshold: threshold,
      ),
    for (final threshold in _countThresholds)
      _countRow(
        track: 'gatherings',
        nameFor: (n) => '${_formatCount(n)} gatherings',
        current: gatherings,
        threshold: threshold,
      ),
  ];
}
