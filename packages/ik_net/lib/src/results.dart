import 'package:ik_rules/ik_rules.dart';

import 'bazaar.dart';
import 'types.dart';

/// Every backend call answers the same way: it worked, or here is the line to
/// show the player. The TypeScript original returns a discriminated union; these
/// classes are the Dart shape of it, and each serializes the same JSON so the
/// parity fixtures compare directly.
class ActionResult {
  const ActionResult.ok() : reason = null;

  const ActionResult.failed(this.reason);

  final String? reason;

  bool get ok => reason == null;

  Map<String, Object?> toJson() =>
      ok ? <String, Object?>{'ok': true} : <String, Object?>{'ok': false, 'reason': reason};
}

class SessionResult {
  const SessionResult.ok(MultiplayerSession this.session) : reason = null;

  const SessionResult.failed(this.reason) : session = null;

  final MultiplayerSession? session;
  final String? reason;

  bool get ok => reason == null;

  Map<String, Object?> toJson() => ok
      ? <String, Object?>{'ok': true, 'session': session!.toJson()}
      : <String, Object?>{'ok': false, 'reason': reason};
}

class CloudSaveWriteResult {
  const CloudSaveWriteResult.ok(CloudSaveRecord this.record) : reason = null, remote = null;

  const CloudSaveWriteResult.failed(this.reason, {this.remote}) : record = null;

  final CloudSaveRecord? record;
  final String? reason;

  /// The record already on the backend, when it refused the write because of it.
  final CloudSaveRecord? remote;

  bool get ok => reason == null;

  Map<String, Object?> toJson() => ok
      ? <String, Object?>{'ok': true, 'record': record!.toJson()}
      : <String, Object?>{
          'ok': false,
          'reason': reason,
          if (remote != null) 'remote': remote!.toJson(),
        };
}

class ChatSendResult {
  const ChatSendResult.ok(ChatMessage this.message) : reason = null;

  const ChatSendResult.failed(this.reason) : message = null;

  final ChatMessage? message;
  final String? reason;

  bool get ok => reason == null;

  Map<String, Object?> toJson() => ok
      ? <String, Object?>{'ok': true, 'message': message!.toJson()}
      : <String, Object?>{'ok': false, 'reason': reason};
}

class CreateGuildResult {
  const CreateGuildResult.ok(GuildRecord this.guild, num this.goldCost) : reason = null;

  const CreateGuildResult.failed(this.reason) : guild = null, goldCost = null;

  final GuildRecord? guild;

  /// What the caller should deduct once it has recorded the guild.
  final num? goldCost;
  final String? reason;

  bool get ok => reason == null;

  Map<String, Object?> toJson() => ok
      ? <String, Object?>{'ok': true, 'guild': guild!.toJson(), 'goldCost': goldCost}
      : <String, Object?>{'ok': false, 'reason': reason};
}

class ApplyToGuildResult {
  const ApplyToGuildResult.ok({required bool this.joined}) : reason = null;

  const ApplyToGuildResult.failed(this.reason) : joined = null;

  /// True when the guild was open and the player is already a member.
  final bool? joined;
  final String? reason;

  bool get ok => reason == null;

  Map<String, Object?> toJson() => ok
      ? <String, Object?>{'ok': true, 'joined': joined}
      : <String, Object?>{'ok': false, 'reason': reason};
}

class ContributeProjectResult {
  const ContributeProjectResult.ok(GuildProject this.project) : reason = null;

  const ContributeProjectResult.failed(this.reason) : project = null;

  final GuildProject? project;
  final String? reason;

  bool get ok => reason == null;

  Map<String, Object?> toJson() => ok
      ? <String, Object?>{'ok': true, 'project': project!.toJson()}
      : <String, Object?>{'ok': false, 'reason': reason};
}

class BountyClaimResult {
  const BountyClaimResult.ok(BountyClaimRecord this.claim, {required bool this.firstCompleter})
    : reason = null;

  const BountyClaimResult.failed(this.reason) : claim = null, firstCompleter = null;

  final BountyClaimRecord? claim;

  /// Only the first accepted turn-in this hour earns the bonus.
  final bool? firstCompleter;
  final String? reason;

  bool get ok => reason == null;

  Map<String, Object?> toJson() => ok
      ? <String, Object?>{'ok': true, 'claim': claim!.toJson(), 'firstCompleter': firstCompleter}
      : <String, Object?>{'ok': false, 'reason': reason};
}

class BazaarPostResult {
  const BazaarPostResult.ok(BazaarPost this.post) : reason = null;

  const BazaarPostResult.failed(this.reason) : post = null;

  final BazaarPost? post;
  final String? reason;

  bool get ok => reason == null;

  Map<String, Object?> toJson() => ok
      ? <String, Object?>{'ok': true, 'post': post!.toJson()}
      : <String, Object?>{'ok': false, 'reason': reason};
}
