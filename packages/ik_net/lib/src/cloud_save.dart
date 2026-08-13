import 'package:ik_rules/ik_rules.dart';

import 'types.dart';

/// Why a save is being kept, or why the sync stopped.
enum CloudSyncSource {
  uploaded('uploaded'),
  downloaded('downloaded'),
  unchanged('unchanged');

  const CloudSyncSource(this.wire);

  final String wire;
}

class CloudSyncResult {
  const CloudSyncResult.ok(PlayerSave this.save, CloudSyncSource this.source)
    : reason = null,
      remote = null;

  const CloudSyncResult.failed(this.reason, {this.remote}) : save = null, source = null;

  final PlayerSave? save;
  final CloudSyncSource? source;
  final String? reason;

  /// The backend's copy, when it is the reason the sync stopped.
  final CloudSaveRecord? remote;

  bool get ok => reason == null;

  Map<String, Object?> toJson() => ok
      ? <String, Object?>{'ok': true, 'save': save!.toJson(), 'source': source!.wire}
      : <String, Object?>{
          'ok': false,
          'reason': reason,
          if (remote != null) 'remote': remote!.toJson(),
        };
}

/// Bounds a cloud snapshot has to be inside before it is accepted.
///
/// Gameplay is resolved on the client, so this cannot prove a save is honest;
/// it only rejects the values no legitimate save reaches.
ValidationResult softValidateSave(PlayerSave save) {
  if (!save.gold.isFinite || save.gold < 0 || save.gold > 1000000000) {
    return const ValidationResult.failed('Cloud save gold is out of bounds.');
  }
  for (final skill in save.skills) {
    if (skill.level < 1 || skill.level > 10000 || skill.xp < 0) {
      return const ValidationResult.failed('Cloud save skill values are out of bounds.');
    }
  }
  return const ValidationResult.ok();
}

class ValidationResult {
  const ValidationResult.ok() : reason = null;

  const ValidationResult.failed(this.reason);

  final String? reason;

  bool get ok => reason == null;

  Map<String, Object?> toJson() =>
      ok ? <String, Object?>{'ok': true} : <String, Object?>{'ok': false, 'reason': reason};
}

/// Which of the two saves a last-write-wins merge should keep.
///
/// The decision is separated from the transport so both backends share it, and
/// so a test can pin it without a network.
bool remoteSaveWins(PlayerSave local, PlayerSave remote) =>
    jsDateParse(remote.updatedAt) > jsDateParse(local.updatedAt) ||
    remote.saveVersion > local.saveVersion;

/// Whether a backend should refuse an upload because its copy is newer.
bool cloudWriteConflicts(CloudSaveRecord existing, PlayerSave incoming) =>
    jsDateParse(existing.updatedAt) > jsDateParse(incoming.updatedAt) &&
    existing.saveVersion >= incoming.saveVersion;
