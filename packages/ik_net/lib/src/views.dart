import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'config.dart';
import 'moderation.dart';
import 'snapshots.dart';
import 'types.dart';

/// How many skills a public profile shows before it stops.
const int publicProfileSkillLimit = 8;

/// The ranks a guild leader can rename, Leader included.
const List<GuildRankKey> editableRankKeys = <GuildRankKey>[
  guildRoleLeader,
  guildRoleOfficer,
  guildRoleVeteran,
  guildRoleMember,
  guildRoleRecruit,
];

/// Which end of the join order a roster starts from.
enum GuildRosterSort { oldest, newest }

String _policyLabel(GuildJoinPolicy policy) =>
    policy == guildJoinOpen ? 'Accept applications' : 'Closed';

/// One row of the guild browser.
class GuildBrowseRow {
  const GuildBrowseRow({
    required this.guildId,
    required this.title,
    required this.subtitle,
    required this.emblem,
    required this.tag,
    required this.actionLabel,
    required this.guestLabel,
    required this.full,
  });

  final String guildId;

  /// `[IRN] Iron League`.
  final String title;

  /// `Accept applications · 4/25 · For the kingdom`.
  final String subtitle;
  final GuildEmblem emblem;
  final String tag;

  /// `Join`, `Apply`, or `Full`.
  final String actionLabel;

  /// Always `Guest` — guests do not count toward the member cap.
  final String guestLabel;

  /// True when the guild has no room left for members.
  final bool full;

  Map<String, Object?> toJson() => <String, Object?>{
    'guildId': guildId,
    'title': title,
    'subtitle': subtitle,
    'emblem': emblem.toJson(),
    'tag': tag,
    'actionLabel': actionLabel,
    'guestLabel': guestLabel,
    'full': full,
  };
}

/// The guilds worth showing for [query].
///
/// A player who types `[irn]` means the tag they saw in chat, so the bracketed
/// form matches too.
List<GuildListing> filterGuildListings(List<GuildListing> rows, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return rows;
  return rows.where((row) {
    final tag = row.tag.toLowerCase();
    return row.name.toLowerCase().contains(needle) ||
        tag.contains(needle) ||
        '[$tag]'.contains(needle);
  }).toList();
}

List<GuildBrowseRow> guildBrowseRows(List<GuildListing> rows, [String query = '']) {
  return filterGuildListings(rows, query).map((row) {
    final full = row.memberCount >= guildMaxMembers;
    final description = row.description.isEmpty ? 'No description.' : row.description;
    return GuildBrowseRow(
      guildId: row.id,
      title: '[${row.tag}] ${row.name}',
      subtitle: <String>[
        _policyLabel(row.joinPolicy),
        '${row.memberCount}/$guildMaxMembers',
        description,
      ].join(' · '),
      emblem: row.emblem,
      tag: row.tag,
      actionLabel: full
          ? 'Full'
          : row.joinPolicy == guildJoinOpen
          ? 'Join'
          : 'Apply',
      guestLabel: 'Guest',
      full: full,
    );
  }).toList();
}

/// The message an application carries when the player writes nothing.
///
/// A character with no name still has to introduce themselves, so a blank name
/// reads as Adventurer rather than as leading whitespace.
String defaultApplicationMessage(String? characterName) {
  final name = characterName?.trim() ?? '';
  return '${name.isEmpty ? 'Adventurer' : name} requests to join';
}

/// What the guild home shows above its roster.
class GuildHomeHeader {
  const GuildHomeHeader({
    required this.title,
    required this.subtitle,
    required this.emblem,
    required this.tag,
    required this.canManage,
  });

  final String title;
  final String subtitle;
  final GuildEmblem emblem;
  final String tag;

  /// True when the viewer may open settings and manage ranks.
  final bool canManage;

  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'subtitle': subtitle,
    'emblem': emblem.toJson(),
    'tag': tag,
    'canManage': canManage,
  };
}

GuildHomeHeader guildHomeHeader(GuildRecord guild, int memberCount, String? viewerId) {
  return GuildHomeHeader(
    title: '[${guild.tag}] ${guild.name}',
    subtitle: '${_policyLabel(guild.joinPolicy)} · $memberCount/$guildMaxMembers members',
    emblem: guild.emblem,
    tag: guild.tag,
    canManage: viewerId != null && guild.leaderId == viewerId,
  );
}

/// One rank a leader can move a member to, under this guild's own names.
class GuildRankOption {
  const GuildRankOption({required this.role, required this.label});

  final GuildRole role;
  final String label;

  Map<String, Object?> toJson() => <String, Object?>{'role': role, 'label': label};
}

List<GuildRankOption> guildRankOptions(GuildRecord guild) {
  return promotableGuildRanks
      .map(
        (role) => GuildRankOption(
          role: role,
          label: guild.rankLabels[role] ?? defaultGuildRankLabels[role]!,
        ),
      )
      .toList();
}

/// One row of the guild roster.
class GuildRosterRow {
  const GuildRosterRow({
    required this.userId,
    required this.position,
    required this.username,
    required this.rankLabel,
    required this.role,
    required this.totalLevel,
    required this.appearance,
    required this.manageable,
    this.lastOnlineAt,
    this.isOnline = false,
    this.lastOnlineLabel = 'Unknown',
  });

  final String userId;

  /// Position in the roster as shown, counting from one.
  final int position;
  final String username;

  /// This guild's name for the member's rank.
  final String rankLabel;
  final GuildRole role;
  final num totalLevel;
  final PlayerAppearance appearance;

  /// True when the viewer can change this member's rank.
  final bool manageable;

  /// Presence `updatedAt`, or null when this member has never been seen.
  final String? lastOnlineAt;
  final bool isOnline;

  /// `Online`, a relative time, or `Unknown`.
  final String lastOnlineLabel;

  Map<String, Object?> toJson() => <String, Object?>{
    'userId': userId,
    'position': position,
    'username': username,
    'rankLabel': rankLabel,
    'role': role,
    'totalLevel': totalLevel,
    'appearance': appearance.toJson(),
    'manageable': manageable,
    'lastOnlineAt': lastOnlineAt,
    'isOnline': isOnline,
    'lastOnlineLabel': lastOnlineLabel,
  };
}

/// Presence age → the roster's last-online line.
({String? lastOnlineAt, bool isOnline, String lastOnlineLabel}) rosterLastOnline(
  String? updatedAt,
  num nowMs,
) {
  if (updatedAt == null || updatedAt.isEmpty) {
    return (lastOnlineAt: null, isOnline: false, lastOnlineLabel: 'Unknown');
  }
  final then = jsDateParse(updatedAt);
  if (!then.isFinite) {
    return (lastOnlineAt: null, isOnline: false, lastOnlineLabel: 'Unknown');
  }
  final age = nowMs - then;
  if (age >= 0 && age < presenceTtlSeconds * 1000) {
    return (lastOnlineAt: updatedAt, isOnline: true, lastOnlineLabel: 'Online');
  }
  final minutes = (age / 60000).floor();
  if (minutes < 1) {
    return (lastOnlineAt: updatedAt, isOnline: false, lastOnlineLabel: 'Just now');
  }
  if (minutes < 60) {
    return (lastOnlineAt: updatedAt, isOnline: false, lastOnlineLabel: '${minutes}m ago');
  }
  final hours = (minutes / 60).floor();
  if (hours < 24) {
    return (lastOnlineAt: updatedAt, isOnline: false, lastOnlineLabel: '${hours}h ago');
  }
  final days = (hours / 24).floor();
  return (lastOnlineAt: updatedAt, isOnline: false, lastOnlineLabel: '${days}d ago');
}

/// The roster in join order.
///
/// Ties keep the order the backend returned, which is itself join order, so two
/// members who joined in the same second do not swap places between refreshes.
List<GuildRosterRow> guildRosterRows(
  GuildRecord guild,
  List<GuildMember> members,
  GuildRosterSort sort,
  String? viewerId, {
  List<ActivityPresence> presence = const <ActivityPresence>[],
  num? nowMs,
}) {
  final canManage = viewerId != null && guild.leaderId == viewerId;
  final clock = nowMs ?? 0;
  final seen = <String, String>{for (final row in presence) row.userId: row.updatedAt};
  final indexed = members.indexed.toList();
  indexed.sort((a, b) {
    final delta = jsDateParse(a.$2.joinedAt) - jsDateParse(b.$2.joinedAt);
    if (delta != 0) {
      return sort == GuildRosterSort.oldest ? delta.sign.toInt() : -delta.sign.toInt();
    }
    return a.$1 - b.$1;
  });
  return indexed.indexed.map((outer) {
    final member = outer.$2.$2;
    final online = rosterLastOnline(seen[member.userId], clock);
    return GuildRosterRow(
      userId: member.userId,
      position: outer.$1 + 1,
      username: member.username,
      rankLabel: guildRoleLabel(guild, member.role),
      role: member.role,
      totalLevel: member.totalLevel,
      appearance: member.appearance,
      manageable: canManage && member.role != guildRoleLeader,
      lastOnlineAt: online.lastOnlineAt,
      isOnline: online.isOnline,
      lastOnlineLabel: online.lastOnlineLabel,
    );
  }).toList();
}

/// One pending application, as the leader reads it.
class GuildApplicationRow {
  const GuildApplicationRow({
    required this.applicationId,
    required this.username,
    required this.message,
    this.guest = false,
  });

  final String applicationId;
  final String username;
  final String message;
  final bool guest;

  Map<String, Object?> toJson() => <String, Object?>{
    'applicationId': applicationId,
    'username': username,
    'message': message,
    if (guest) 'guest': true,
  };
}

List<GuildApplicationRow> guildApplicationRows(List<GuildApplication> applications) {
  return applications
      .map(
        (application) => GuildApplicationRow(
          applicationId: application.id,
          username: application.username,
          message: application.guest
              ? (application.message.isEmpty ? 'Guest request.' : 'Guest: ${application.message}')
              : (application.message.isEmpty ? 'No message.' : application.message),
          guest: application.guest,
        ),
      )
      .toList();
}

/// Everything the create-guild form needs to render itself.
class CreateGuildFormView {
  const CreateGuildFormView({
    required this.goldCost,
    required this.costLine,
    required this.tagPreview,
    required this.canAfford,
    required this.submitLabel,
  });

  final num goldCost;

  /// `Costs 25 gold · you have 1,200`.
  final String costLine;

  /// `[IRN]`, or `[??]` before anything is typed.
  final String tagPreview;
  final bool canAfford;

  /// `Create for 25 gold`, or why the button is off.
  final String submitLabel;

  Map<String, Object?> toJson() => <String, Object?>{
    'goldCost': goldCost,
    'costLine': costLine,
    'tagPreview': tagPreview,
    'canAfford': canAfford,
    'submitLabel': submitLabel,
  };
}

final RegExp _nonLetters = RegExp('[^a-zA-Z]');

/// Keeps a tag to the letters a tag may contain, as the player types.
String sanitizeGuildTagInput(String raw) {
  final letters = raw.replaceAll(_nonLetters, '').toUpperCase();
  return letters.length <= 4 ? letters : letters.substring(0, 4);
}

CreateGuildFormView createGuildFormView(num gold, String tag) {
  final canAfford = gold >= guildCreateGoldCost;
  final preview = sanitizeGuildTagInput(tag);
  return CreateGuildFormView(
    goldCost: guildCreateGoldCost,
    costLine: 'Costs $guildCreateGoldCost gold · you have ${jsLocaleNumber(gold)}',
    tagPreview: '[${preview.isEmpty ? '??' : preview}]',
    canAfford: canAfford,
    submitLabel: canAfford ? 'Create for $guildCreateGoldCost gold' : 'Not enough gold',
  );
}

/// One rank name field in guild settings.
class RankLabelField {
  const RankLabelField({required this.role, required this.fieldLabel, required this.value});

  final GuildRankKey role;

  /// `Officer slot`.
  final String fieldLabel;
  final String value;

  Map<String, Object?> toJson() => <String, Object?>{
    'role': role,
    'fieldLabel': fieldLabel,
    'value': value,
  };
}

List<RankLabelField> rankLabelFields(GuildRecord guild) {
  return editableRankKeys
      .map(
        (role) => RankLabelField(
          role: role,
          fieldLabel: '${defaultGuildRankLabels[role]} slot',
          value: guild.rankLabels[role] ?? defaultGuildRankLabels[role]!,
        ),
      )
      .toList();
}

/// The sentence that asks a player to confirm leaving.
String leaveGuildPrompt(GuildRecord guild) =>
    'Leave [${guild.tag}] ${guild.name}? You will need to rejoin or reapply later.';

/// One board the leaderboard picker offers.
class BoardOption {
  const BoardOption({required this.key, required this.label});

  final MultiplayerBoardKey key;
  final String label;

  Map<String, Object?> toJson() => <String, Object?>{'key': key, 'label': label};
}

List<BoardOption> boardOptions(GameDatabase db) {
  return launchBoardKeys(db)
      .map((key) => BoardOption(key: key, label: boardLabel(db, key)))
      .toList();
}

/// One row of a leaderboard.
class LeaderboardRowView {
  const LeaderboardRowView({
    required this.rank,
    required this.entryId,
    required this.username,
    required this.subtitle,
    required this.valueLabel,
    required this.emblem,
    required this.appearance,
    required this.isGuild,
    this.secondaryLabel,
  });

  final num rank;

  /// A user id for a player, a guild id for a guild.
  final String entryId;
  final String username;

  /// The guild a player belongs to, or how full a guild is.
  final String subtitle;

  /// `1,204`, grouped the way the rest of the UI groups numbers. On a combined
  /// board this is the level, with the experience in [secondaryLabel].
  final String valueLabel;

  /// `12,300,000 xp` under the level, on a board that shows both. Null when the
  /// board ranks by one thing.
  final String? secondaryLabel;

  /// Set for a guild row, whose badge stands in for a portrait.
  final GuildEmblem? emblem;
  final PlayerAppearance appearance;
  final bool isGuild;

  Map<String, Object?> toJson() => <String, Object?>{
    'rank': rank,
    'entryId': entryId,
    'username': username,
    'subtitle': subtitle,
    'valueLabel': valueLabel,
    if (secondaryLabel != null) 'secondaryLabel': secondaryLabel,
    'emblem': emblem?.toJson(),
    'appearance': appearance.toJson(),
    'isGuild': isGuild,
  };
}

List<LeaderboardRowView> leaderboardRows(List<LeaderboardEntry> entries) {
  return entries.map((entry) {
    final isGuild = entry.entryKind == LeaderboardEntryKind.guild;
    final experience = entry.secondaryValue;
    return LeaderboardRowView(
      rank: entry.rank,
      entryId: entry.userId,
      username: entry.username,
      subtitle: isGuild ? (entry.guildName ?? 'Guild') : (entry.guildName ?? 'No guild'),
      valueLabel: jsLocaleNumber(entry.value),
      secondaryLabel: experience == null ? null : '${jsLocaleNumber(experience)} xp',
      emblem: isGuild ? entry.emblem : null,
      appearance: entry.appearance,
      isGuild: isGuild,
    );
  }).toList();
}

/// What an empty board says, which differs for guilds.
String emptyBoardMessage(MultiplayerBoardKey boardKey) {
  if (boardKey == boardPacifistTotalLevel) {
    return 'No scores on this board yet. Keep Combat at level 1 to stand on it.';
  }
  return boardKey == boardGuildTotalLevel
      ? 'No guilds yet — create or join one from the Guilds tab.'
      : 'No scores on this board yet.';
}

/// One player standing in a shared space, or working the same activity.
class PeerRowView {
  const PeerRowView({
    required this.userId,
    required this.username,
    required this.subtitle,
    required this.appearance,
  });

  final String userId;
  final String username;

  /// `Combat 7 · Iron League`, with an em dash for an unknown level.
  final String subtitle;
  final PlayerAppearance appearance;

  Map<String, Object?> toJson() => <String, Object?>{
    'userId': userId,
    'username': username,
    'subtitle': subtitle,
    'appearance': appearance.toJson(),
  };
}

List<PeerRowView> peerRows(
  List<ActivityPresence> peers,
  String Function(String? skillId) skillName,
) {
  return peers.map((peer) {
    final level = peer.skillLevel == null ? '—' : jsNumberToString(peer.skillLevel!);
    return PeerRowView(
      userId: peer.userId,
      username: peer.username,
      subtitle: <String>[
        '${skillName(peer.skillId)} $level',
        if (peer.guildName != null) peer.guildName!,
      ].join(' · '),
      appearance: peer.appearance,
    );
  }).toList();
}

/// What the Citadel visitor list says about one visitor.
String citadelVisitorSubtitle(ActivityPresence visitor) {
  final guild = visitor.guildName ?? 'No guild';
  final level = visitor.skillLevel;
  return level == null ? guild : '$guild · Lv ${jsNumberToString(level)}';
}

/// The public profile sheet, with nothing left to derive.
class PublicProfileView {
  const PublicProfileView({
    required this.userId,
    required this.username,
    required this.appearance,
    required this.summaryLine,
    required this.skillLines,
    required this.skillsHidden,
  });

  final String userId;
  final String username;
  final PlayerAppearance appearance;

  /// `Total level 214 · Iron League · 12 achievements`.
  final String summaryLine;

  /// At most [publicProfileSkillLimit] lines like `Combat 12`.
  final List<String> skillLines;

  /// True when the player hid their skills.
  final bool skillsHidden;

  Map<String, Object?> toJson() => <String, Object?>{
    'userId': userId,
    'username': username,
    'appearance': appearance.toJson(),
    'summaryLine': summaryLine,
    'skillLines': skillLines,
    'skillsHidden': skillsHidden,
  };
}

PublicProfileView publicProfileView(
  PublicPlayerProfile profile,
  String Function(String? skillId) skillName,
) {
  final skills = profile.publicSkills.length <= publicProfileSkillLimit
      ? profile.publicSkills
      : profile.publicSkills.sublist(0, publicProfileSkillLimit);
  return PublicProfileView(
    userId: profile.userId,
    username: profile.username,
    appearance: profile.appearance,
    summaryLine: <String>[
      'Total level ${jsNumberToString(profile.totalLevel)}',
      if (profile.guildName != null) profile.guildName!,
      '${jsNumberToString(profile.achievementsUnlocked)} achievements',
    ].join(' · '),
    skillLines: skills
        .map((skill) => '${skillName(skill.skillId)} ${jsNumberToString(skill.level)}')
        .toList(),
    skillsHidden: profile.publicSkills.isEmpty,
  );
}

/// The rooms the chat drawer offers, in tab order.
enum ChatTab {
  global('global'),
  local('local'),
  guild('guild'),
  guest('guest'),
  dm('dm');

  const ChatTab(this.wire);

  final String wire;
}

const List<ChatTab> chatTabOrder = <ChatTab>[
  ChatTab.global,
  ChatTab.local,
  ChatTab.guild,
  ChatTab.guest,
  ChatTab.dm,
];

/// One tab of the chat drawer.
class ChatTabView {
  const ChatTabView({
    required this.tab,
    required this.label,
    required this.enabled,
    required this.selected,
  });

  final ChatTab tab;

  /// `Global`, `Citadel` inside the hub, `Private (3)` when messages wait.
  final String label;

  /// False for guild or guest chat without a room to show.
  final bool enabled;
  final bool selected;

  Map<String, Object?> toJson() => <String, Object?>{
    'tab': tab.wire,
    'label': label,
    'enabled': enabled,
    'selected': selected,
  };
}

/// Which location the Local tab is talking about.
///
/// Every Citadel district shares one room, so the hub answers with its own id
/// rather than the district the player happens to stand in.
String chatLocalLocationId(String locationId, bool citadelHub) =>
    citadelHub ? citadelChatLocationId : locationId;

/// How many unread messages a badge admits to, before it gives up counting.
String? unreadBadgeLabel(num count) {
  if (count <= 0) return null;
  return count > 9 ? '9+' : jsNumberToString(count);
}

List<ChatTabView> chatTabs({
  required ChatTab selected,
  required bool citadelHub,
  required bool hasGuild,
  required bool hasGuest,
  required num unreadDms,
}) {
  return chatTabOrder.map((tab) {
    final label = switch (tab) {
      ChatTab.global => 'Global',
      ChatTab.local => citadelHub ? 'Citadel' : 'Local',
      ChatTab.guild => 'Guild',
      ChatTab.guest => 'Guest',
      ChatTab.dm => unreadDms > 0 ? 'Private (${jsNumberToString(unreadDms)})' : 'Private',
    };
    return ChatTabView(
      tab: tab,
      label: label,
      enabled: switch (tab) {
        ChatTab.guild => hasGuild,
        ChatTab.guest => hasGuest,
        _ => true,
      },
      selected: tab == selected,
    );
  }).toList();
}

/// The room a tab writes to, or null when it is not a room at all.
///
/// Private messages are a reply to a person rather than a channel, and guild
/// or guest chat without a guild has nowhere to go.
ChatChannel? chatChannelForTab(
  ChatTab tab, {
  required String locationId,
  required bool citadelHub,
  required String? guildId,
  String? guestGuildId,
}) {
  return switch (tab) {
    ChatTab.global => const ChatChannel.global(),
    ChatTab.local => ChatChannel.local(chatLocalLocationId(locationId, citadelHub)),
    ChatTab.guild => guildId == null ? null : ChatChannel.guild(guildId),
    ChatTab.guest => guestGuildId == null ? null : ChatChannel.guild(guestGuildId),
    ChatTab.dm => null,
  };
}

/// What an empty room says, which differs for private messages.
String emptyChatMessage(ChatTab tab) =>
    tab == ChatTab.dm ? 'No private messages yet.' : 'No messages yet.';

/// Why the Private tab has no composer.
const String chatDmHint = 'Reply to players from Nearby Adventurers or their public profile.';

/// What a player is told when they try to use guild chat without a guild.
const String chatNoGuildNotice = 'Join a guild to use guild chat.';

const String chatNoGuestNotice = 'Guest a guild to use guest chat.';

const String chatViewGuildsLabel = 'View guilds';

/// Where the read cursor for one account's DMs is kept.
String dmReadCursorKey(String userId) => 'idle-kingdoms.chat.dm-read-at:$userId';

/// One line of a chat room.
class ChatLineView {
  const ChatLineView({
    required this.messageId,
    required this.username,
    required this.body,
    required this.mine,
  });

  final String messageId;
  final String username;
  final String body;

  /// True for the viewer's own messages, which read differently.
  final bool mine;

  Map<String, Object?> toJson() => <String, Object?>{
    'messageId': messageId,
    'username': username,
    'body': body,
    'mine': mine,
  };
}

List<ChatLineView> chatLines(
  List<ChatMessage> messages,
  String? viewerId, {
  bool filterProfanityEnabled = false,
}) {
  return messages
      .map(
        (message) => ChatLineView(
          messageId: message.id,
          username: chatLineUsername(message),
          body: filterProfanityEnabled ? filterProfanity(message.body) : message.body,
          mine: viewerId != null && message.userId == viewerId,
        ),
      )
      .toList();
}

/// `[TAG] Hero` in global/local, rank or Guest in guild rooms.
String chatLineUsername(ChatMessage message) {
  if (message.channelKey.startsWith('guild:')) {
    if (message.guest) return 'Guest ${message.username}';
    final icon = message.rankIcon;
    final rank = message.rankLabel;
    if (icon != null && rank != null) return '$icon $rank ${message.username}';
    if (rank != null) return '$rank ${message.username}';
    return message.username;
  }
  final tag = message.guildTag;
  if (tag != null && tag.isNotEmpty) return '[$tag] ${message.username}';
  return message.username;
}

/// Where multiplayer data lives, as the account panel says it.
enum MultiplayerMode { local, supabase }

String multiplayerModeLine(MultiplayerMode mode) {
  final backend = mode == MultiplayerMode.local ? 'local demo backend' : 'Supabase';
  return 'Accounts use the $backend. Sign in to play and sync progress.';
}

/// What the entry gate says before character creation.
String authGateIntro(MultiplayerMode mode) {
  final backend = mode == MultiplayerMode.local ? 'local demo backend' : 'Supabase';
  return 'Create an account with your email to begin. Character creation comes next. Accounts use the $backend.';
}

/// The line every signed-out multiplayer panel shows instead of content.
const String signInPrompt = 'Sign in to use multiplayer features.';

/// Guilds word the same prompt around guilds, since that is the tab in hand.
const String guildSignInPrompt = 'Sign in to use guilds.';
