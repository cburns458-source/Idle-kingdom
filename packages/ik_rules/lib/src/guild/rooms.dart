import 'package:ik_content/ik_content.dart';

import '../world/constants.dart';
import 'hall.dart';

const num guildHallCompanyXpPercent = 5;

/// Flat +5% XP when another guild member is anywhere in the hall.
num applyGuildHallCompanyXp(num xp, bool guildmatesPresent) {
  if (!guildmatesPresent || xp <= 0) return xp;
  return (xp * (100 + guildHallCompanyXpPercent) / 100).floor();
}

bool guildHallCompanyActive(String? locationId, bool guildmatesInHall) =>
    guildmatesInHall && locationId == guildHallLocationId;

bool isGuildHallEssenceActivity(String activityId) => activityId == guildHallEssenceActivityId;

bool isGuildHallCageActivity(String activityId) => activityId == guildHallCageActivityId;

bool activityIsGuildHallCage(ActivityRow? activity) {
  if (activity == null) return false;
  if (isGuildHallCageActivity(activity.activityId)) return true;
  return RegExp(r'(?:^|;)\s*guild_cage\b', caseSensitive: false).hasMatch(activity.notes ?? '');
}

bool guildHallRoomActivityVisible(String activityId, List<String> completedTiers) {
  if (isGuildHallEssenceActivity(activityId)) return guildHallArcanaUnlocked(completedTiers);
  if (isGuildHallCageActivity(activityId)) return guildHallCageUnlocked(completedTiers);
  return true;
}

bool guildHallGardenPatchOpen(List<String> completedTiers) =>
    guildHallGardenUnlocked(completedTiers);
