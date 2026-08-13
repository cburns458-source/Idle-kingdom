import 'package:ik_content/ik_content.dart';

/// Citadel Plaza — the public arena.
const String arenaPlazaLocationId = 'LOC-0028';

/// Combat Training Grounds — the same arena, next to PvE training.
const String arenaCombatLocationId = 'LOC-0032';

const List<String> arenaLocationIds = <String>[arenaPlazaLocationId, arenaCombatLocationId];

bool locationHasArena(LocationRow? location) {
  if (location == null) return false;
  return arenaLocationIds.contains(location.locationId);
}
