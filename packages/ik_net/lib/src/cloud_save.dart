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

/// Wire int that treats a missing, null, or non-numeric field as 0.
int plazaResponseInt(Object? value) {
  if (value is num && value.isFinite) return value.floor();
  return 0;
}

class CloudSyncResult {
  const CloudSyncResult.ok(
    PlayerSave this.save,
    CloudSyncSource this.source, {
    this.goldGained,
    this.pointsGained = 0,
    this.plazaPoints = 0,
    this.pointsSpent = 0,
    this.firstCompleter,
    this.code,
    this.fightId,
    this.winsRemaining,
    this.pvpOutcome,
    this.rounds,
    this.youMaxHp,
    this.themMaxHp,
    this.opponent,
    this.claim,
  }) : reason = null,
       remote = null,
       noRoom = null;

  const CloudSyncResult.failed(
    this.reason, {
    this.remote,
    this.winsRemaining,
    this.code,
    this.noRoom,
  }) : save = null,
       source = null,
       goldGained = null,
       pointsGained = 0,
       plazaPoints = 0,
       pointsSpent = 0,
       firstCompleter = null,
       fightId = null,
       pvpOutcome = null,
       rounds = null,
       youMaxHp = null,
       themMaxHp = null,
       opponent = null,
       claim = null;

  final PlayerSave? save;
  final CloudSyncSource? source;
  final String? reason;

  /// The backend's copy, when it is the reason the sync stopped.
  final CloudSaveRecord? remote;

  final num? goldGained;

  /// Plaza points granted by this command. Missing on the wire is 0.
  final int pointsGained;

  /// Plaza points balance after this command. Missing on the wire is 0.
  final int plazaPoints;

  /// Plaza points spent by this command. Missing on the wire is 0.
  final int pointsSpent;

  final bool? firstCompleter;
  final String? code;
  final NoRoom? noRoom;
  final String? fightId;
  final num? winsRemaining;
  final String? pvpOutcome;
  final List<PvpRoundResult>? rounds;
  final num? youMaxHp;
  final num? themMaxHp;
  final ArenaOpponent? opponent;
  final BountyClaimRecord? claim;

  bool get ok => reason == null;

  Map<String, Object?> toJson() => ok
      ? <String, Object?>{
          'ok': true,
          'save': save!.toJson(),
          'source': source!.wire,
          if (goldGained != null) 'goldGained': goldGained,
          'pointsGained': pointsGained,
          'plazaPoints': plazaPoints,
          'pointsSpent': pointsSpent,
          if (firstCompleter != null) 'firstCompleter': firstCompleter,
          if (code != null) 'code': code,
          if (fightId != null) 'fightId': fightId,
        }
      : <String, Object?>{
          'ok': false,
          'reason': reason,
          if (remote != null) 'remote': remote!.toJson(),
          if (code != null) 'code': code,
          if (noRoom != null) 'noRoom': noRoom!.toJson(),
        };
}

/// The most gold a save may hold and still be accepted.
///
/// Named because the Bazaar has to respect it from the other side: a trade that
/// paid out over this would produce a save the backend then refuses to store,
/// so the exchange caps an offer's worth and leaves what will not fit in the
/// collection box.
const int cloudSaveGoldCap = 1000000000;

/// Bounds a cloud snapshot has to be inside before it is accepted.
///
/// Gameplay is resolved on the client, so this cannot prove a save is honest;
/// it only rejects the values no legitimate save reaches.
ValidationResult softValidateSave(PlayerSave save) {
  if (!save.gold.isFinite || save.gold < 0 || save.gold > cloudSaveGoldCap) {
    return const ValidationResult.failed('Cloud save gold is out of bounds.');
  }
  if (!save.plazaPoints.isFinite || save.plazaPoints < 0 || save.plazaPoints > cloudSaveGoldCap) {
    return const ValidationResult.failed('Cloud save plaza points are out of bounds.');
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
