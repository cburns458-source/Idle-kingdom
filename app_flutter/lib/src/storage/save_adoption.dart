import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

/// Seeds [storage] with a save another client left behind, and says whether it did.
///
/// Only when this device has none of its own: a player who has already started
/// here is playing that character, and an older copy must not take its place.
/// Anything unreadable is ignored rather than reported, because a player who
/// never used the old client should not be told about it at all.
bool adoptForeignSave(SaveStorage storage, String? text, num nowMs) {
  if (text == null || storage.getItem(saveStorageKey) != null) return false;
  final imported = importSaveText(text, nowMs);
  if (!imported.ok) return false;
  storage.setItem(saveStorageKey, exportSaveText(imported.save!));
  return true;
}
