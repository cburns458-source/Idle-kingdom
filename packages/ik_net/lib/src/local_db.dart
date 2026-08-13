import 'package:ik_rules/ik_rules.dart';

import 'bazaar.dart';
import 'types.dart';

/// A muted or blocked pairing: the viewer and whoever they silenced.
class UserPair {
  const UserPair({required this.userId, required this.otherUserId});

  factory UserPair.fromJson(Map<String, Object?> json, String otherKey) =>
      UserPair(userId: json['userId']! as String, otherUserId: json[otherKey]! as String);

  final String userId;
  final String otherUserId;

  Map<String, Object?> toJson(String otherKey) => <String, Object?>{
    'userId': userId,
    otherKey: otherUserId,
  };
}

class LocalAccount {
  const LocalAccount({
    required this.userId,
    required this.email,
    required this.username,
    required this.password,
    this.chatBanned = false,
  });

  factory LocalAccount.fromJson(Map<String, Object?> json) => LocalAccount(
    userId: json['userId']! as String,
    email: json['email']! as String,
    username: json['username']! as String,
    password: json['password'] as String? ?? '',
    chatBanned: json['chatBanned'] as bool? ?? false,
  );

  final String userId;
  final String email;
  final String username;
  final String password;
  final bool chatBanned;

  LocalAccount copyWith({bool? chatBanned}) => LocalAccount(
    userId: userId,
    email: email,
    username: username,
    password: password,
    chatBanned: chatBanned ?? this.chatBanned,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'userId': userId,
    'email': email,
    'username': username,
    'password': password,
    if (chatBanned) 'chatBanned': true,
  };
}

class LeaderboardRow {
  const LeaderboardRow({
    required this.userId,
    required this.boardKey,
    required this.value,
    required this.updatedAt,
  });

  factory LeaderboardRow.fromJson(Map<String, Object?> json) => LeaderboardRow(
    userId: json['userId']! as String,
    boardKey: json['boardKey']! as String,
    value: json['value']! as num,
    updatedAt: json['updatedAt']! as String,
  );

  final String userId;
  final MultiplayerBoardKey boardKey;
  final num value;
  final String updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'userId': userId,
    'boardKey': boardKey,
    'value': value,
    'updatedAt': updatedAt,
  };
}

class PlayerReport {
  const PlayerReport({
    required this.id,
    required this.reporterId,
    required this.targetUserId,
    required this.reason,
    required this.createdAt,
  });

  factory PlayerReport.fromJson(Map<String, Object?> json) => PlayerReport(
    id: json['id']! as String,
    reporterId: json['reporterId']! as String,
    targetUserId: json['targetUserId']! as String,
    reason: json['reason']! as String,
    createdAt: json['createdAt']! as String,
  );

  final String id;
  final String reporterId;
  final String targetUserId;
  final String reason;
  final String createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'reporterId': reporterId,
    'targetUserId': targetUserId,
    'reason': reason,
    'createdAt': createdAt,
  };
}

class FriendRequest {
  const FriendRequest({required this.fromUserId, required this.toUserId, required this.createdAt});

  factory FriendRequest.fromJson(Map<String, Object?> json) => FriendRequest(
    fromUserId: json['fromUserId']! as String,
    toUserId: json['toUserId']! as String,
    createdAt: json['createdAt']! as String,
  );

  final String fromUserId;
  final String toUserId;
  final String createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'fromUserId': fromUserId,
    'toUserId': toUserId,
    'createdAt': createdAt,
  };
}

class Friendship {
  const Friendship({required this.userA, required this.userB});

  factory Friendship.fromJson(Map<String, Object?> json) =>
      Friendship(userA: json['userA']! as String, userB: json['userB']! as String);

  final String userA;
  final String userB;

  Map<String, Object?> toJson() => <String, Object?>{'userA': userA, 'userB': userB};
}

/// Everything the local backend keeps, held as one JSON document under a single
/// storage key, the way the browser build keeps it in `localStorage`.
class LocalDb {
  LocalDb({
    required this.users,
    required this.profiles,
    required this.saves,
    required this.leaderboards,
    required this.messages,
    required this.lastChatAt,
    required this.blocks,
    required this.reports,
    required this.guilds,
    required this.members,
    required this.applications,
    required this.projects,
    required this.challenges,
    required this.presence,
    required this.mutes,
    required this.friendRequests,
    required this.friends,
    required this.bountyClaims,
    required this.bazaarPosts,
    required this.guests,
  });

  LocalDb.empty()
    : users = <LocalAccount>[],
      profiles = <MultiplayerProfile>[],
      saves = <CloudSaveRecord>[],
      leaderboards = <LeaderboardRow>[],
      messages = <ChatMessage>[],
      lastChatAt = <String, String>{},
      blocks = <UserPair>[],
      reports = <PlayerReport>[],
      guilds = <GuildRecord>[],
      members = <GuildMember>[],
      applications = <GuildApplication>[],
      projects = <GuildProject>[],
      challenges = <GuildChallenge>[],
      presence = <ActivityPresence>[],
      mutes = <UserPair>[],
      friendRequests = <FriendRequest>[],
      friends = <Friendship>[],
      bountyClaims = <BountyClaimRecord>[],
      bazaarPosts = <BazaarPost>[],
      guests = <GuildGuest>[];

  /// Reads whatever a previous version wrote, filling in anything it lacks.
  factory LocalDb.fromJson(Object? raw) {
    final db = LocalDb.empty();
    if (raw is! Map<String, Object?>) return db;

    List<Map<String, Object?>> rows(String key) {
      final value = raw[key];
      if (value is! List) return const <Map<String, Object?>>[];
      return value.whereType<Map<String, Object?>>().toList();
    }

    db.users.addAll(rows('users').map(LocalAccount.fromJson));
    db.profiles.addAll(rows('profiles').map(MultiplayerProfile.fromJson));
    db.saves.addAll(rows('saves').map(CloudSaveRecord.fromJson));
    db.leaderboards.addAll(rows('leaderboards').map(LeaderboardRow.fromJson));
    db.messages.addAll(rows('messages').map(ChatMessage.fromJson));
    final stamps = raw['lastChatAt'];
    if (stamps is Map<String, Object?>) {
      for (final entry in stamps.entries) {
        final value = entry.value;
        if (value is String) db.lastChatAt[entry.key] = value;
      }
    }
    db.blocks.addAll(rows('blocks').map((row) => UserPair.fromJson(row, 'blockedUserId')));
    db.reports.addAll(rows('reports').map(PlayerReport.fromJson));
    db.guilds.addAll(rows('guilds').map(GuildRecord.fromJson).map(normalizeGuild));
    db.members.addAll(rows('members').map(GuildMember.fromJson));
    db.applications.addAll(rows('applications').map(GuildApplication.fromJson));
    db.projects.addAll(rows('projects').map(GuildProject.fromJson));
    db.challenges.addAll(rows('challenges').map(GuildChallenge.fromJson));
    db.presence.addAll(rows('presence').map(ActivityPresence.fromJson));
    db.mutes.addAll(rows('mutes').map((row) => UserPair.fromJson(row, 'mutedUserId')));
    db.friendRequests.addAll(rows('friendRequests').map(FriendRequest.fromJson));
    db.friends.addAll(rows('friends').map(Friendship.fromJson));
    db.bountyClaims.addAll(rows('bountyClaims').map(BountyClaimRecord.fromJson));
    db.bazaarPosts.addAll(rows('bazaarPosts').map(BazaarPost.fromJson));
    db.guests.addAll(rows('guests').map(GuildGuest.fromJson));
    return db;
  }

  List<LocalAccount> users;
  List<MultiplayerProfile> profiles;
  List<CloudSaveRecord> saves;
  List<LeaderboardRow> leaderboards;
  List<ChatMessage> messages;
  Map<String, String> lastChatAt;
  List<UserPair> blocks;
  List<PlayerReport> reports;
  List<GuildRecord> guilds;
  List<GuildMember> members;
  List<GuildApplication> applications;
  List<GuildProject> projects;
  List<GuildChallenge> challenges;
  List<ActivityPresence> presence;
  List<UserPair> mutes;
  List<FriendRequest> friendRequests;
  List<Friendship> friends;
  List<BountyClaimRecord> bountyClaims;
  List<BazaarPost> bazaarPosts;
  List<GuildGuest> guests;

  Map<String, Object?> toJson() => <String, Object?>{
    'users': users.map((row) => row.toJson()).toList(),
    'profiles': profiles.map((row) => row.toJson()).toList(),
    'saves': saves.map((row) => row.toJson()).toList(),
    'leaderboards': leaderboards.map((row) => row.toJson()).toList(),
    'messages': messages.map((row) => row.toJson()).toList(),
    'lastChatAt': <String, Object?>{...lastChatAt},
    'blocks': blocks.map((row) => row.toJson('blockedUserId')).toList(),
    'reports': reports.map((row) => row.toJson()).toList(),
    'guilds': guilds.map((row) => row.toJson()).toList(),
    'members': members.map((row) => row.toJson()).toList(),
    'applications': applications.map((row) => row.toJson()).toList(),
    'projects': projects.map((row) => row.toJson()).toList(),
    'challenges': challenges.map((row) => row.toJson()).toList(),
    'presence': presence.map((row) => row.toJson()).toList(),
    'mutes': mutes.map((row) => row.toJson('mutedUserId')).toList(),
    'friendRequests': friendRequests.map((row) => row.toJson()).toList(),
    'friends': friends.map((row) => row.toJson()).toList(),
    'bountyClaims': bountyClaims.map((row) => row.toJson()).toList(),
    'bazaarPosts': bazaarPosts.map((row) => row.toJson()).toList(),
    if (guests.isNotEmpty) 'guests': guests.map((row) => row.toJson()).toList(),
  };
}

/// Repairs a guild row an older build wrote: no tag, an emoji emblem, a missing
/// join policy, or rank labels the player never set.
GuildRecord normalizeGuild(GuildRecord raw) => GuildRecord(
  id: raw.id,
  name: raw.name,
  tag: normalizeTag(raw.name, raw.tag),
  description: raw.description,
  emblem: normalizeEmblem(raw.emblem),
  leaderId: raw.leaderId,
  joinPolicy: raw.joinPolicy == guildJoinClosed ? guildJoinClosed : guildJoinOpen,
  rankLabels: normalizeRankLabels(<String, Object?>{...raw.rankLabels}),
  createdAt: raw.createdAt,
  guestAutoAccept: raw.guestAutoAccept,
  rankIconTheme: normalizeRankIconTheme(raw.rankIconTheme),
);
