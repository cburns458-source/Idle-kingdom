import 'dart:convert';

import 'package:ik_rules/ik_rules.dart';

/// Moving a save between devices by hand.
///
/// The text is the save JSON itself, byte for byte what storage holds, which is
/// what makes this the way off the retired React client: the value under
/// `idle-kingdoms.demo.save` in a browser's local storage is already a valid
/// import, and so is anything this exports.

const String saveTransferHeading = 'Move this save';

const String saveTransferBlurb =
    'Copy this character to another device, or paste one in. Importing replaces '
    'the character on this device.';

const String saveImportHint = 'Paste a save';

const String saveCopiedNotice = 'Save copied.';

const String saveImportEmpty = 'Paste a save first.';

/// Said for anything unreadable, because the reason is never actionable: a
/// player who pasted the wrong thing needs to paste the right thing.
const String saveImportUnreadable = 'That is not an Idle Kingdoms save.';

/// What to say once an imported save is the one being played.
String saveImportedNotice(PlayerSave save) {
  final name = save.characterName?.trim();
  return 'Now playing ${name == null || name.isEmpty ? 'this save' : name}.';
}

/// A save read out of pasted text, or the refusal to show for it.
class SaveImportResult {
  const SaveImportResult.ok(PlayerSave this.save) : reason = null;

  const SaveImportResult.failed(String this.reason) : save = null;

  final PlayerSave? save;
  final String? reason;

  bool get ok => save != null;
}

/// The save as text, for a player to copy somewhere safe or onto another device.
String exportSaveText(PlayerSave save) => jsonEncode(save.toJson());

/// Reads [text] as a save, migrating an old one on the way in.
///
/// Nothing is written here: the caller decides whether to adopt what came back,
/// which is what lets a client warn before replacing the save in hand.
SaveImportResult importSaveText(String text, num nowMs) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return const SaveImportResult.failed(saveImportEmpty);
  try {
    return SaveImportResult.ok(parseSave(jsonDecode(trimmed), nowMs));
  } on Object {
    return const SaveImportResult.failed(saveImportUnreadable);
  }
}
