import 'dart:math' as math;

import 'package:ik_content/ik_content.dart';

class SkillXpProgress {
  const SkillXpProgress({
    required this.level,
    required this.totalXp,
    required this.intoLevel,
    required this.toNextLevel,
    required this.nextLevel,
    required this.atCap,
  });

  final num level;
  final num totalXp;

  /// XP earned within the current level.
  final num intoLevel;

  /// XP required to reach the next level from the start of this level.
  final num toNextLevel;

  final num? nextLevel;

  /// True when total XP is at or past the highest curve row.
  final bool atCap;

  Map<String, Object?> toJson() => <String, Object?>{
    'level': level,
    'totalXp': totalXp,
    'intoLevel': intoLevel,
    'toNextLevel': toNextLevel,
    'nextLevel': nextLevel,
    'atCap': atCap,
  };
}

SkillXpProgress skillXpProgress(GameDatabase db, num totalXp) {
  final xp = math.max(0, totalXp.floor());
  final curve = db.xpCurve;
  if (curve.isEmpty) {
    return SkillXpProgress(
      level: 1,
      totalXp: xp,
      intoLevel: xp,
      toNextLevel: 0,
      nextLevel: null,
      atCap: true,
    );
  }

  num level = 1;
  num totalAtLevel = 0;
  // The curve's last row has no next level, so this is null past the cap. The
  // TypeScript original leans on `null <= 0` being true there.
  num? xpToNext = curve.first.xpToNextLevel ?? 0;
  for (final row in curve) {
    if (xp >= row.totalXpAtLevel) {
      level = row.level;
      totalAtLevel = row.totalXpAtLevel;
      xpToNext = row.xpToNextLevel;
    } else {
      break;
    }
  }

  final toNext = xpToNext ?? 0;
  final last = curve.last;
  final atCap = level >= last.level && (toNext <= 0 || xp >= totalAtLevel + toNext);
  final intoLevel = math.max(0, xp - totalAtLevel);

  return SkillXpProgress(
    level: level,
    totalXp: xp,
    intoLevel: atCap ? intoLevel : math.min(intoLevel, math.max(0, toNext)),
    toNextLevel: math.max(0, toNext),
    nextLevel: atCap ? null : level + 1,
    atCap: atCap,
  );
}
