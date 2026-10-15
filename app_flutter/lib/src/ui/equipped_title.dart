import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

/// The title HUD and profile may write next to a name.
///
/// Hidden when the slot is empty, the title is locked, or the player left that
/// faith. Faith titles sit before the name; The Undying stays a suffix.
PlayerTitle? equippedDisplayTitle(GameDatabase db, PlayerSave save) {
  final equipped = save.cosmetics.equipped;
  final equippedId = equipped.containsKey(titleCosmeticSlotId)
      ? equipped[titleCosmeticSlotId]
      : null;
  if (equipped.containsKey(titleCosmeticSlotId) && (equippedId == null || equippedId.isEmpty)) {
    return null;
  }
  if (isFaithTitleLocked(db, save, equippedId)) return null;
  final title = titleForSave(save, db);
  if (title == null) return null;
  if (religionIdForTitleCosmetic(db, equippedId) != null) {
    return PlayerTitle(text: title.text, placement: TitlePlacement.prefix);
  }
  return title;
}

/// Character name with the equipped title, or [fallback] when unnamed.
String displayNameWithEquippedTitle(GameDatabase db, PlayerSave save, String fallback) {
  final name = save.characterName;
  if (name == null || name.isEmpty) return fallback;
  return nameWithTitle(name, equippedDisplayTitle(db, save));
}
