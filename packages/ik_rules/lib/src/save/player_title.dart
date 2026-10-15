import 'package:collection/collection.dart';
import 'package:ik_content/ik_content.dart';

import 'generated/save_models.dart';

/// Which side of the name a title is written on.
enum TitlePlacement {
  prefix('prefix'),
  suffix('suffix');

  const TitlePlacement(this.wire);

  final String wire;
}

class PlayerTitle {
  const PlayerTitle({required this.text, required this.placement});

  final String text;
  final TitlePlacement placement;

  Map<String, Object?> toJson() => <String, Object?>{'text': text, 'placement': placement.wire};
}

/// Held from the first step until the first defeat.
const PlayerTitle undyingTitle = PlayerTitle(text: 'The Undying', placement: TitlePlacement.suffix);

/// The title a save has earned, or null when it holds none.
PlayerTitle? titleForSave(PlayerSave save, [GameDatabase? db]) {
  final equipped = save.cosmetics.equipped;
  final equippedId = equipped.containsKey(titleCosmeticSlotId)
      ? equipped[titleCosmeticSlotId]
      : null;
  if (equippedId != null && equippedId != starterTitleCosmeticId) {
    // Faith (and later) titles stay visible after the first death; Undying does not.
    if (db == null) return null;
    final cosmetic = db.cosmetics.firstWhereOrNull((row) => row.raw['Cosmetic ID'] == equippedId);
    final itemId = cosmetic?.raw['Item ID'];
    if (itemId is! String) return null;
    final text = db.items
        .firstWhereOrNull((row) => row.raw['Item ID'] == itemId)
        ?.raw['Display Name'];
    if (text is String && text.isNotEmpty) {
      return PlayerTitle(text: text, placement: TitlePlacement.suffix);
    }
    return null;
  }
  if (save.hasEverDied) return null;
  if (equipped.containsKey(titleCosmeticSlotId)) {
    return equipped[titleCosmeticSlotId] == starterTitleCosmeticId ? undyingTitle : null;
  }
  // Older saves never wrote the title slot; they still wear The Undying.
  return undyingTitle;
}

String nameWithTitle(String name, PlayerTitle? title) {
  if (title == null) return name;
  return title.placement == TitlePlacement.prefix ? '${title.text} $name' : '$name ${title.text}';
}

/// How a character is introduced: their name, with whatever title they hold.
///
/// Falls back to [fallback] for a save that has not been named yet, which keeps
/// a title off an anonymous character.
String displayNameForSave(PlayerSave save, String fallback, [GameDatabase? db]) {
  final name = save.characterName;
  if (name == null || name.isEmpty) return fallback;
  return nameWithTitle(name, titleForSave(save, db));
}
