import 'package:ik_rules/ik_rules.dart';

/// Which ladder a leaderboard row belongs to.
///
/// The per-skill boards are `skill:<Skill ID>`, so this stays a string rather
/// than an enum, exactly as the TypeScript template literal type does.
typedef MultiplayerBoardKey = String;

/// Ranks by total level and carries total XP alongside it, so one board answers
/// both questions and ties break on experience.
const String boardTotalLevel = 'total_level';
const String boardGuildTotalLevel = 'guild_total_level';

/// Kept so rows written before the boards were combined still read back. No
/// longer offered in the picker.
const String boardTotalExperience = 'total_experience';

/// Total level among players who have never raised Combat past level 1.
const String boardPacifistTotalLevel = 'total_level_combat_1';

const String boardGoldEarned = 'gold_earned';
const String boardMonstersKilled = 'monsters_killed';
const String boardCrittersCollected = 'critters_collected';
const String boardBountiesCompleted = 'bounties_completed';
const String boardPvpKd = 'pvp_kd';

const String skillBoardPrefix = 'skill:';

MultiplayerBoardKey skillBoardKey(String skillId) => '$skillBoardPrefix$skillId';

/// Boards that carry a second number: total level ranks, total XP rides along.
///
/// The guild board is not one of them: its value is a whole roster totalled by
/// the backend, and it was never two boards to begin with.
bool boardCarriesExperience(MultiplayerBoardKey boardKey) =>
    boardKey == boardTotalLevel || boardKey == boardPacifistTotalLevel;

/// A board only some players stand on, where a zero means "does not qualify"
/// rather than a real score of nothing.
bool boardHidesZeroes(MultiplayerBoardKey boardKey) => boardKey == boardPacifistTotalLevel;

/// The account row every social surface reads names and portraits from.
class MultiplayerProfile {
  const MultiplayerProfile({
    required this.userId,
    required this.username,
    required this.appearance,
    required this.guildId,
    required this.guildName,
    required this.privacyPublicSkills,
    required this.updatedAt,
  });

  factory MultiplayerProfile.fromJson(Map<String, Object?> json) => MultiplayerProfile(
    userId: json['userId']! as String,
    username: json['username']! as String,
    appearance: PlayerAppearance.fromJson(json['appearance']! as Map<String, Object?>),
    guildId: json['guildId'] as String?,
    guildName: json['guildName'] as String?,
    privacyPublicSkills: json['privacyPublicSkills'] as bool? ?? true,
    updatedAt: json['updatedAt']! as String,
  );

  final String userId;
  final String username;
  final PlayerAppearance appearance;
  final String? guildId;
  final String? guildName;
  final bool privacyPublicSkills;
  final String updatedAt;

  MultiplayerProfile copyWith({
    String? username,
    PlayerAppearance? appearance,
    String? guildId,
    String? guildName,
    bool? privacyPublicSkills,
    String? updatedAt,
    bool clearGuild = false,
  }) => MultiplayerProfile(
    userId: userId,
    username: username ?? this.username,
    appearance: appearance ?? this.appearance,
    guildId: clearGuild ? null : (guildId ?? this.guildId),
    guildName: clearGuild ? null : (guildName ?? this.guildName),
    privacyPublicSkills: privacyPublicSkills ?? this.privacyPublicSkills,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'userId': userId,
    'username': username,
    'appearance': appearance.toJson(),
    'guildId': guildId,
    'guildName': guildName,
    'privacyPublicSkills': privacyPublicSkills,
    'updatedAt': updatedAt,
  };
}

/// A name and portrait for a friends or ignore row.
class SocialContact {
  const SocialContact({
    required this.userId,
    required this.username,
    required this.appearance,
    this.guildName,
  });

  final String userId;
  final String username;
  final PlayerAppearance appearance;
  final String? guildName;

  Map<String, Object?> toJson() => <String, Object?>{
    'userId': userId,
    'username': username,
    'appearance': appearance.toJson(),
    'guildName': guildName,
  };
}

/// A save as the backend holds it, with the version and stamp it was accepted at.
class CloudSaveRecord {
  const CloudSaveRecord({
    required this.userId,
    required this.saveVersion,
    required this.updatedAt,
    required this.payload,
  });

  factory CloudSaveRecord.fromJson(Map<String, Object?> json) => CloudSaveRecord(
    userId: json['userId']! as String,
    saveVersion: json['saveVersion']! as num,
    updatedAt: json['updatedAt']! as String,
    payload: PlayerSave.fromJson(json['payload']! as Map<String, Object?>),
  );

  final String userId;
  final num saveVersion;
  final String updatedAt;
  final PlayerSave payload;

  Map<String, Object?> toJson() => <String, Object?>{
    'userId': userId,
    'saveVersion': saveVersion,
    'updatedAt': updatedAt,
    'payload': payload.toJson(),
  };
}

/// Whether a leaderboard row stands for one player or a whole guild.
enum LeaderboardEntryKind {
  player('player'),
  guild('guild');

  const LeaderboardEntryKind(this.wire);

  final String wire;
}

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.userId,
    required this.username,
    required this.appearance,
    required this.guildName,
    required this.boardKey,
    required this.value,
    required this.rank,
    this.secondaryValue,
    this.entryKind,
    this.emblem,
  });

  final String userId;
  final String username;
  final PlayerAppearance appearance;
  final String? guildName;
  final MultiplayerBoardKey boardKey;
  final num value;
  final num rank;

  /// The second number a combined board shows: total XP under a total level.
  /// Null on boards that rank by one thing.
  final num? secondaryValue;

  /// Set for guild boards, where a row is a guild rather than a player.
  final LeaderboardEntryKind? entryKind;
  final GuildEmblem? emblem;

  LeaderboardEntry withRank(num next) => LeaderboardEntry(
    userId: userId,
    username: username,
    appearance: appearance,
    guildName: guildName,
    boardKey: boardKey,
    value: value,
    rank: next,
    secondaryValue: secondaryValue,
    entryKind: entryKind,
    emblem: emblem,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'userId': userId,
    'username': username,
    'appearance': appearance.toJson(),
    'guildName': guildName,
    'boardKey': boardKey,
    'value': value,
    'rank': rank,
    if (secondaryValue != null) 'secondaryValue': secondaryValue,
    if (entryKind != null) 'entryKind': entryKind!.wire,
    if (emblem != null || entryKind != null) 'emblem': emblem?.toJson(),
  };
}

/// One chat room. `global` is everyone, `local` is a location, `guild` is a
/// roster, and `dm` is the sorted pair of two user ids.
sealed class ChatChannel {
  const ChatChannel();

  const factory ChatChannel.global() = GlobalChatChannel;

  const factory ChatChannel.local(String locationId) = LocalChatChannel;

  const factory ChatChannel.guild(String guildId) = GuildChatChannel;

  const factory ChatChannel.dm(String pairKey) = DirectChatChannel;

  Map<String, Object?> toJson() => switch (this) {
    GlobalChatChannel() => <String, Object?>{'kind': 'global'},
    LocalChatChannel(locationId: final locationId) => <String, Object?>{
      'kind': 'local',
      'locationId': locationId,
    },
    GuildChatChannel(guildId: final guildId) => <String, Object?>{
      'kind': 'guild',
      'guildId': guildId,
    },
    DirectChatChannel(pairKey: final pairKey) => <String, Object?>{
      'kind': 'dm',
      'pairKey': pairKey,
    },
  };
}

class GlobalChatChannel extends ChatChannel {
  const GlobalChatChannel();
}

class LocalChatChannel extends ChatChannel {
  const LocalChatChannel(this.locationId);

  final String locationId;
}

class GuildChatChannel extends ChatChannel {
  const GuildChatChannel(this.guildId);

  final String guildId;
}

class DirectChatChannel extends ChatChannel {
  const DirectChatChannel(this.pairKey);

  final String pairKey;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.channelKey,
    required this.userId,
    required this.username,
    required this.body,
    required this.createdAt,
    this.guildTag,
    this.rankLabel,
    this.rankIcon,
    this.guest = false,
  });

  factory ChatMessage.fromJson(Map<String, Object?> json) => ChatMessage(
    id: json['id']! as String,
    channelKey: json['channelKey']! as String,
    userId: json['userId']! as String,
    username: json['username']! as String,
    body: json['body']! as String,
    createdAt: json['createdAt']! as String,
    guildTag: json['guildTag'] as String?,
    rankLabel: json['rankLabel'] as String?,
    rankIcon: json['rankIcon'] as String?,
    guest: json['guest'] as bool? ?? false,
  );

  final String id;
  final String channelKey;
  final String userId;
  final String username;
  final String body;
  final String createdAt;

  /// Member guild tag, shown as `[TAG]` in global and local rooms.
  final String? guildTag;

  /// Guild-chat rank name, from the guild's own labels at send time.
  final String? rankLabel;

  /// Guild-chat rank mark, from the guild's icon theme at send time.
  final String? rankIcon;

  /// True when the speaker is a guest of the guild room, not a member.
  final bool guest;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'channelKey': channelKey,
    'userId': userId,
    'username': username,
    'body': body,
    'createdAt': createdAt,
    if (guildTag != null) 'guildTag': guildTag,
    if (rankLabel != null) 'rankLabel': rankLabel,
    if (rankIcon != null) 'rankIcon': rankIcon,
    if (guest) 'guest': true,
  };
}

/// Leader plus four promotable ranks.
typedef GuildRole = String;

const String guildRoleLeader = 'leader';
const String guildRoleOfficer = 'officer';
const String guildRoleVeteran = 'veteran';
const String guildRoleMember = 'member';
const String guildRoleRecruit = 'recruit';

typedef GuildJoinPolicy = String;

const String guildJoinOpen = 'open';
const String guildJoinClosed = 'closed';

/// All guild roles, including leader — used for customizable display names.
typedef GuildRankKey = GuildRole;

const Map<GuildRankKey, String> defaultGuildRankLabels = <GuildRankKey, String>{
  guildRoleLeader: 'Leader',
  guildRoleOfficer: 'Officer',
  guildRoleVeteran: 'Veteran',
  guildRoleMember: 'Member',
  guildRoleRecruit: 'Recruit',
};

const List<GuildRole> promotableGuildRanks = <GuildRole>[
  guildRoleOfficer,
  guildRoleVeteran,
  guildRoleMember,
  guildRoleRecruit,
];

/// Army stripes, with a star for the leader.
const String guildRankIconThemeStripes = 'stripes';

/// Pips, with a crown for the leader.
const String guildRankIconThemeCrowns = 'crowns';

const List<String> guildRankIconThemes = <String>[
  guildRankIconThemeStripes,
  guildRankIconThemeCrowns,
];

String normalizeRankIconTheme(String? raw) =>
    raw == guildRankIconThemeCrowns ? guildRankIconThemeCrowns : guildRankIconThemeStripes;

/// Guest speakers use this in guild chat, in place of a rank mark.
const String guildGuestChatIcon = '☺';

/// Leader first, then officer, veteran, member, recruit.
int guildRankSortIndex(String role) {
  return switch (normalizeRole(role)) {
    guildRoleLeader => 0,
    guildRoleOfficer => 1,
    guildRoleVeteran => 2,
    guildRoleMember => 3,
    _ => 4,
  };
}

/// The mark that sits in front of a name in guild chat.
String guildRankIcon(String theme, String role) {
  if (normalizeRankIconTheme(theme) == guildRankIconThemeCrowns) {
    return switch (role) {
      guildRoleLeader => '♔',
      guildRoleOfficer => '◆',
      guildRoleVeteran => '●',
      guildRoleMember => '•',
      _ => '·',
    };
  }
  return switch (role) {
    guildRoleLeader => '★',
    guildRoleOfficer => '▍▍▍▍',
    guildRoleVeteran => '▍▍▍',
    guildRoleMember => '▍▍',
    _ => '▍',
  };
}

const num guildCreateGoldCost = 25;
const int guildMaxMembers = 25;

const List<String> guildEmblemColors = <String>[
  '#5c4027',
  '#2f6b3a',
  '#3d5a80',
  '#7a2f2f',
  '#6b4f1d',
  '#4a3b6b',
  '#1f4b5c',
  '#5a2d4a',
];

const List<String> guildEmblemSymbols = <String>[
  'sword',
  'shield',
  'tree',
  'dragon',
  'star',
  'flame',
  'moon',
  'eagle',
  'castle',
  'gem',
  'wolf',
  'lion',
];

/// Legacy emoji emblems, mapped to the solid icon ids that replaced them.
const Map<String, String> guildEmblemEmojiToSymbol = <String, String>{
  '⚔️': 'sword',
  '🛡️': 'shield',
  '🌲': 'tree',
  '🐉': 'dragon',
  '⭐': 'star',
  '🔥': 'flame',
  '🌙': 'moon',
  '🦅': 'eagle',
  '🏰': 'castle',
  '💎': 'gem',
  '🐺': 'wolf',
  '🦁': 'lion',
};

class GuildEmblem {
  const GuildEmblem({required this.color, required this.symbol});

  factory GuildEmblem.fromJson(Map<String, Object?> json) =>
      GuildEmblem(color: json['color']! as String, symbol: json['symbol']! as String);

  /// Banner fill color, as a CSS hex string the clients both understand.
  final String color;

  /// Solid icon id shown on the banner.
  final String symbol;

  Map<String, Object?> toJson() => <String, Object?>{'color': color, 'symbol': symbol};
}

class GuildRecord {
  const GuildRecord({
    required this.id,
    required this.name,
    required this.tag,
    required this.description,
    required this.emblem,
    required this.leaderId,
    required this.joinPolicy,
    required this.rankLabels,
    required this.createdAt,
    this.guestAutoAccept = false,
    this.rankIconTheme = guildRankIconThemeStripes,
  });

  factory GuildRecord.fromJson(Map<String, Object?> json) => GuildRecord(
    id: json['id']! as String,
    name: json['name']! as String,
    tag: json['tag'] as String? ?? '',
    description: json['description'] as String? ?? '',
    emblem: normalizeEmblem(json['emblem']),
    leaderId: json['leaderId']! as String,
    joinPolicy: json['joinPolicy'] as String? ?? guildJoinOpen,
    rankLabels: normalizeRankLabels(json['rankLabels']),
    createdAt: json['createdAt']! as String,
    guestAutoAccept: json['guestAutoAccept'] as bool? ?? false,
    rankIconTheme: normalizeRankIconTheme(json['rankIconTheme'] as String?),
  );

  final String id;
  final String name;

  /// 2–4 letters, displayed as `[TAG]`.
  final String tag;
  final String description;
  final GuildEmblem emblem;
  final String leaderId;
  final GuildJoinPolicy joinPolicy;
  final Map<GuildRankKey, String> rankLabels;
  final String createdAt;

  /// When true, Guest joins this guild's chat without an application.
  final bool guestAutoAccept;

  /// Which of the two rank-icon themes guild chat uses.
  final String rankIconTheme;

  GuildRecord copyWith({
    String? name,
    String? tag,
    String? description,
    GuildEmblem? emblem,
    GuildJoinPolicy? joinPolicy,
    Map<GuildRankKey, String>? rankLabels,
    bool? guestAutoAccept,
    String? rankIconTheme,
  }) => GuildRecord(
    id: id,
    name: name ?? this.name,
    tag: tag ?? this.tag,
    description: description ?? this.description,
    emblem: emblem ?? this.emblem,
    leaderId: leaderId,
    joinPolicy: joinPolicy ?? this.joinPolicy,
    rankLabels: rankLabels ?? this.rankLabels,
    createdAt: createdAt,
    guestAutoAccept: guestAutoAccept ?? this.guestAutoAccept,
    rankIconTheme: rankIconTheme ?? this.rankIconTheme,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'tag': tag,
    'description': description,
    'emblem': emblem.toJson(),
    'leaderId': leaderId,
    'joinPolicy': joinPolicy,
    'rankLabels': <String, Object?>{...rankLabels},
    'createdAt': createdAt,
    if (guestAutoAccept) 'guestAutoAccept': true,
    if (rankIconTheme != guildRankIconThemeStripes) 'rankIconTheme': rankIconTheme,
  };
}

/// A guild in the browser list, where the size matters as much as the name.
class GuildListing {
  const GuildListing({required this.guild, required this.memberCount});

  final GuildRecord guild;
  final int memberCount;

  String get id => guild.id;
  String get name => guild.name;
  String get tag => guild.tag;
  String get description => guild.description;
  GuildEmblem get emblem => guild.emblem;
  GuildJoinPolicy get joinPolicy => guild.joinPolicy;
  bool get guestAutoAccept => guild.guestAutoAccept;

  Map<String, Object?> toJson() => <String, Object?>{...guild.toJson(), 'memberCount': memberCount};
}

class GuildMember {
  const GuildMember({
    required this.guildId,
    required this.userId,
    required this.username,
    required this.role,
    required this.joinedAt,
    required this.appearance,
    required this.totalLevel,
  });

  factory GuildMember.fromJson(Map<String, Object?> json) => GuildMember(
    guildId: json['guildId']! as String,
    userId: json['userId']! as String,
    username: json['username']! as String,
    role: normalizeRole(json['role']),
    joinedAt: json['joinedAt']! as String,
    appearance: json['appearance'] is Map<String, Object?>
        ? PlayerAppearance.fromJson(json['appearance']! as Map<String, Object?>)
        : defaultPlayerAppearance,
    totalLevel: json['totalLevel'] is num ? json['totalLevel']! as num : 1,
  );

  final String guildId;
  final String userId;
  final String username;
  final GuildRole role;
  final String joinedAt;
  final PlayerAppearance appearance;
  final num totalLevel;

  GuildMember copyWith({
    String? username,
    GuildRole? role,
    PlayerAppearance? appearance,
    num? totalLevel,
  }) => GuildMember(
    guildId: guildId,
    userId: userId,
    username: username ?? this.username,
    role: role ?? this.role,
    joinedAt: joinedAt,
    appearance: appearance ?? this.appearance,
    totalLevel: totalLevel ?? this.totalLevel,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'guildId': guildId,
    'userId': userId,
    'username': username,
    'role': role,
    'joinedAt': joinedAt,
    'appearance': appearance.toJson(),
    'totalLevel': totalLevel,
  };
}

/// A player who may use this guild's chat without appearing on the roster.
class GuildGuest {
  const GuildGuest({
    required this.guildId,
    required this.userId,
    required this.username,
    required this.joinedAt,
    required this.appearance,
  });

  factory GuildGuest.fromJson(Map<String, Object?> json) => GuildGuest(
    guildId: json['guildId']! as String,
    userId: json['userId']! as String,
    username: json['username']! as String,
    joinedAt: json['joinedAt']! as String,
    appearance: json['appearance'] is Map<String, Object?>
        ? PlayerAppearance.fromJson(json['appearance']! as Map<String, Object?>)
        : defaultPlayerAppearance,
  );

  final String guildId;
  final String userId;
  final String username;
  final String joinedAt;
  final PlayerAppearance appearance;

  Map<String, Object?> toJson() => <String, Object?>{
    'guildId': guildId,
    'userId': userId,
    'username': username,
    'joinedAt': joinedAt,
    'appearance': appearance.toJson(),
  };
}

class CreateGuildInput {
  const CreateGuildInput({
    required this.name,
    required this.tag,
    this.description,
    required this.emblem,
  });

  final String name;
  final String tag;
  final String? description;
  final GuildEmblem emblem;
}

class GuildApplication {
  const GuildApplication({
    required this.id,
    required this.guildId,
    required this.userId,
    required this.username,
    required this.message,
    required this.createdAt,
    this.guest = false,
  });

  factory GuildApplication.fromJson(Map<String, Object?> json) => GuildApplication(
    id: json['id']! as String,
    guildId: json['guildId']! as String,
    userId: json['userId']! as String,
    username: json['username']! as String,
    message: json['message'] as String? ?? '',
    createdAt: json['createdAt']! as String,
    guest: json['guest'] as bool? ?? false,
  );

  final String id;
  final String guildId;
  final String userId;
  final String username;
  final String message;
  final String createdAt;
  final bool guest;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'guildId': guildId,
    'userId': userId,
    'username': username,
    'message': message,
    'createdAt': createdAt,
    if (guest) 'guest': true,
  };
}

class GuildProject {
  const GuildProject({
    required this.id,
    required this.guildId,
    required this.name,
    required this.description,
    required this.goalAmount,
    required this.contributed,
    required this.rewardLabel,
  });

  factory GuildProject.fromJson(Map<String, Object?> json) => GuildProject(
    id: json['id']! as String,
    guildId: json['guildId']! as String,
    name: json['name']! as String,
    description: json['description'] as String? ?? '',
    goalAmount: json['goalAmount']! as num,
    contributed: json['contributed']! as num,
    rewardLabel: json['rewardLabel'] as String? ?? '',
  );

  final String id;
  final String guildId;
  final String name;
  final String description;
  final num goalAmount;
  final num contributed;
  final String rewardLabel;

  GuildProject copyWith({num? contributed}) => GuildProject(
    id: id,
    guildId: guildId,
    name: name,
    description: description,
    goalAmount: goalAmount,
    contributed: contributed ?? this.contributed,
    rewardLabel: rewardLabel,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'guildId': guildId,
    'name': name,
    'description': description,
    'goalAmount': goalAmount,
    'contributed': contributed,
    'rewardLabel': rewardLabel,
  };
}

/// Per-guild hall: a shared item chest, a million-gold debt, and how far the
/// guild has built.
///
/// The storehouse doubles as the donation ledger. A finished tier spends the
/// materials it asked for, which is why nothing comes back out of it.
class GuildHallState {
  const GuildHallState({
    required this.guildId,
    required this.debtRemaining,
    required this.debtPaidBy,
    required this.storehouse,
    required this.completedTiers,
    required this.debtPaidOff,
  });

  factory GuildHallState.fresh(String guildId) => GuildHallState(
    guildId: guildId,
    debtRemaining: guildHallDebtGold,
    debtPaidBy: const <String, num>{},
    storehouse: const <InventoryStack>[],
    completedTiers: const <String>[],
    debtPaidOff: false,
  );

  factory GuildHallState.fromJson(Map<String, Object?> json) => GuildHallState(
    guildId: json['guildId']! as String,
    debtRemaining: json['debtRemaining'] is num ? json['debtRemaining']! as num : guildHallDebtGold,
    debtPaidBy: <String, num>{
      if (json['debtPaidBy'] is Map)
        for (final entry in (json['debtPaidBy']! as Map).entries)
          if (entry.key is String && entry.value is num) entry.key as String: entry.value as num,
    },
    storehouse: json['storehouse'] is List
        ? (json['storehouse']! as List)
              .map((entry) => InventoryStack.fromJson(asJsonMap(entry)))
              .toList()
        : const <InventoryStack>[],
    completedTiers: json['completedTiers'] is List
        ? (json['completedTiers']! as List).whereType<String>().toList()
        : const <String>[],
    debtPaidOff: json['debtPaidOff'] as bool? ?? false,
  );

  final String guildId;
  final num debtRemaining;
  final Map<String, num> debtPaidBy;
  final List<InventoryStack> storehouse;

  /// Tier ids the guild has finished, in the order it finished them.
  final List<String> completedTiers;
  final bool debtPaidOff;

  bool get bankUnlocked => guildHallBankUnlocked(completedTiers);
  bool get boxingUnlocked => guildHallBoxingUnlocked(completedTiers);

  GuildHallState copyWith({
    num? debtRemaining,
    Map<String, num>? debtPaidBy,
    List<InventoryStack>? storehouse,
    List<String>? completedTiers,
    bool? debtPaidOff,
  }) => GuildHallState(
    guildId: guildId,
    debtRemaining: debtRemaining ?? this.debtRemaining,
    debtPaidBy: debtPaidBy ?? this.debtPaidBy,
    storehouse: storehouse ?? this.storehouse,
    completedTiers: completedTiers ?? this.completedTiers,
    debtPaidOff: debtPaidOff ?? this.debtPaidOff,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'guildId': guildId,
    'debtRemaining': debtRemaining,
    'debtPaidBy': <String, Object?>{...debtPaidBy},
    'storehouse': storehouse.map((row) => row.toJson()).toList(),
    'completedTiers': completedTiers,
    'debtPaidOff': debtPaidOff,
  };
}

class GuildChallenge {
  const GuildChallenge({
    required this.id,
    required this.guildId,
    required this.name,
    required this.boardKey,
    required this.goalValue,
    required this.currentValue,
  });

  factory GuildChallenge.fromJson(Map<String, Object?> json) => GuildChallenge(
    id: json['id']! as String,
    guildId: json['guildId']! as String,
    name: json['name']! as String,
    boardKey: json['boardKey']! as String,
    goalValue: json['goalValue']! as num,
    currentValue: json['currentValue']! as num,
  );

  final String id;
  final String guildId;
  final String name;
  final MultiplayerBoardKey boardKey;
  final num goalValue;
  final num currentValue;

  GuildChallenge copyWith({num? currentValue}) => GuildChallenge(
    id: id,
    guildId: guildId,
    name: name,
    boardKey: boardKey,
    goalValue: goalValue,
    currentValue: currentValue ?? this.currentValue,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'guildId': guildId,
    'name': name,
    'boardKey': boardKey,
    'goalValue': goalValue,
    'currentValue': currentValue,
  };
}

/// What another player is doing, kept only as long as its TTL.
class ActivityPresence {
  const ActivityPresence({
    required this.userId,
    required this.username,
    required this.appearance,
    required this.guildName,
    required this.locationId,
    required this.currentActivityId,
    required this.skillId,
    required this.skillLevel,
    required this.outfitCosmeticId,
    required this.mountCosmeticId,
    required this.updatedAt,
    required this.expiresAt,
  });

  factory ActivityPresence.fromJson(Map<String, Object?> json) => ActivityPresence(
    userId: json['userId']! as String,
    username: json['username']! as String,
    appearance: PlayerAppearance.fromJson(json['appearance']! as Map<String, Object?>),
    guildName: json['guildName'] as String?,
    locationId: json['locationId']! as String,
    currentActivityId: json['currentActivityId'] as String?,
    skillId: json['skillId'] as String?,
    skillLevel: json['skillLevel'] as num?,
    outfitCosmeticId: json['outfitCosmeticId'] as String?,
    mountCosmeticId: json['mountCosmeticId'] as String?,
    updatedAt: json['updatedAt']! as String,
    expiresAt: json['expiresAt']! as String,
  );

  final String userId;
  final String username;
  final PlayerAppearance appearance;
  final String? guildName;
  final String locationId;
  final String? currentActivityId;
  final String? skillId;
  final num? skillLevel;
  final String? outfitCosmeticId;
  final String? mountCosmeticId;
  final String updatedAt;
  final String expiresAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'userId': userId,
    'username': username,
    'appearance': appearance.toJson(),
    'guildName': guildName,
    'locationId': locationId,
    'currentActivityId': currentActivityId,
    'skillId': skillId,
    'skillLevel': skillLevel,
    'outfitCosmeticId': outfitCosmeticId,
    'mountCosmeticId': mountCosmeticId,
    'updatedAt': updatedAt,
    'expiresAt': expiresAt,
  };
}

/// What the player publishes about themselves, before the backend stamps it.
class PresenceInput {
  const PresenceInput({
    required this.appearance,
    required this.locationId,
    required this.currentActivityId,
    required this.skillId,
    required this.skillLevel,
    required this.outfitCosmeticId,
    required this.mountCosmeticId,
  });

  final PlayerAppearance appearance;
  final String locationId;
  final String? currentActivityId;
  final String? skillId;
  final num? skillLevel;
  final String? outfitCosmeticId;
  final String? mountCosmeticId;
}

class MultiplayerSession {
  const MultiplayerSession({
    required this.userId,
    required this.email,
    required this.username,
    required this.accessToken,
    this.playSessionId,
  });

  factory MultiplayerSession.fromJson(Map<String, Object?> json) => MultiplayerSession(
    userId: json['userId']! as String,
    email: json['email']! as String,
    username: json['username']! as String,
    accessToken: json['accessToken'] as String? ?? '',
    playSessionId: json['playSessionId'] as String?,
  );

  final String userId;
  final String email;
  final String username;
  final String accessToken;

  /// Which device currently holds the account. A new sign-in replaces it.
  final String? playSessionId;

  MultiplayerSession copyWith({String? playSessionId}) => MultiplayerSession(
    userId: userId,
    email: email,
    username: username,
    accessToken: accessToken,
    playSessionId: playSessionId ?? this.playSessionId,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'userId': userId,
    'email': email,
    'username': username,
    'accessToken': accessToken,
    if (playSessionId != null) 'playSessionId': playSessionId,
  };
}

/// One public skill line on another player's profile.
class PublicSkillLine {
  const PublicSkillLine({required this.skillId, required this.level, required this.xp});

  final String skillId;
  final num level;
  final num xp;

  Map<String, Object?> toJson() => <String, Object?>{'skillId': skillId, 'level': level, 'xp': xp};
}

class PublicPlayerProfile {
  const PublicPlayerProfile({
    required this.userId,
    required this.username,
    required this.appearance,
    required this.guildName,
    required this.publicSkills,
    required this.achievementsUnlocked,
    required this.totalLevel,
  });

  final String userId;
  final String username;
  final PlayerAppearance appearance;
  final String? guildName;
  final List<PublicSkillLine> publicSkills;
  final num achievementsUnlocked;
  final num totalLevel;

  Map<String, Object?> toJson() => <String, Object?>{
    'userId': userId,
    'username': username,
    'appearance': appearance.toJson(),
    'guildName': guildName,
    'publicSkills': publicSkills.map((row) => row.toJson()).toList(),
    'achievementsUnlocked': achievementsUnlocked,
    'totalLevel': totalLevel,
  };
}

/// Citadel Plaza — hub presence and the Nearby listing target.
const String citadelLocationIdValue = 'LOC-0028';

/// Stable Local-chat key while on the Citadel sub-map, giving `local:citadel`.
const String citadelChatLocationId = 'citadel';
const String multiplayerSessionKey = 'idle-kingdoms.multiplayer.session';
const String multiplayerLocalDbKey = 'idle-kingdoms.multiplayer.local-db';

String chatChannelKey(ChatChannel channel) => switch (channel) {
  GlobalChatChannel() => 'global',
  LocalChatChannel(:final locationId) => 'local:$locationId',
  GuildChatChannel(:final guildId) => 'guild:$guildId',
  DirectChatChannel(:final pairKey) => 'dm:$pairKey',
};

String dmPairKey(String userA, String userB) {
  final pair = <String>[userA, userB]..sort();
  return pair.join(':');
}

/// The appearance a row falls back to when no save or profile supplied one.
const PlayerAppearance defaultPlayerAppearance = PlayerAppearance(
  skinTone: defaultSkinToneId,
  hairstyle: defaultHairstyleId,
  hairColor: defaultHairColorId,
  expression: defaultExpressionId,
  beard: defaultBeardId,
  genderPresentation: defaultGenderPresentationId,
);

/// A stored symbol, an emoji from an older save, or anything unrecognized,
/// resolved to one of the icons the clients can actually draw.
String normalizeSymbol(Object? raw) {
  if (raw is! String || raw.trim().isEmpty) return guildEmblemSymbols.first;
  final value = raw.trim();
  if (guildEmblemSymbols.contains(value)) return value;
  return guildEmblemEmojiToSymbol[value] ?? guildEmblemSymbols.first;
}

GuildEmblem normalizeEmblem(Object? raw) {
  if (raw is Map<String, Object?> && raw.containsKey('color') && raw.containsKey('symbol')) {
    final color = raw['color'];
    return GuildEmblem(
      color: color is String ? color : guildEmblemColors.first,
      symbol: normalizeSymbol(raw['symbol']),
    );
  }
  if (raw is GuildEmblem) {
    return GuildEmblem(color: raw.color, symbol: normalizeSymbol(raw.symbol));
  }
  if (raw is String && raw.trim().isNotEmpty) {
    return GuildEmblem(color: guildEmblemColors.first, symbol: normalizeSymbol(raw));
  }
  return GuildEmblem(color: guildEmblemColors.first, symbol: guildEmblemSymbols.first);
}

Map<GuildRankKey, String> normalizeRankLabels(Object? raw) {
  final base = <GuildRankKey, String>{...defaultGuildRankLabels};
  if (raw is! Map<String, Object?>) return base;
  for (final key in defaultGuildRankLabels.keys) {
    final value = raw[key];
    if (value is! String) continue;
    final trimmed = value.trim();
    if (trimmed.isEmpty) continue;
    base[key] = trimmed.length > 18 ? trimmed.substring(0, 18) : trimmed;
  }
  return base;
}

GuildRole normalizeRole(Object? raw) {
  if (raw == guildRoleLeader ||
      raw == guildRoleOfficer ||
      raw == guildRoleVeteran ||
      raw == guildRoleMember ||
      raw == guildRoleRecruit) {
    return raw! as String;
  }
  return guildRoleRecruit;
}

final RegExp _nonLetters = RegExp('[^a-zA-Z]');

String _letterTag(String source) {
  final clean = source.replaceAll(_nonLetters, '').toUpperCase();
  return clean.length > 4 ? clean.substring(0, 4) : clean;
}

/// A tag the player typed, falling back to initials from the name.
String normalizeTag(String name, Object? tag) {
  if (tag is String) {
    final clean = _letterTag(tag);
    if (clean.length >= 2) return clean;
  }
  final fromName = _letterTag(name);
  return fromName.length >= 2 ? fromName : 'GD';
}

String guildRoleLabel(GuildRecord guild, GuildRole role) => guild.rankLabels[role] ?? role;
