/// What a guild action means, with nowhere to store the answer.
///
/// These were once spelled out inside the local backend, which made it the only
/// place that knew a tag is two to four letters or that a recruit cannot pay the
/// debt. Both backends read them from here now, so a rule cannot hold on one
/// device and not on the server.
library;

import 'dart:math' as math;

import 'package:ik_rules/ik_rules.dart';

import 'results.dart';
import 'types.dart';

/// The longest an application message is kept at.
const int guildApplicationMessageMaxLength = 120;

const int guildNameMaxLength = 28;
const int guildDescriptionMaxLength = 160;

const String guildHallFinishedRefusal = 'The hall is finished.';
const String guildHallUnneededRefusal = 'The storehouse only takes what this step still needs.';

String _cut(String raw, int length) => raw.length > length ? raw.substring(0, length) : raw;

String guildNameFromInput(String raw) => _cut(raw.trim(), guildNameMaxLength);

/// A tag as it is stored: letters only, upper case, at most four.
String guildTagFromInput(String raw) =>
    _cut(raw.replaceAll(RegExp('[^a-zA-Z]'), '').toUpperCase(), 4);

String guildApplicationMessage(String raw) => _cut(raw.trim(), guildApplicationMessageMaxLength);

/// Why a guild cannot be founded from a name, a tag, and a purse.
///
/// The form asks this of every keystroke so it can say what is missing, and the
/// backend asks it again before writing anything.
String? createGuildRefusalFor({
  required String name,
  required String tag,
  required num goldAvailable,
}) {
  if (guildNameFromInput(name).length < 3) return 'Guild name needs at least 3 characters.';
  final cleanTag = guildTagFromInput(tag);
  if (cleanTag.length < 2 || cleanTag.length > 4) return 'Guild tag must be 2–4 letters.';
  if (goldAvailable < guildCreateGoldCost) {
    return 'Creating a guild costs ${jsNumberToString(guildCreateGoldCost)} gold.';
  }
  return null;
}

/// Why a guild cannot be founded, or null when it can.
String? createGuildRefusal(CreateGuildInput input, num goldAvailable) =>
    createGuildRefusalFor(name: input.name, tag: input.tag, goldAvailable: goldAvailable);

/// The guild a founder asked for, cleaned up and with no id yet.
///
/// A backend supplies the id: on one device that is a counter, and on a server
/// it is the row the insert wrote, which is also what settles a race for a name.
GuildRecord guildFromCreateInput(
  String leaderId,
  CreateGuildInput input,
  String createdAt, {
  String id = '',
}) => GuildRecord(
  id: id,
  name: guildNameFromInput(input.name),
  tag: guildTagFromInput(input.tag),
  description: _cut((input.description ?? '').trim(), guildDescriptionMaxLength),
  emblem: normalizeEmblem(input.emblem),
  leaderId: leaderId,
  joinPolicy: guildJoinOpen,
  rankLabels: <GuildRankKey, String>{...defaultGuildRankLabels},
  createdAt: createdAt,
);

bool isGuildLeader(GuildRecord guild, String userId) => guild.leaderId == userId;

bool isGuildOfficerOrLeader(GuildRecord guild, String userId, GuildRole? role) {
  if (isGuildLeader(guild, userId)) return true;
  return role == guildRoleOfficer;
}

String? decideApplicationRefusal(GuildRecord guild, String actorId, GuildRole? actorRole) {
  if (isGuildOfficerOrLeader(guild, actorId, actorRole)) return null;
  return 'Only the guild leader or an officer can decide applications.';
}

String? removeGuildMemberRefusal(GuildRecord guild, String actorId, String targetUserId) {
  if (!isGuildLeader(guild, actorId)) return 'Only the leader can remove members.';
  if (targetUserId == guild.leaderId) return 'Cannot remove the leader.';
  if (targetUserId == actorId) return 'Leave the guild instead.';
  return null;
}

String? removeGuildGuestRefusal(GuildRecord guild, String actorId, GuildRole? actorRole) {
  if (isGuildOfficerOrLeader(guild, actorId, actorRole)) return null;
  return 'Only the guild leader or an officer can remove guests.';
}

/// Why a rank change is refused, given the leader already asked for it.
String? memberRoleRefusal(GuildRecord guild, String targetUserId, GuildRole role) {
  if (role == guildRoleLeader) return 'Transfer leadership is not available yet.';
  if (targetUserId == guild.leaderId) return 'Cannot change the leader rank this way.';
  if (!promotableGuildRanks.contains(role)) return 'Invalid rank.';
  return null;
}

/// The project after [amount] goes in, never past its goal.
GuildProject contributedProject(GuildProject project, num amount) {
  final add = math.max(1, amount.floor());
  return project.copyWith(contributed: math.min(project.goalAmount, project.contributed + add));
}

/// The hall and the payer's save after gold goes toward the debt.
GuildHallActionResult payGuildHallDebt(
  GuildHallState hall,
  String userId,
  PlayerSave save,
  num amount,
) {
  final want = math.max(0, amount.floor());
  if (want <= 0) return const GuildHallActionResult.failed('Choose an amount.');
  if (save.gold < want) return const GuildHallActionResult.failed('Not enough gold.');
  if (hall.debtPaidOff || hall.debtRemaining <= 0) return GuildHallActionResult.ok(hall);

  final pay = math.min(want, hall.debtRemaining.floor());
  final remaining = hall.debtRemaining - pay;
  final paidOff = remaining <= 0;
  final paidBy = <String, num>{...hall.debtPaidBy};
  paidBy[userId] = (paidBy[userId] ?? 0) + pay;
  return GuildHallActionResult.ok(
    hall.copyWith(debtRemaining: paidOff ? 0 : remaining, debtPaidBy: paidBy, debtPaidOff: paidOff),
    save: save.copyWith(gold: save.gold - pay),
    paidOffJustNow: paidOff,
  );
}

/// The hall and the donor's save after a stack goes into the store house.
///
/// A donation is one way, and it pays for whatever tier it completes: the
/// materials a tier costs leave the store house as it finishes.
GuildHallActionResult donateToGuildHall(
  GuildHallState hall,
  PlayerSave save,
  int inventoryIndex,
  num quantity,
) {
  if (inventoryIndex < 0 || inventoryIndex >= save.inventory.length) {
    return const GuildHallActionResult.failed('That stack is not there.');
  }
  final stack = save.inventory[inventoryIndex];
  if (stackIsUnbankableGold(stack)) {
    return const GuildHallActionResult.failed('Gold stays on you.');
  }
  final want = math.max(0, quantity.floor());
  if (want <= 0) return const GuildHallActionResult.failed('Choose a quantity.');

  final remaining = guildHallDonationCap(hall.completedTiers, hall.storehouse, stack.itemId);
  if (remaining <= 0) {
    return GuildHallActionResult.failed(
      nextGuildHallTier(hall.completedTiers) == null
          ? guildHallFinishedRefusal
          : guildHallUnneededRefusal,
    );
  }

  final takenQty = math.min(want, math.min(stack.quantity.floor(), remaining.floor()));
  final added = addItemToInventoryExact(
    save.copyWith(inventory: hall.storehouse),
    stack.itemId,
    takenQty,
    stack.enchantmentId,
    stack.favorite ?? false,
  );
  if (!added.ok || added.save == null) {
    return GuildHallActionResult.failed(added.reason ?? 'The storehouse is full.');
  }

  final nextInventory = [...save.inventory];
  if (takenQty >= stack.quantity) {
    nextInventory.removeAt(inventoryIndex);
  } else {
    nextInventory[inventoryIndex] = stack.copyWith(quantity: stack.quantity - takenQty);
  }
  final settled = settleGuildHallTiers(added.save!.inventory, hall.completedTiers);
  return GuildHallActionResult.ok(
    hall.copyWith(storehouse: settled.storehouse, completedTiers: settled.completedTiers),
    save: save.copyWith(inventory: nextInventory),
    tiersFinishedNow: settled.finishedNow.map((tier) => tier.id).toList(),
  );
}

/// The project and challenge a new guild starts with.
///
/// Both backends seed the same two, so a guild founded on the server has the
/// same first goals as one founded offline.
const String guildStorehouseProjectName = 'Guild Storehouse';
const String guildStorehouseProjectDescription = 'Pool resources for cosmetic recognition.';
const num guildStorehouseProjectGoal = 1000;
const String guildStorehouseProjectReward = 'Guild banner cosmetic (recognition)';

const String guildMonsterChallengeName = 'Weekly Monster Hunt';
const num guildMonsterChallengeGoal = 100;
