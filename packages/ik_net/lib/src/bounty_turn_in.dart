import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'service.dart';

/// What a turn-in produced: the paid save and the claim a backend recorded, or
/// the reason it was refused.
class BountyTurnInResult {
  const BountyTurnInResult.ok({
    required PlayerSave this.save,
    required BountyClaimRecord this.claim,
    required bool this.firstCompleter,
    required num this.goldGained,
  }) : reason = null;

  const BountyTurnInResult.failed(this.reason)
    : save = null,
      claim = null,
      firstCompleter = null,
      goldGained = null;

  final PlayerSave? save;
  final BountyClaimRecord? claim;

  /// True only for the one turn-in the backend accepted first this hour.
  final bool? firstCompleter;
  final num? goldGained;
  final String? reason;

  bool get ok => reason == null;
}

/// The Plaza notice-board turn-in.
///
/// Hosted play sends `bounty_turn_in` so the claim and the gold land in one
/// server transaction. Offline demo still pays here after the local backend
/// records the first completer.
Future<BountyTurnInResult> turnInBounty(
  MultiplayerService service,
  GameDatabase db,
  PlayerSave save,
  BountyDefinition bounty,
  num nowMs,
) async {
  final session = service.session;
  if (!service.isSignedIn || session == null) {
    return const BountyTurnInResult.failed('Sign in to claim bounties.');
  }

  if (service.hostedCommands) {
    final hosted = await service.gameCommand('bounty_turn_in', <String, Object?>{
      'bountyId': bounty.id,
    });
    if (!hosted.ok || hosted.save == null) {
      return BountyTurnInResult.failed(hosted.reason ?? 'Could not claim that bounty.');
    }
    final claim =
        hosted.claim ??
        BountyClaimRecord(
          hourKey: hourlyBountyBoard(nowMs).hourKey,
          bountyId: bounty.id,
          userId: session.userId,
          username: session.username,
          claimedAt: isoFromMs(nowMs),
        );
    return BountyTurnInResult.ok(
      save: hosted.save!,
      claim: claim,
      firstCompleter: hosted.firstCompleter ?? false,
      goldGained: hosted.goldGained ?? 0,
    );
  }

  final prepared = prepareBountyTurnIn(save, bounty, nowMs);
  if (!prepared.ok) return BountyTurnInResult.failed(prepared.reason!);

  final hourKey = hourlyBountyBoard(nowMs).hourKey;
  final claimed = await service.claimBounty(hourKey, bounty.id);
  if (!claimed.ok) return BountyTurnInResult.failed(claimed.reason!);

  final claim = claimed.claim!;
  final firstCompleter = (claimed.firstCompleter ?? false) && claim.userId == session.userId;
  final rewarded = applyBountyReward(prepared.save!, bounty, firstCompleter);

  return BountyTurnInResult.ok(
    save: rewarded.save,
    claim: claim,
    firstCompleter: firstCompleter,
    goldGained: rewarded.goldGained,
  );
}
