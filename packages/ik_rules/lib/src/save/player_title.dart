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

  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    'placement': placement.wire,
  };
}

/// Held from the first step until the first defeat.
const PlayerTitle undyingTitle = PlayerTitle(
  text: 'The Undying',
  placement: TitlePlacement.suffix,
);

/// The title a save has earned, or null when it holds none.
PlayerTitle? titleForSave(PlayerSave save) => save.hasEverDied ? null : undyingTitle;

String nameWithTitle(String name, PlayerTitle? title) {
  if (title == null) return name;
  return title.placement == TitlePlacement.prefix
      ? '${title.text} $name'
      : '$name ${title.text}';
}

/// How a character is introduced: their name, with whatever title they hold.
///
/// Falls back to [fallback] for a save that has not been named yet, which keeps
/// a title off an anonymous character.
String displayNameForSave(PlayerSave save, String fallback) {
  final name = save.characterName;
  if (name == null || name.isEmpty) return fallback;
  return nameWithTitle(name, titleForSave(save));
}
