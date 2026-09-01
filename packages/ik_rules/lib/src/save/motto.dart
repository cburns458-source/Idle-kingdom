import 'generated/save_models.dart';

final RegExp _whitespaceRun = RegExp(r'\s+');

/// Trim, collapse whitespace, and cap length. Empty becomes null.
String? normalizeMotto(String raw) {
  final trimmed = raw.trim().replaceAll(_whitespaceRun, ' ');
  if (trimmed.isEmpty) return null;
  return trimmed.length <= mottoMaxLength ? trimmed : trimmed.substring(0, mottoMaxLength);
}

bool isValidMotto(String raw) {
  // Empty is allowed (clears the motto); only reject when over the cap after trim.
  final trimmed = raw.trim().replaceAll(_whitespaceRun, ' ');
  return trimmed.length <= mottoMaxLength;
}
