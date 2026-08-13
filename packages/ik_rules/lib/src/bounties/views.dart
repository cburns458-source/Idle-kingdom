import 'dart:math' as math;

import '../js_compat.dart';
import '../save/generated/save_models.dart';
import 'progress.dart';
import 'types.dart';

/// Where a signed-out player is sent to be able to claim anything.
const String bountySignInNotice = 'Sign in from Menu → Account to claim bounty rewards.';

/// The line above the board.
///
/// The countdown is formatted by the client, because each one already has a
/// duration formatter the rest of its screens use.
String bountyRotationLine(String remainingLabel) =>
    'Rotates in $remainingLabel. First turn-in earns a bonus; '
    'others can still claim the base reward.';

/// One bounty as the board shows it.
class BountyRowView {
  const BountyRowView({
    required this.bountyId,
    required this.title,
    required this.description,
    required this.progressLine,
    required this.firstCompleterLine,
    required this.actionLabel,
    required this.canTurnIn,
  });

  final String bountyId;
  final String title;
  final String description;

  /// `3 / 10 · 120 gold (+60 first)`.
  final String progressLine;

  /// `First completer: Rowan`, or null while nobody has turned one in.
  final String? firstCompleterLine;

  /// `Claimed`, `Turn in`, or `In progress`.
  final String actionLabel;

  /// True only when pressing the button would actually claim something.
  final bool canTurnIn;

  Map<String, Object?> toJson() => <String, Object?>{
    'bountyId': bountyId,
    'title': title,
    'description': description,
    'progressLine': progressLine,
    'firstCompleterLine': firstCompleterLine,
    'actionLabel': actionLabel,
    'canTurnIn': canTurnIn,
  };
}

String _rewardLine(BountyDefinition bounty, num progress) {
  final done = math.min(progress, bounty.amount);
  final bonus = bounty.firstPlaceBonusGold > 0
      ? ' (+${jsNumberToString(bounty.firstPlaceBonusGold)} first)'
      : '';
  return '${jsNumberToString(done)} / ${jsNumberToString(bounty.amount)} · '
      '${jsNumberToString(bounty.rewardGold)} gold$bonus';
}

BountyRowView bountyRowView(
  PlayerSave save,
  BountyDefinition bounty,
  BountyClaimRecord? claim,
  bool signedIn,
  num nowMs,
) {
  final ready = isBountyReadyToClaim(save, bounty, nowMs);
  final claimed = save.bountyClaimedIds.contains(bounty.id);
  return BountyRowView(
    bountyId: bounty.id,
    title: bounty.title,
    description: bounty.description,
    progressLine: _rewardLine(bounty, bountyProgressFor(save, bounty, nowMs)),
    firstCompleterLine: claim == null ? null : 'First completer: ${claim.username}',
    actionLabel: claimed
        ? 'Claimed'
        : ready
        ? 'Turn in'
        : 'In progress',
    canTurnIn: signedIn && ready && !claimed,
  );
}

/// Every row of the current board.
///
/// [claims] is the hour's recorded first turn-ins; a bounty nobody has finished
/// is simply absent from it.
List<BountyRowView> bountyRows(
  PlayerSave save,
  HourlyBountyBoard board,
  List<BountyClaimRecord> claims,
  bool signedIn,
  num nowMs,
) {
  return board.bounties.map((bounty) {
    BountyClaimRecord? claim;
    for (final row in claims) {
      if (row.bountyId == bounty.id) {
        claim = row;
        break;
      }
    }
    return bountyRowView(save, bounty, claim, signedIn, nowMs);
  }).toList();
}

/// What the turn-in says once a backend has accepted it.
String bountyClaimedNotice(num goldGained, bool firstCompleter) {
  final gold = jsNumberToString(goldGained);
  return firstCompleter ? 'First completer! +$gold gold.' : 'Bounty claimed. +$gold gold.';
}
