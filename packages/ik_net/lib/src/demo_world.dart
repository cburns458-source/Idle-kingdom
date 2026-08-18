import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'local_db.dart';
import 'types.dart';

/// Static accounts used to exercise Nearby, guild search, and profiles.
const String demoGuildId = 'gld_demo_watch';
const String demoGuildName = 'The Watch';
const String demoGuildTag = 'WCH';

const String demoMiraId = 'usr_demo_mira';
const String demoBramId = 'usr_demo_bram';
const String demoKaelId = 'usr_demo_kael';

const String demoMiraName = 'Mira';
const String demoBramName = 'Bram';
const String demoKaelName = 'Kael';

/// Meadow gathering, so a player standing there sees Mira in Nearby.
const String demoMiraLocationId = 'LOC-0009';
const String demoMiraActivityId = 'ACT-0012';
const String demoMiraSkillId = 'SKL-0004';

/// Town square, idle.
const String demoBramLocationId = 'LOC-0002';
const String demoBramSkillId = 'SKL-0007';

/// Citadel Plaza.
const String demoKaelLocationId = 'LOC-0028';
const String demoKaelSkillId = 'SKL-0001';

const Set<String> demoPlayerIds = <String>{demoMiraId, demoBramId, demoKaelId};

bool isDemoPlayerId(String userId) => demoPlayerIds.contains(userId);

/// Takes The Watch and its three characters back off this device.
///
/// A build with a real backend calls this on boot, because a device that once
/// ran an offline build still has the practice guild sitting in its storage,
/// and beside real players it reads as a test account nobody can reach.
void removeDemoWorld(LocalDb db) {
  db.users = db.users.where((row) => !isDemoPlayerId(row.userId)).toList();
  db.profiles = db.profiles.where((row) => !isDemoPlayerId(row.userId)).toList();
  db.saves = db.saves.where((row) => !isDemoPlayerId(row.userId)).toList();
  db.leaderboards = db.leaderboards.where((row) => !isDemoPlayerId(row.userId)).toList();
  db.presence = db.presence.where((row) => !isDemoPlayerId(row.userId)).toList();
  db.messages = db.messages.where((row) => !row.id.startsWith('msg_demo_')).toList();
  db.friends = db.friends
      .where((row) => !isDemoPlayerId(row.userA) && !isDemoPlayerId(row.userB))
      .toList();
  db.friendRequests = db.friendRequests
      .where((row) => !isDemoPlayerId(row.fromUserId) && !isDemoPlayerId(row.toUserId))
      .toList();
  db.blocks = db.blocks
      .where((row) => !isDemoPlayerId(row.userId) && !isDemoPlayerId(row.otherUserId))
      .toList();
  db.mutes = db.mutes
      .where((row) => !isDemoPlayerId(row.userId) && !isDemoPlayerId(row.otherUserId))
      .toList();

  db.guilds = db.guilds.where((row) => row.id != demoGuildId).toList();
  db.members = db.members.where((row) => row.guildId != demoGuildId).toList();
  db.applications = db.applications.where((row) => row.guildId != demoGuildId).toList();
  db.projects = db.projects.where((row) => row.guildId != demoGuildId).toList();
  db.challenges = db.challenges.where((row) => row.guildId != demoGuildId).toList();
  db.guests = db.guests.where((row) => row.guildId != demoGuildId).toList();
  db.halls = db.halls.where((row) => row.guildId != demoGuildId).toList();
}

/// Seeds The Watch and its three members, and refreshes their presence.
///
/// Idempotent: a second call does not duplicate rows, and extra members who
/// joined the guild are left in place. Presence is always rewritten so the
/// three stay visible after the normal TTL.
void applyDemoWorld(LocalDb db, GameDatabase gameDb, {required num nowMs, required String nowIso}) {
  final miraLook = defaultPlayerAppearance.copyWith(genderPresentation: 'APR-0017');
  final bramLook = defaultPlayerAppearance.copyWith(
    genderPresentation: 'APR-0018',
    hairColor: 'APR-0008',
  );
  final kaelLook = defaultPlayerAppearance.copyWith(genderPresentation: 'APR-0019');

  _upsertAccount(
    db,
    userId: demoMiraId,
    username: demoMiraName,
    appearance: miraLook,
    nowIso: nowIso,
  );
  _upsertAccount(
    db,
    userId: demoBramId,
    username: demoBramName,
    appearance: bramLook,
    nowIso: nowIso,
  );
  _upsertAccount(
    db,
    userId: demoKaelId,
    username: demoKaelName,
    appearance: kaelLook,
    nowIso: nowIso,
  );

  _upsertSave(
    db,
    gameDb,
    userId: demoMiraId,
    name: demoMiraName,
    locationId: demoMiraLocationId,
    activityId: demoMiraActivityId,
    appearance: miraLook,
    skillLevels: const <String, num>{demoMiraSkillId: 14, combatSkillId: 8},
    nowMs: nowMs,
    nowIso: nowIso,
  );
  _upsertSave(
    db,
    gameDb,
    userId: demoBramId,
    name: demoBramName,
    locationId: demoBramLocationId,
    appearance: bramLook,
    skillLevels: const <String, num>{demoBramSkillId: 11, combatSkillId: 6},
    nowMs: nowMs,
    nowIso: nowIso,
  );
  _upsertSave(
    db,
    gameDb,
    userId: demoKaelId,
    name: demoKaelName,
    locationId: demoKaelLocationId,
    appearance: kaelLook,
    skillLevels: const <String, num>{demoKaelSkillId: 18},
    nowMs: nowMs,
    nowIso: nowIso,
  );

  final guild = GuildRecord(
    id: demoGuildId,
    name: demoGuildName,
    tag: demoGuildTag,
    description: 'A standing patrol of three. Open to new recruits.',
    emblem: GuildEmblem(color: guildEmblemColors[2], symbol: 'shield'),
    leaderId: demoMiraId,
    joinPolicy: guildJoinOpen,
    rankLabels: <GuildRankKey, String>{...defaultGuildRankLabels},
    createdAt: nowIso,
    guestAutoAccept: true,
  );
  final existingGuild = db.guilds.indexWhere((row) => row.id == demoGuildId);
  if (existingGuild < 0) {
    db.guilds.add(guild);
  } else {
    db.guilds[existingGuild] = guild;
  }

  _upsertMember(
    db,
    guildId: demoGuildId,
    userId: demoMiraId,
    username: demoMiraName,
    role: guildRoleLeader,
    appearance: miraLook,
    totalLevel: 14,
    joinedAt: nowIso,
  );
  _upsertMember(
    db,
    guildId: demoGuildId,
    userId: demoBramId,
    username: demoBramName,
    role: guildRoleOfficer,
    appearance: bramLook,
    totalLevel: 11,
    joinedAt: nowIso,
  );
  _upsertMember(
    db,
    guildId: demoGuildId,
    userId: demoKaelId,
    username: demoKaelName,
    role: guildRoleMember,
    appearance: kaelLook,
    totalLevel: 18,
    joinedAt: nowIso,
  );

  db.profiles = db.profiles
      .map(
        (row) => isDemoPlayerId(row.userId)
            ? row.copyWith(guildId: demoGuildId, guildName: demoGuildName, updatedAt: nowIso)
            : row,
      )
      .toList();

  final expiresAt = isoFromMs(nowMs + const Duration(days: 365).inMilliseconds);
  db.presence = [
    ...db.presence.where((row) => !isDemoPlayerId(row.userId)),
    _presence(
      userId: demoMiraId,
      username: demoMiraName,
      appearance: miraLook,
      locationId: demoMiraLocationId,
      activityId: demoMiraActivityId,
      skillId: demoMiraSkillId,
      skillLevel: 14,
      nowIso: nowIso,
      expiresAt: expiresAt,
    ),
    _presence(
      userId: demoBramId,
      username: demoBramName,
      appearance: bramLook,
      locationId: demoBramLocationId,
      skillId: demoBramSkillId,
      skillLevel: 11,
      nowIso: nowIso,
      expiresAt: expiresAt,
    ),
    _presence(
      userId: demoKaelId,
      username: demoKaelName,
      appearance: kaelLook,
      locationId: demoKaelLocationId,
      skillId: demoKaelSkillId,
      skillLevel: 18,
      nowIso: nowIso,
      expiresAt: expiresAt,
    ),
  ];

  if (!db.halls.any((row) => row.guildId == demoGuildId)) {
    db.halls.add(GuildHallState.fresh(demoGuildId));
  }

  db.messages = [
    ...db.messages.where((row) => !row.id.startsWith('msg_demo_')),
    ChatMessage(
      id: 'msg_demo_mira_global',
      channelKey: 'global',
      userId: demoMiraId,
      username: demoMiraName,
      body: 'The Watch holds the meadow road.',
      createdAt: nowIso,
      guildTag: demoGuildTag,
      rankIcon: guildRankIcon(guildRankIconThemeStripes, guildRoleLeader),
    ),
    ChatMessage(
      id: 'msg_demo_mira_meadow',
      channelKey: 'local:$demoMiraLocationId',
      userId: demoMiraId,
      username: demoMiraName,
      body: 'Plenty of flax this morning.',
      createdAt: nowIso,
      guildTag: demoGuildTag,
      rankIcon: guildRankIcon(guildRankIconThemeStripes, guildRoleLeader),
    ),
  ];
}

void _upsertAccount(
  LocalDb db, {
  required String userId,
  required String username,
  required PlayerAppearance appearance,
  required String nowIso,
}) {
  if (!db.users.any((row) => row.userId == userId)) {
    db.users.add(
      LocalAccount(
        userId: userId,
        email: '$username@demo.idle-kingdoms'.toLowerCase(),
        username: username,
        password: 'demo-not-a-login',
      ),
    );
  }
  final index = db.profiles.indexWhere((row) => row.userId == userId);
  final profile = MultiplayerProfile(
    userId: userId,
    username: username,
    appearance: appearance,
    guildId: demoGuildId,
    guildName: demoGuildName,
    privacyPublicSkills: true,
    updatedAt: nowIso,
  );
  if (index < 0) {
    db.profiles.add(profile);
  } else {
    db.profiles[index] = profile;
  }
}

void _upsertSave(
  LocalDb db,
  GameDatabase gameDb, {
  required String userId,
  required String name,
  required String locationId,
  String? activityId,
  required PlayerAppearance appearance,
  required Map<String, num> skillLevels,
  required num nowMs,
  required String nowIso,
}) {
  var save = createNewSave(gameDb, nowMs).copyWith(characterName: name);
  final assigned = assignRace(gameDb, save, 'RACE-0001');
  save = assigned.save ?? save;
  final skills = save.skills.map((skill) {
    final level = skillLevels[skill.skillId];
    return level == null ? skill : skill.copyWith(level: level);
  }).toList();
  save = save.copyWith(
    appearance: appearance,
    currentLocationId: locationId,
    currentActivityId: activityId,
    skills: skills,
    updatedAt: nowIso,
  );
  db.saves = db.saves.where((row) => row.userId != userId).toList();
  db.saves.add(
    CloudSaveRecord(
      userId: userId,
      saveVersion: save.saveVersion,
      updatedAt: nowIso,
      payload: save,
    ),
  );
}

void _upsertMember(
  LocalDb db, {
  required String guildId,
  required String userId,
  required String username,
  required String role,
  required PlayerAppearance appearance,
  required num totalLevel,
  required String joinedAt,
}) {
  final index = db.members.indexWhere((row) => row.guildId == guildId && row.userId == userId);
  final member = GuildMember(
    guildId: guildId,
    userId: userId,
    username: username,
    role: role,
    joinedAt: joinedAt,
    appearance: appearance,
    totalLevel: totalLevel,
  );
  if (index < 0) {
    db.members.add(member);
  } else {
    db.members[index] = member.copyWith(role: role, username: username, appearance: appearance);
  }
}

ActivityPresence _presence({
  required String userId,
  required String username,
  required PlayerAppearance appearance,
  required String locationId,
  String? activityId,
  required String skillId,
  required num skillLevel,
  required String nowIso,
  required String expiresAt,
}) {
  return ActivityPresence(
    userId: userId,
    username: username,
    appearance: appearance,
    guildName: demoGuildName,
    locationId: locationId,
    currentActivityId: activityId,
    skillId: skillId,
    skillLevel: skillLevel,
    outfitCosmeticId: null,
    mountCosmeticId: null,
    updatedAt: nowIso,
    expiresAt: expiresAt,
  );
}
