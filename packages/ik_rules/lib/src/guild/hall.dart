import 'package:ik_content/ik_content.dart';

import '../world/constants.dart';

bool locationHasGuildHall(LocationRow? location) {
  if (location == null) return false;
  return location.locationId == guildHallLocationId;
}

/// Recruits cannot pay the hall debt. Member and every rank above can.
bool canPayGuildDebt(String role) {
  return role == 'leader' || role == 'officer' || role == 'veteran' || role == 'member';
}

const num guildHallDebtGold = 1000000;

/// Item quantity the guild must contribute before the boxing ring opens.
const num boxingRingUnlockItems = 50;

const String boxingRingUnlockId = 'boxing_ring';

bool boxingRingUnlocked(num itemsContributed, List<String> unlocks) {
  return unlocks.contains(boxingRingUnlockId) || itemsContributed >= boxingRingUnlockItems;
}
