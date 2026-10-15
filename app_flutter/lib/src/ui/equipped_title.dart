import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

/// The title HUD and the viewer's own profile may write next to a name.
///
/// Hidden when the slot is empty, the title is locked, or the player left that
/// faith. Placement comes from Cosmetics `Title Placement`.
PlayerTitle? equippedDisplayTitle(GameDatabase db, PlayerSave save) {
  final equipped = save.cosmetics.equipped;
  final equippedId = equipped.containsKey(titleCosmeticSlotId)
      ? equipped[titleCosmeticSlotId]
      : null;
  if (equipped.containsKey(titleCosmeticSlotId) && (equippedId == null || equippedId.isEmpty)) {
    return null;
  }
  if (isFaithTitleLocked(db, save, equippedId)) return null;
  return titleForSave(save, db);
}

/// Character name with the equipped title, or [fallback] when unnamed.
String displayNameWithEquippedTitle(GameDatabase db, PlayerSave save, String fallback) {
  final name = save.characterName;
  if (name == null || name.isEmpty) return fallback;
  return nameWithTitle(name, equippedDisplayTitle(db, save));
}

/// Title published on another player's profile. Nothing when the id is missing
/// or does not resolve to a titled cosmetic.
PlayerTitle? publishedDisplayTitle(GameDatabase db, String? titleCosmeticId) {
  return titleForCosmeticId(db, titleCosmeticId);
}

/// [name] with a published title, or [name] alone when the id is null or unknown.
String displayNameWithPublishedTitle(GameDatabase db, String name, String? titleCosmeticId) {
  return nameWithTitle(name, publishedDisplayTitle(db, titleCosmeticId));
}
