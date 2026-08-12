import 'generated/save_models.dart';

final RegExp _whitespaceRun = RegExp(r'\s+');

/// Trim, collapse internal runs of whitespace, and clip to the stored length.
String? normalizeCharacterName(String raw) {
  final trimmed = raw.trim().replaceAll(_whitespaceRun, ' ');
  if (trimmed.isEmpty) return null;
  return trimmed.length <= characterNameMaxLength
      ? trimmed
      : trimmed.substring(0, characterNameMaxLength);
}

bool isValidCharacterName(String raw) => normalizeCharacterName(raw) != null;
