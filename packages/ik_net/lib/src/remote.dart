/// The shape of a remote backend, as far as the client is concerned.
///
/// Everything here is pure: what to ask a table for, and how to read a row it
/// hands back. The wire itself belongs to whichever client is running, so both
/// the web app and the Flutter app can send the same requests without agreeing
/// on an HTTP library.
library;

import 'dart:math';

import 'package:ik_rules/ik_rules.dart';

import 'bazaar.dart';
import 'snapshots.dart';
import 'types.dart';

typedef RemoteRow = Map<String, Object?>;

/// The tables the migrations define, named once.
class RemoteTables {
  const RemoteTables._();

  static const String profiles = 'profiles';
  static const String saves = 'player_saves';
  static const String leaderboard = 'leaderboard_snapshots';
  static const String leaderboardEntries = 'leaderboard_entries';
  static const String chat = 'chat_messages';
  static const String bountyClaims = 'bounty_claims';
  static const String bazaarPosts = 'bazaar_posts';
  static const String guilds = 'guilds';
  static const String guildMembers = 'guild_members';
  static const String guildApplications = 'guild_applications';
  static const String guildGuests = 'guild_guests';
  static const String guildHalls = 'guild_halls';
  static const String guildProjects = 'guild_projects';
  static const String guildChallenges = 'guild_challenges';
  static const String activityPresence = 'activity_presence';
}

/// The edge function that writes chat, since a client may not insert directly.
const String remoteSendChatFunction = 'send-chat';

const String remoteNotConfigured = 'Supabase is not configured.';
const String remoteSignUpFailed = 'Sign-up failed.';
const String remoteSignInFailed = 'Sign-in failed.';
const String remoteInvalidBackendUrl =
    'The Supabase project URL is wrong. Use https://YOUR_PROJECT.supabase.co with no /rest/v1.';

/// Maps PostgREST/Auth path errors to a fix the operator can act on.
String friendlyRemoteError(String message) {
  if (message.toLowerCase().contains('invalid path specified')) {
    return remoteInvalidBackendUrl;
  }
  return message;
}

/// What a screen says when an action threw instead of refusing.
///
/// A refusal has a reason to show. An error has none, and silence reads as a
/// button that does nothing, so the error itself is what gets shown.
String unexpectedSocialError(Object error) => friendlyRemoteError('Something went wrong: $error');

const String remoteMagicLinkUnavailable =
    'Magic links require Supabase. Use email/password in local demo mode.';

/// How many messages a channel read asks for.
const int remoteChatLimit = 50;

/// How many private messages an inbox read asks for.
const int remoteDirectMessageLimit = 80;

/// As long as a username may be, which is what the account metadata carries.
const int remoteUsernameMaxLength = 24;

const String remoteSaveColumns = 'save_version, updated_at, payload';
const String remoteChatColumns =
    'id, channel_key, user_id, username, body, created_at, '
    'guild_tag, rank_icon, guest';
const String remoteLeaderboardColumns = 'user_id, board_key, value, value_secondary, profiles';
const String remoteBountyClaimColumns = 'hour_key, bounty_id, user_id, username, claimed_at';
const String remoteBazaarColumns = 'id, kind, user_id, username, body, created_at';
const String remotePresenceColumns =
    'user_id, username, appearance_json, guild_name, location_id, '
    'current_activity_id, skill_id, skill_level, outfit_cosmetic_id, '
    'mount_cosmetic_id, updated_at, expires_at';

/// Columns a public profile sheet needs from `profiles`.
const String remotePublicProfileColumns =
    'user_id, username, appearance_json, guild_id, privacy_public_skills, '
    'privacy_direct_messages, privacy_local_chat, updated_at';
const String remotePresenceConflict = 'user_id';

/// How many Bazaar notices a read asks for.
const int remoteBazaarLimit = 40;

/// The conflict target that makes a submit an update rather than a duplicate.
const String remoteLeaderboardConflict = 'user_id,board_key';

String remoteUsername(String raw) {
  final trimmed = raw.trim();
  return trimmed.length <= remoteUsernameMaxLength
      ? trimmed
      : trimmed.substring(0, remoteUsernameMaxLength);
}

/// A unique stand-in until character creation names the account.
const String pendingAccountUsernamePrefix = 'pending_';

String pendingAccountUsername(String userId) {
  final compact = userId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
  final body = compact.length <= 16 ? compact : compact.substring(compact.length - 16);
  return '$pendingAccountUsernamePrefix$body';
}

bool isPendingAccountUsername(String username) => username.startsWith(pendingAccountUsernamePrefix);

String remoteEmail(String raw) => raw.trim().toLowerCase();

/// The session a fresh sign-up produces, from what the auth call returned.
MultiplayerSession sessionFromSignUp(
  String userId,
  String email,
  String username,
  String? accessToken,
) {
  return MultiplayerSession(
    userId: userId,
    email: remoteEmail(email),
    username: remoteUsername(username),
    accessToken: accessToken ?? '',
  );
}

/// The session a sign-in produces.
///
/// An account made outside the game has no username in its metadata, so the
/// local part of the email stands in, and failing that a generic name.
MultiplayerSession sessionFromSignIn(
  String userId,
  String? accountEmail,
  String typedEmail,
  String? metadataUsername,
  String? accessToken,
) {
  final email = accountEmail ?? remoteEmail(typedEmail);
  final fallback = (accountEmail ?? '').split('@').first;
  return MultiplayerSession(
    userId: userId,
    email: email,
    username: metadataUsername ?? (fallback.isEmpty ? 'Adventurer' : fallback),
    accessToken: accessToken ?? '',
  );
}

/// A UUID v4 the account stores as the device that may play.
String newPlaySessionId([Random? random]) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int index) => bytes[index].toRadixString(16).padLeft(2, '0');
  return '${hex(0)}${hex(1)}${hex(2)}${hex(3)}-'
      '${hex(4)}${hex(5)}-'
      '${hex(6)}${hex(7)}-'
      '${hex(8)}${hex(9)}-'
      '${hex(10)}${hex(11)}${hex(12)}${hex(13)}${hex(14)}${hex(15)}';
}

/// The profile row a new account starts with.
RemoteRow profileRowForSignUp(MultiplayerSession session) => <String, Object?>{
  'user_id': session.userId,
  'username': session.username,
  'privacy_public_skills': true,
};

/// Claims this device as the only one allowed to play the account.
RemoteRow profilePlaySessionRow(MultiplayerSession session) => <String, Object?>{
  'user_id': session.userId,
  'username': session.username,
  'active_play_session_id': session.playSessionId,
};

RemoteRow saveRowFor(String userId, PlayerSave save, {String? playSessionId}) => <String, Object?>{
  'user_id': userId,
  'save_version': save.saveVersion,
  'updated_at': save.updatedAt,
  'payload': save.toJson(),
  'play_session_id': ?playSessionId,
};

/// The leaderboard rows one save is worth, all stamped with the same instant.
List<RemoteRow> leaderboardRowsFor(
  String userId,
  LeaderboardSnapshotValues snapshot,
  String nowIso,
) {
  return snapshot.boards
      .map(
        (board) => <String, Object?>{
          'user_id': userId,
          'board_key': board.boardKey,
          'value': board.value,
          'value_secondary': board.secondaryValue ?? 0,
          'updated_at': nowIso,
        },
      )
      .toList();
}

String _str(Object? value) => value == null ? '' : jsString(value);

String? _optStr(Object? value) {
  final text = _str(value);
  return text.isEmpty ? null : text;
}

num _num(Object? value) => jsNumber(value ?? 0);

/// A stored save as the row carried it.
///
/// The payload stays raw: a row may have been written by another build, and
/// whether it can be read as a save is the caller's question, not the row's.
class RemoteSaveRow {
  const RemoteSaveRow({
    required this.userId,
    required this.saveVersion,
    required this.updatedAt,
    required this.payload,
  });

  final String userId;
  final num saveVersion;
  final String updatedAt;
  final Map<String, Object?> payload;

  /// The same row with its payload read as a save, which throws if it cannot be.
  CloudSaveRecord toCloudSaveRecord() => CloudSaveRecord(
    userId: userId,
    saveVersion: saveVersion,
    updatedAt: updatedAt,
    payload: PlayerSave.fromJson(payload),
  );

  /// The same, but null rather than a throw when a row this build cannot read
  /// turns up — an older or newer client may have written it.
  CloudSaveRecord? toCloudSaveRecordOrNull() {
    try {
      return toCloudSaveRecord();
    } on Object {
      return null;
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'userId': userId,
    'saveVersion': saveVersion,
    'updatedAt': updatedAt,
    'payload': payload,
  };
}

/// A `player_saves` row as the cloud copy it stands for, or null if absent.
RemoteSaveRow? remoteSaveRowFrom(String userId, RemoteRow? row) {
  if (row == null) return null;
  return RemoteSaveRow(
    userId: userId,
    saveVersion: _num(row['save_version']),
    updatedAt: _str(row['updated_at']),
    payload: (row['payload'] as Map<String, Object?>?) ?? const <String, Object?>{},
  );
}

/// Whether the stored copy should win over what is about to be uploaded.
///
/// Both halves have to agree: a save that is newer by the clock but older by
/// version is a migration in progress, and the newer format wins.
bool isRemoteSaveNewer(RemoteSaveRow remote, PlayerSave local) {
  return jsDateParse(remote.updatedAt) > jsDateParse(local.updatedAt) &&
      remote.saveVersion >= local.saveVersion;
}

ChatMessage chatMessageFrom(RemoteRow row) => ChatMessage(
  id: _str(row['id']),
  channelKey: _str(row['channel_key']),
  userId: _str(row['user_id']),
  username: _str(row['username']),
  body: _str(row['body']),
  createdAt: _str(row['created_at']),
  guildTag: _optStr(row['guild_tag'] ?? row['guildTag']),
  rankIcon: _optStr(row['rank_icon'] ?? row['rankIcon']),
  guest: row['guest'] == true,
);

/// The message the send-chat function answered with.
///
/// A function may hand back the row it inserted or the message it made of it, so
/// both spellings of each field are accepted rather than trusting one.
ChatMessage? chatMessageFromFunction(RemoteRow? data) {
  if (data == null) return null;
  final id = _str(data['id']);
  if (id.isEmpty) return null;
  return chatMessageFrom(<String, Object?>{
    'id': id,
    'channel_key': data['channelKey'] ?? data['channel_key'],
    'user_id': data['userId'] ?? data['user_id'],
    'username': data['username'],
    'body': data['body'],
    'created_at': data['createdAt'] ?? data['created_at'],
    'guild_tag': data['guildTag'] ?? data['guild_tag'],
    'rank_icon': data['rankIcon'] ?? data['rank_icon'],
    'guest': data['guest'],
  });
}

/// What a send is refused with when the function answered with nothing usable.
const String remoteChatSendFailed = 'The chat message was not accepted.';

/// The same, for a Bazaar notice the board did not hand back.
const String remoteBazaarPostFailed = 'The notice was not accepted.';

/// Why an upload stops: the account has a newer save than the one being sent.
const String remoteSaveConflict = 'A newer cloud save exists.';
const String remoteSignedInElsewhere = 'Signed in on another device.';
const String remotePlaySessionColumn = 'active_play_session_id';

/// A leaderboard row joined with its profile.
///
/// The rank is the position the ordered read put it in, since the table stores
/// values rather than places. `profiles` is a jsonb column on
/// `leaderboard_entries`, not a PostgREST embed.
LeaderboardEntry leaderboardEntryFrom(RemoteRow row, MultiplayerBoardKey boardKey, int index) {
  final profile = _asRemoteMap(row['profiles']);
  final guild = _asRemoteMap(profile?['guilds']);
  final username = _str(profile?['username']);
  return LeaderboardEntry(
    userId: _str(row['user_id']),
    username: username.isEmpty ? 'Adventurer' : username,
    appearance: playerAppearanceFromRemote(profile?['appearance_json']),
    guildName: _optStr(guild?['name']),
    boardKey: boardKey,
    value: _num(row['value']),
    rank: index + 1,
    secondaryValue: boardCarriesExperience(boardKey) ? _num(row['value_secondary']) : null,
  );
}

Map<String, Object?>? _asRemoteMap(Object? value) {
  if (value == null) return null;
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return <String, Object?>{for (final entry in value.entries) entry.key.toString(): entry.value};
  }
  return null;
}

List<LeaderboardEntry> leaderboardEntriesFrom(List<RemoteRow> rows, MultiplayerBoardKey boardKey) {
  final entries = <LeaderboardEntry>[
    for (final (index, row) in rows.indexed) leaderboardEntryFrom(row, boardKey, index),
  ];
  // A zero on a qualify-or-not board means the player is not on it at all.
  if (!boardHidesZeroes(boardKey)) return entries;
  return entries
      .where((entry) => entry.value > 0)
      .indexed
      .map((entry) => entry.$2.withRank(entry.$1 + 1))
      .toList();
}

/// The row that claims an hourly bounty first.
///
/// `(hour_key, bounty_id)` is the table's primary key, which is what decides the
/// race: the insert that lands first is the one that stands, and a backend says
/// so rather than a client believing it.
RemoteRow bountyClaimRowFor(MultiplayerSession session, String hourKey, String bountyId) =>
    <String, Object?>{
      'hour_key': hourKey,
      'bounty_id': bountyId,
      'user_id': session.userId,
      'username': session.username,
    };

BountyClaimRecord bountyClaimFrom(RemoteRow row) => BountyClaimRecord(
  hourKey: _str(row['hour_key']),
  bountyId: _str(row['bounty_id']),
  userId: _str(row['user_id']),
  username: _str(row['username']),
  claimedAt: _str(row['claimed_at']),
);

RemoteRow bazaarPostRowFor(MultiplayerSession session, BazaarPostKind kind, String body) =>
    <String, Object?>{
      'kind': kind,
      'user_id': session.userId,
      'username': session.username,
      'body': body,
    };

BazaarPost bazaarPostFrom(RemoteRow row) => BazaarPost(
  id: _str(row['id']),
  kind: _str(row['kind']),
  userId: _str(row['user_id']),
  username: _str(row['username']),
  body: _str(row['body']),
  createdAt: _str(row['created_at']),
);

/// The Bazaar newest-last, the way a chat log reads.
///
/// A backend hands the newest first, because that is the only way to ask for the
/// most recent forty, so the order is turned round once they arrive.
List<BazaarPost> bazaarPostsFrom(List<RemoteRow> rows) =>
    rows.reversed.map(bazaarPostFrom).toList();

/// The snapshot one account publishes so Nearby can list them without reading
/// another player's save.
RemoteRow presenceRowFor({
  required MultiplayerSession session,
  required PresenceInput input,
  String? guildName,
  required String updatedAt,
  required String expiresAt,
}) => <String, Object?>{
  'user_id': session.userId,
  'username': session.username,
  'appearance_json': input.appearance.toJson(),
  'guild_name': guildName,
  'location_id': input.locationId,
  'current_activity_id': input.currentActivityId,
  'skill_id': input.skillId,
  'skill_level': input.skillLevel,
  'outfit_cosmetic_id': input.outfitCosmeticId,
  'mount_cosmetic_id': input.mountCosmeticId,
  'updated_at': updatedAt,
  'expires_at': expiresAt,
};

ActivityPresence activityPresenceFrom(RemoteRow row) => ActivityPresence(
  userId: _str(row['user_id']),
  username: _str(row['username']),
  appearance: playerAppearanceFromRemote(row['appearance_json']),
  guildName: _optStr(row['guild_name']),
  locationId: _str(row['location_id']),
  currentActivityId: _optStr(row['current_activity_id']),
  skillId: _optStr(row['skill_id']),
  skillLevel: row['skill_level'] == null ? null : _num(row['skill_level']),
  outfitCosmeticId: _optStr(row['outfit_cosmetic_id']),
  mountCosmeticId: _optStr(row['mount_cosmetic_id']),
  updatedAt: _str(row['updated_at']),
  expiresAt: _str(row['expires_at']),
);

/// A hosted `profiles` row as the account card social surfaces list.
MultiplayerProfile? multiplayerProfileFromRemote(RemoteRow? row) {
  if (row == null) return null;
  final userId = _str(row['user_id']);
  if (userId.isEmpty) return null;
  final username = _str(row['username']);
  return MultiplayerProfile(
    userId: userId,
    username: username.isEmpty ? 'Adventurer' : username,
    appearance: playerAppearanceFromRemote(row['appearance_json']),
    guildId: _optStr(row['guild_id']),
    guildName: _optStr(row['guild_name']),
    privacyPublicSkills: row['privacy_public_skills'] != false,
    privacyDirectMessages: normalizeChatPrivacy(_optStr(row['privacy_direct_messages'])),
    privacyLocalChat: normalizeChatPrivacy(_optStr(row['privacy_local_chat'])),
    updatedAt: _str(row['updated_at']),
  );
}

/// Live rows only: expired stamps stay in the table for last-online, but Nearby
/// must not list a player who has already gone.
List<ActivityPresence> livePresenceFrom(List<RemoteRow> rows, num nowMs) {
  return [for (final row in rows) activityPresenceFrom(row)]
      .where((row) => jsDateParse(row.expiresAt) > nowMs)
      .toList();
}
