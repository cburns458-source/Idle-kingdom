import 'generated/rows.dart';

const String guildHallEssenceActivityId = 'ACT-GH01';
const String guildHallCageActivityId = 'ACT-GH02';
const String guildHallLocationIdForRooms = 'LOC-0033';
const String guildHallCageNote = 'guild_cage; NoLoot';

const String _essenceTemplateKey = 'delve_for_essence';
const String _cageTemplateKey = 'train_citadel_grounds';

/// Clones Harness essence and the citadel training fight onto the guild hall.
GameDatabase withGuildHallRoomActivities(GameDatabase db) {
  ActivityRow? essenceTemplate;
  ActivityRow? cageTemplate;
  final existing = <String>{};
  for (final row in db.activities) {
    existing.add(row.activityId);
    final key = (row.raw['Internal Key'] as String?) ?? '';
    if (key == _essenceTemplateKey) essenceTemplate = row;
    if (key == _cageTemplateKey) cageTemplate = row;
  }
  final extras = <Map<String, Object?>>[];
  if (essenceTemplate != null && !existing.contains(guildHallEssenceActivityId)) {
    extras.add({
      ...essenceTemplate.raw,
      'Activity ID': guildHallEssenceActivityId,
      'Internal Key': 'guild_hall_harness_essence',
      'Location ID': guildHallLocationIdForRooms,
      'Contextual Name': 'Harness essence',
      'Description': "The hall Arcana station. Same work as the Wizard's Tower.",
    });
  }
  if (cageTemplate != null && !existing.contains(guildHallCageActivityId)) {
    extras.add({
      ...cageTemplate.raw,
      'Activity ID': guildHallCageActivityId,
      'Internal Key': 'guild_hall_monster_cage',
      'Location ID': guildHallLocationIdForRooms,
      'Contextual Name': 'Challenge the cage',
      'Description': 'A training enemy. XP only — nothing drops.',
      'Notes': guildHallCageNote,
    });
  }
  if (extras.isEmpty) return db;
  final next = Map<String, Object?>.of(db.raw);
  next['Activities'] = [...db.activities.map((row) => row.raw), ...extras];
  return GameDatabase(next);
}
