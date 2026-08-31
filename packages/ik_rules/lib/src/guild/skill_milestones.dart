// Guild chat announcements when a member crosses skill thresholds.

class GuildSkillMilestoneSettings {
  const GuildSkillMilestoneSettings({
    required this.enabled,
    required this.levelStart,
    required this.levelStep,
    required this.xpStartMillion,
    required this.xpStepMillion,
  });

  final bool enabled;
  final num levelStart;
  final num levelStep;
  final num xpStartMillion;
  final num xpStepMillion;

  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'levelStart': levelStart,
    'levelStep': levelStep,
    'xpStartMillion': xpStartMillion,
    'xpStepMillion': xpStepMillion,
  };
}

const GuildSkillMilestoneSettings defaultGuildSkillMilestoneSettings = GuildSkillMilestoneSettings(
  enabled: true,
  levelStart: 50,
  levelStep: 10,
  xpStartMillion: 125,
  xpStepMillion: 25,
);

GuildSkillMilestoneSettings normalizeGuildSkillMilestoneSettings(Object? raw) {
  final base = defaultGuildSkillMilestoneSettings;
  if (raw is! Map) return base;
  num read(String key, num fallback) {
    final value = raw[key];
    if (value is num && value.isFinite) return value.floor().clamp(1, 1 << 30);
    return fallback;
  }

  return GuildSkillMilestoneSettings(
    enabled: raw['enabled'] != false,
    levelStart: read('levelStart', base.levelStart),
    levelStep: read('levelStep', base.levelStep),
    xpStartMillion: read('xpStartMillion', base.xpStartMillion),
    xpStepMillion: read('xpStepMillion', base.xpStepMillion),
  );
}

sealed class GuildSkillMilestone {
  const GuildSkillMilestone({required this.skillId, required this.skillName});

  final String skillId;
  final String skillName;
}

class GuildSkillLevelMilestone extends GuildSkillMilestone {
  const GuildSkillLevelMilestone({
    required super.skillId,
    required super.skillName,
    required this.level,
  });

  final num level;
}

class GuildSkillXpMilestone extends GuildSkillMilestone {
  const GuildSkillXpMilestone({
    required super.skillId,
    required super.skillName,
    required this.xpMillion,
  });

  final num xpMillion;
}

String formatGuildSkillMilestone(String characterName, GuildSkillMilestone milestone) {
  final name = characterName.trim().isEmpty ? 'Adventurer' : characterName.trim();
  if (milestone is GuildSkillLevelMilestone) {
    return '$name reached ${milestone.skillName} ${milestone.level.round()}';
  }
  if (milestone is GuildSkillXpMilestone) {
    return '$name reached ${milestone.xpMillion.round()}m ${milestone.skillName} XP';
  }
  return name;
}

List<num> levelMilestonesAtOrBelow(num level, GuildSkillMilestoneSettings settings) {
  if (level < settings.levelStart) return const <num>[];
  final out = <num>[];
  for (var n = settings.levelStart; n <= level; n += settings.levelStep) {
    out.add(n);
  }
  return out;
}

List<num> xpMillionMilestonesAtOrBelow(num xp, num level, GuildSkillMilestoneSettings settings) {
  if (level < 100) return const <num>[];
  final millions = (xp / 1000000).floor();
  if (millions < settings.xpStartMillion) return const <num>[];
  final out = <num>[];
  for (var n = settings.xpStartMillion; n <= millions; n += settings.xpStepMillion) {
    out.add(n);
  }
  return out;
}

List<GuildSkillMilestone> guildSkillMilestonesCrossed({
  required String skillId,
  required String skillName,
  required num beforeLevel,
  required num beforeXp,
  required num afterLevel,
  required num afterXp,
  required GuildSkillMilestoneSettings settings,
}) {
  final normalized = normalizeGuildSkillMilestoneSettings(settings.toJson());
  if (!normalized.enabled) return const <GuildSkillMilestone>[];

  final beforeLevels = levelMilestonesAtOrBelow(beforeLevel, normalized).toSet();
  final out = <GuildSkillMilestone>[];
  for (final level in levelMilestonesAtOrBelow(afterLevel, normalized)) {
    if (!beforeLevels.contains(level)) {
      out.add(GuildSkillLevelMilestone(skillId: skillId, skillName: skillName, level: level));
    }
  }

  final beforeXpMarks = xpMillionMilestonesAtOrBelow(beforeXp, beforeLevel, normalized).toSet();
  for (final xpMillion in xpMillionMilestonesAtOrBelow(afterXp, afterLevel, normalized)) {
    if (!beforeXpMarks.contains(xpMillion)) {
      out.add(
        GuildSkillXpMilestone(skillId: skillId, skillName: skillName, xpMillion: xpMillion),
      );
    }
  }
  return out;
}

class _SkillSnap {
  const _SkillSnap({required this.skillId, required this.level, required this.xp});

  final String skillId;
  final num level;
  final num xp;
}

List<GuildSkillMilestone> guildSkillMilestonesBetweenSaves({
  required List<({String skillId, num level, num xp})> beforeSkills,
  required List<({String skillId, num level, num xp})> afterSkills,
  required String Function(String skillId) skillName,
  required GuildSkillMilestoneSettings settings,
}) {
  final normalized = normalizeGuildSkillMilestoneSettings(settings.toJson());
  if (!normalized.enabled) return const <GuildSkillMilestone>[];
  final beforeById = <String, _SkillSnap>{
    for (final row in beforeSkills)
      row.skillId: _SkillSnap(skillId: row.skillId, level: row.level, xp: row.xp),
  };
  final out = <GuildSkillMilestone>[];
  for (final after in afterSkills) {
    final before = beforeById[after.skillId];
    out.addAll(
      guildSkillMilestonesCrossed(
        skillId: after.skillId,
        skillName: skillName(after.skillId),
        beforeLevel: before?.level ?? 1,
        beforeXp: before?.xp ?? 0,
        afterLevel: after.level,
        afterXp: after.xp,
        settings: normalized,
      ),
    );
  }
  return out;
}
