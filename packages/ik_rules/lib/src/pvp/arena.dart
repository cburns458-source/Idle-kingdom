import 'package:ik_content/ik_content.dart';

/// Citadel Plaza — the public arena.
const String arenaPlazaLocationId = 'LOC-0028';

const List<String> arenaLocationIds = <String>[arenaPlazaLocationId];

bool locationHasArena(LocationRow? location) {
  if (location == null) return false;
  return arenaLocationIds.contains(location.locationId);
}
