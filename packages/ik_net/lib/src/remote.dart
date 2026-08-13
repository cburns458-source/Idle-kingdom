/// The shape of a remote backend, as far as the client is concerned.
///
/// Everything here is pure: what to ask a table for, and how to read a row it
/// hands back. The wire itself belongs to whichever client is running, so both
/// the web app and the Flutter app can send the same requests without agreeing
/// on an HTTP library.
library;

import 'package:ik_rules/ik_rules.dart';

import 'snapshots.dart';
import 'types.dart';

typedef RemoteRow = Map<String, Object?>;

/// The tables the migrations define, named once.
class RemoteTables {
  const RemoteTables._();

  static const String profiles = 'profiles';
  static const String saves = 'player_saves';
  static const String leaderboard = 'leaderboard_snapshots';
  static const String chat = 'chat_messages';
}

/// The edge function that writes chat, since a client may not insert directly.
const String remoteSendChatFunction = 'send-chat';

const String remoteNotConfigured = 'Supabase is not configured.';
const String remoteSignUpFailed = 'Sign-up failed.';
const String remoteSignInFailed = 'Sign-in failed.';
const String remoteMagicLinkUnavailable =
    'Magic links require Supabase. Use email/password in local demo mode.';

/// How many messages a channel read asks for.
const int remoteChatLimit = 50;

/// As long as a username may be, which is what the account metadata carries.
const int remoteUsernameMaxLength = 24;

const String remoteSaveColumns = 'save_version, updated_at, payload';
const String remoteChatColumns = 'id, channel_key, user_id, username, body, created_at';
const String remoteLeaderboardColumns =
    'user_id, board_key, value, profiles(username, appearance_json, guild_id, guilds(name))';

/// The conflict target that makes a submit an update rather than a duplicate.
const String remoteLeaderboardConflict = 'user_id,board_key';

String remoteUsername(String raw) {
  final trimmed = raw.trim();
  return trimmed.length <= remoteUsernameMaxLength
      ? trimmed
      : trimmed.substring(0, remoteUsernameMaxLength);
}

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

/// The profile row a new account starts with.
RemoteRow profileRowForSignUp(MultiplayerSession session) => <String, Object?>{
  'user_id': session.userId,
  'username': session.username,
  'privacy_public_skills': true,
};

RemoteRow saveRowFor(String userId, PlayerSave save) => <String, Object?>{
  'user_id': userId,
  'save_version': save.saveVersion,
  'updated_at': save.updatedAt,
  'payload': save.toJson(),
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
          'updated_at': nowIso,
        },
      )
      .toList();
}

String _str(Object? value) => value == null ? '' : jsString(value);

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
);

/// The message the send-chat function answered with.
///
/// A function may hand back the row it inserted or the message it made of it, so
/// both spellings of each field are accepted rather than trusting one.
ChatMessage? chatMessageFromFunction(RemoteRow? data) {
  if (data == null) return null;
  final id = _str(data['id']);
  if (id.isEmpty) return null;
  return ChatMessage(
    id: id,
    channelKey: _str(data['channelKey'] ?? data['channel_key']),
    userId: _str(data['userId'] ?? data['user_id']),
    username: _str(data['username']),
    body: _str(data['body']),
    createdAt: _str(data['createdAt'] ?? data['created_at']),
  );
}

/// What a send is refused with when the function answered with nothing usable.
const String remoteChatSendFailed = 'The chat message was not accepted.';

/// Why an upload stops: the account has a newer save than the one being sent.
const String remoteSaveConflict = 'A newer cloud save exists.';

/// A leaderboard row joined with its profile.
///
/// The rank is the position the ordered read put it in, since the table stores
/// values rather than places.
LeaderboardEntry leaderboardEntryFrom(RemoteRow row, MultiplayerBoardKey boardKey, int index) {
  final profile = row['profiles'] as Map<String, Object?>?;
  final appearance = profile?['appearance_json'] as Map<String, Object?>?;
  final guild = profile?['guilds'] as Map<String, Object?>?;
  return LeaderboardEntry(
    userId: _str(row['user_id']),
    username: (profile?['username'] as String?) ?? 'Adventurer',
    appearance: appearance == null
        ? defaultPlayerAppearance
        : PlayerAppearance.fromJson(appearance),
    guildName: guild?['name'] as String?,
    boardKey: boardKey,
    value: _num(row['value']),
    rank: index + 1,
  );
}

List<LeaderboardEntry> leaderboardEntriesFrom(
  List<RemoteRow> rows,
  MultiplayerBoardKey boardKey,
) {
  return <LeaderboardEntry>[
    for (final (index, row) in rows.indexed) leaderboardEntryFrom(row, boardKey, index),
  ];
}
