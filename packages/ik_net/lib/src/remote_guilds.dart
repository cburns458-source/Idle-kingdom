/// Guild rows, in both directions.
///
/// Nothing here talks to a backend. These are the shapes the guild tables hold
/// and the models the guild tab wants, so the service is left deciding what to
/// ask for and the transport is left carrying it.
library;

import 'dart:convert';

import 'package:ik_rules/ik_rules.dart';

import 'remote.dart';
import 'types.dart';

const String remoteGuildColumns =
    'id, name, tag, description, emblem, leader_id, join_policy, '
    'rank_labels, rank_icon_theme, guest_auto_accept, created_at';

const String remoteGuildMemberColumns =
    'guild_id, user_id, username, role, joined_at, appearance_json, total_level';

const String remoteGuildApplicationColumns =
    'id, guild_id, user_id, username, message, created_at, guest';

const String remoteGuildGuestColumns = 'guild_id, user_id, username, appearance_json, joined_at';

const String remoteGuildHallColumns =
    'guild_id, debt_remaining, debt_paid_off, debt_paid_by, storehouse, completed_tiers';

const String remoteGuildProjectColumns =
    'id, guild_id, name, description, goal_amount, contributed, reward_label';

const String remoteGuildChallengeColumns =
    'id, guild_id, name, board_key, goal_value, current_value';

/// What a name or tag collision reads as, whichever of the two it was.
///
/// The database settles the race, and it answers with a constraint name no
/// screen should ever show, so both come back as the same plain sentence.
const String remoteGuildNameTaken = 'That guild name or tag is taken.';

const String remoteGuildCreateFailed = 'The guild was not created.';
const String remoteGuildMissing = 'Guild not found.';

/// True when a refusal is the database saying a unique column already has that
/// value, rather than something the player could fix by trying again.
bool isDuplicateRefusal(String reason) {
  final text = reason.toLowerCase();
  return text.contains('duplicate key') ||
      text.contains('already exists') ||
      text.contains('unique constraint');
}

String _str(Object? value) => value == null ? '' : jsString(value);

num _num(Object? value) => jsNumber(value ?? 0);

Map<String, Object?> _map(Object? value) =>
    value is Map<String, Object?> ? value : const <String, Object?>{};

List<Object?> _list(Object? value) => value is List<Object?> ? value : const <Object?>[];

/// The guild row a founder inserts.
///
/// No id and no created_at: the table makes both, and the insert hands back
/// what it made.
RemoteRow guildRowForCreate(String leaderId, GuildRecord guild) => <String, Object?>{
  'name': guild.name,
  'tag': guild.tag,
  'description': guild.description,
  'emblem': guild.emblem.toJson(),
  'leader_id': leaderId,
  'join_policy': guild.joinPolicy,
  'rank_labels': guild.rankLabels,
  'rank_icon_theme': guild.rankIconTheme,
  'guest_auto_accept': guild.guestAutoAccept,
};

/// The settings half of a guild, for an update that leaves the rest alone.
RemoteRow guildSettingsRowFor(GuildRecord guild) => <String, Object?>{
  'id': guild.id,
  'description': guild.description,
  'emblem': guild.emblem.toJson(),
  'join_policy': guild.joinPolicy,
  'rank_labels': guild.rankLabels,
  'rank_icon_theme': guild.rankIconTheme,
  'guest_auto_accept': guild.guestAutoAccept,
};

/// An emblem as any shape a row has ever held it in.
///
/// The column started as a bare emoji, became JSON in a text column in 002, and
/// is jsonb from 008 on. A guild made before a migration still reads correctly.
GuildEmblem guildEmblemFromRow(Object? value) {
  if (value is String && value.trimLeft().startsWith('{')) {
    try {
      return normalizeEmblem(jsonDecode(value));
    } on FormatException {
      return normalizeEmblem(null);
    }
  }
  return normalizeEmblem(value);
}

GuildRecord guildRecordFrom(RemoteRow row) => GuildRecord(
  id: _str(row['id']),
  name: _str(row['name']),
  tag: _str(row['tag']).toUpperCase(),
  description: _str(row['description']),
  emblem: guildEmblemFromRow(row['emblem']),
  leaderId: _str(row['leader_id']),
  joinPolicy: _str(row['join_policy']) == guildJoinClosed ? guildJoinClosed : guildJoinOpen,
  rankLabels: normalizeRankLabels(row['rank_labels']),
  createdAt: _str(row['created_at']),
  guestAutoAccept: row['guest_auto_accept'] == true,
  rankIconTheme: normalizeRankIconTheme(_str(row['rank_icon_theme'])),
);

/// A roster row, carrying the name, look, and level it is listed under.
RemoteRow guildMemberRowFor(GuildMember member) => <String, Object?>{
  'guild_id': member.guildId,
  'user_id': member.userId,
  'username': member.username,
  'role': member.role,
  'appearance_json': member.appearance.toJson(),
  'total_level': member.totalLevel,
};

GuildMember guildMemberFrom(RemoteRow row) => GuildMember(
  guildId: _str(row['guild_id']),
  userId: _str(row['user_id']),
  username: _str(row['username']),
  role: normalizeRole(_str(row['role'])),
  joinedAt: _str(row['joined_at']),
  appearance: PlayerAppearance.fromJson(_map(row['appearance_json'])),
  totalLevel: _num(row['total_level']) < 1 ? 1 : _num(row['total_level']),
);

/// Members oldest first, so a roster reads in the order people arrived.
List<GuildMember> guildMembersFrom(List<RemoteRow> rows) => rows.map(guildMemberFrom).toList();

RemoteRow guildApplicationRowFor({
  required String guildId,
  required String userId,
  required String username,
  required String message,
  required bool guest,
}) => <String, Object?>{
  'guild_id': guildId,
  'user_id': userId,
  'username': username,
  'message': message,
  'guest': guest,
};

GuildApplication guildApplicationFrom(RemoteRow row) => GuildApplication(
  id: _str(row['id']),
  guildId: _str(row['guild_id']),
  userId: _str(row['user_id']),
  username: _str(row['username']),
  message: _str(row['message']),
  createdAt: _str(row['created_at']),
  guest: row['guest'] == true,
);

RemoteRow guildGuestRowFor(GuildGuest guest) => <String, Object?>{
  'guild_id': guest.guildId,
  'user_id': guest.userId,
  'username': guest.username,
  'appearance_json': guest.appearance.toJson(),
};

GuildGuest guildGuestFrom(RemoteRow row) => GuildGuest(
  guildId: _str(row['guild_id']),
  userId: _str(row['user_id']),
  username: _str(row['username']),
  joinedAt: _str(row['joined_at']),
  appearance: PlayerAppearance.fromJson(_map(row['appearance_json'])),
);

RemoteRow guildProjectRowFor(GuildProject project) => <String, Object?>{
  'guild_id': project.guildId,
  'name': project.name,
  'description': project.description,
  'goal_amount': project.goalAmount,
  'contributed': project.contributed,
  'reward_label': project.rewardLabel,
};

GuildProject guildProjectFrom(RemoteRow row) => GuildProject(
  id: _str(row['id']),
  guildId: _str(row['guild_id']),
  name: _str(row['name']),
  description: _str(row['description']),
  goalAmount: _num(row['goal_amount']),
  contributed: _num(row['contributed']),
  rewardLabel: _str(row['reward_label']),
);

RemoteRow guildChallengeRowFor(GuildChallenge challenge) => <String, Object?>{
  'guild_id': challenge.guildId,
  'name': challenge.name,
  'board_key': challenge.boardKey,
  'goal_value': challenge.goalValue,
  'current_value': challenge.currentValue,
};

GuildChallenge guildChallengeFrom(RemoteRow row) => GuildChallenge(
  id: _str(row['id']),
  guildId: _str(row['guild_id']),
  name: _str(row['name']),
  boardKey: _str(row['board_key']),
  goalValue: _num(row['goal_value']),
  currentValue: _num(row['current_value']),
);

RemoteRow guildHallRowFor(GuildHallState hall) => <String, Object?>{
  'guild_id': hall.guildId,
  'debt_remaining': hall.debtRemaining,
  'debt_paid_off': hall.debtPaidOff,
  'debt_paid_by': hall.debtPaidBy,
  'storehouse': hall.storehouse.map((stack) => stack.toJson()).toList(),
  'completed_tiers': hall.completedTiers,
};

GuildHallState guildHallFrom(RemoteRow row) => GuildHallState(
  guildId: _str(row['guild_id']),
  debtRemaining: _num(row['debt_remaining']),
  debtPaidBy: <String, num>{
    for (final entry in _map(row['debt_paid_by']).entries) entry.key: _num(entry.value),
  },
  storehouse: _list(row['storehouse'])
      .map((value) => InventoryStack.fromJson(_map(value)))
      .toList(),
  completedTiers: _list(row['completed_tiers']).map(_str).toList(),
  debtPaidOff: row['debt_paid_off'] == true,
);
