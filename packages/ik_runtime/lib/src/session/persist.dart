import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

/// Everything that happens to a save on its way to storage.
///
/// Every write goes through here so two things can never be forgotten: the
/// unattended anchor moves to now (otherwise the next load would replay time the
/// player was present for), and achievements and statistics catch up with
/// whatever the save just did.
PlayerSave prepareSaveForWrite(GameDatabase db, PlayerSave save, num nowMs) {
  return syncProgressionMeta(db, stampUnattendedProgressAt(save, nowMs), nowMs);
}
