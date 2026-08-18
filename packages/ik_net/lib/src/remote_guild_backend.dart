/// Guilds, answered by the server.
///
/// The local backend is still the reference for what a guild *means* — who may
/// promote whom, when a hall tier is paid for, what a full guild is — and this
/// enforces the same rules against rows instead of a document on one device.
/// Where the two must differ they say so: a race for a name is settled by the
/// database, not by reading the table first.
library;

import 'package:ik_rules/ik_rules.dart';

import 'guild_rules.dart';
import 'remote.dart';
import 'remote_guilds.dart';
import 'remote_transport.dart';
import 'results.dart';
import 'types.dart';

/// What this player is listed as on a roster.
class GuildMemberFacts {
  const GuildMemberFacts({
    required this.username,
    required this.appearance,
    required this.totalLevel,
  });

  final String username;
  final PlayerAppearance appearance;
  final num totalLevel;
}

/// The facts a save is worth, which is what a roster row shows.
GuildMemberFacts guildMemberFactsFrom(MultiplayerSession session, PlayerSave? save) {
  final named = save?.characterName?.trim();
  return GuildMemberFacts(
    username: named != null && named.isNotEmpty ? named : session.username,
    appearance: save?.appearance ?? defaultPlayerAppearance,
    totalLevel: save == null ? 1 : totalLevel(save),
  );
}

class RemoteGuildBackend {
  RemoteGuildBackend({
    required this.transport,
    required this.sessionOf,
    required this.factsOf,
    required this.nowIso,
  });

  final RemoteTransport transport;

  /// Who is asking. Null when nobody is signed in, which every call refuses on.
  final MultiplayerSession? Function() sessionOf;

  /// This player's roster facts, read when a row about them is written.
  final Future<GuildMemberFacts> Function() factsOf;

  final String Function() nowIso;

  // --- Reads ----------------------------------------------------------------

  Future<List<GuildRecord>> _guildRows({String? guildId}) async {
    final result = await transport.select(
      RemoteTables.guilds,
      columns: remoteGuildColumns,
      equals: guildId == null ? const <String, Object?>{} : <String, Object?>{'id': guildId},
      orderBy: 'name',
    );
    if (!result.ok) return const <GuildRecord>[];
    return result.rows!.map(guildRecordFrom).toList();
  }

  Future<GuildRecord?> guildById(String guildId) async {
    final rows = await _guildRows(guildId: guildId);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<GuildListing>> listGuilds() async {
    final guilds = await _guildRows();
    if (guilds.isEmpty) return const <GuildListing>[];
    // One read for every roster row rather than a count per guild, because this
    // transport speaks in rows and a browse list is short.
    final members = await transport.select(RemoteTables.guildMembers, columns: 'guild_id');
    final counts = <String, int>{};
    for (final row in members.rows ?? const <RemoteRow>[]) {
      final id = row['guild_id'];
      if (id is! String) continue;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return guilds
        .map((guild) => GuildListing(guild: guild, memberCount: counts[guild.id] ?? 0))
        .toList();
  }

  Future<List<GuildMember>> guildMembers(String guildId) async {
    final result = await transport.select(
      RemoteTables.guildMembers,
      columns: remoteGuildMemberColumns,
      equals: <String, Object?>{'guild_id': guildId},
      orderBy: 'joined_at',
    );
    if (!result.ok) return const <GuildMember>[];
    return guildMembersFrom(result.rows!);
  }

  /// The roster row for [userId], or null when they are in no guild.
  Future<GuildMember?> _membershipOf(String userId) async {
    final result = await transport.select(
      RemoteTables.guildMembers,
      columns: remoteGuildMemberColumns,
      equals: <String, Object?>{'user_id': userId},
      limit: 1,
    );
    if (!result.ok || result.single == null) return null;
    return guildMemberFrom(result.single!);
  }

  Future<String?> currentGuildId() async {
    final current = sessionOf();
    if (current == null) return null;
    final membership = await _membershipOf(current.userId);
    return membership?.guildId;
  }

  Future<GuildGuest?> _guestOf(String userId) async {
    final result = await transport.select(
      RemoteTables.guildGuests,
      columns: remoteGuildGuestColumns,
      equals: <String, Object?>{'user_id': userId},
      limit: 1,
    );
    if (!result.ok || result.single == null) return null;
    return guildGuestFrom(result.single!);
  }

  Future<String?> currentGuestGuildId() async {
    final current = sessionOf();
    if (current == null) return null;
    return (await _guestOf(current.userId))?.guildId;
  }

  Future<List<GuildApplication>> guildApplications(String guildId) async {
    final result = await transport.select(
      RemoteTables.guildApplications,
      columns: remoteGuildApplicationColumns,
      equals: <String, Object?>{'guild_id': guildId},
      orderBy: 'created_at',
    );
    if (!result.ok) return const <GuildApplication>[];
    return result.rows!.map(guildApplicationFrom).toList();
  }

  Future<int> _memberCount(String guildId) async {
    final result = await transport.select(
      RemoteTables.guildMembers,
      columns: 'user_id',
      equals: <String, Object?>{'guild_id': guildId},
    );
    return (result.rows ?? const <RemoteRow>[]).length;
  }

  // --- Joining and leaving --------------------------------------------------

  Future<CreateGuildResult> createGuild(CreateGuildInput input, num goldAvailable) async {
    final current = sessionOf();
    if (current == null) return const CreateGuildResult.failed('Sign in to create a guild.');

    final refusal = createGuildRefusal(input, goldAvailable);
    if (refusal != null) return CreateGuildResult.failed(refusal);
    if (await _membershipOf(current.userId) != null) {
      return const CreateGuildResult.failed('Leave your current guild before creating another.');
    }

    final wanted = guildFromCreateInput(current.userId, input, nowIso());
    final written = await transport.insert(
      RemoteTables.guilds,
      guildRowForCreate(current.userId, wanted),
      columns: remoteGuildColumns,
    );
    if (!written.ok) {
      return CreateGuildResult.failed(
        isDuplicateRefusal(written.reason!) ? remoteGuildNameTaken : written.reason!,
      );
    }
    final row = written.single;
    if (row == null) return const CreateGuildResult.failed(remoteGuildCreateFailed);
    final guild = guildRecordFrom(row);

    final facts = await factsOf();
    final seated = await transport.insert(
      RemoteTables.guildMembers,
      guildMemberRowFor(
        GuildMember(
          guildId: guild.id,
          userId: current.userId,
          username: facts.username,
          role: guildRoleLeader,
          joinedAt: nowIso(),
          appearance: facts.appearance,
          totalLevel: facts.totalLevel,
        ),
      ),
      columns: remoteGuildMemberColumns,
    );
    if (!seated.ok) return CreateGuildResult.failed(seated.reason!);

    await _noteOwnGuild(current.userId, guild.id);
    await transport.upsert(RemoteTables.guildHalls, <RemoteRow>[
      guildHallRowFor(GuildHallState.fresh(guild.id)),
    ]);
    await _seedGuildGoals(guild.id);
    return CreateGuildResult.ok(guild, guildCreateGoldCost);
  }

  Future<ApplyToGuildResult> applyToGuild(String guildId, String message) async {
    final current = sessionOf();
    if (current == null) return const ApplyToGuildResult.failed('Sign in to join a guild.');
    final guild = await guildById(guildId);
    if (guild == null) return const ApplyToGuildResult.failed(remoteGuildMissing);
    if (await _membershipOf(current.userId) != null) {
      return const ApplyToGuildResult.failed('Already in a guild.');
    }
    if (await _memberCount(guildId) >= guildMaxMembers) {
      return ApplyToGuildResult.failed('That guild is full ($guildMaxMembers members).');
    }

    if (guild.joinPolicy == guildJoinOpen) {
      final facts = await factsOf();
      final seated = await transport.insert(
        RemoteTables.guildMembers,
        guildMemberRowFor(
          GuildMember(
            guildId: guildId,
            userId: current.userId,
            username: facts.username,
            role: guildRoleRecruit,
            joinedAt: nowIso(),
            appearance: facts.appearance,
            totalLevel: facts.totalLevel,
          ),
        ),
        columns: remoteGuildMemberColumns,
      );
      if (!seated.ok) return ApplyToGuildResult.failed(seated.reason!);
      await _clearRequests(guildId, current.userId);
      await _noteOwnGuild(current.userId, guildId);
      return const ApplyToGuildResult.ok(joined: true);
    }

    final asked = await transport.insert(
      RemoteTables.guildApplications,
      guildApplicationRowFor(
        guildId: guildId,
        userId: current.userId,
        username: current.username,
        message: guildApplicationMessage(message),
        guest: false,
      ),
      columns: remoteGuildApplicationColumns,
    );
    if (!asked.ok) {
      return ApplyToGuildResult.failed(
        isDuplicateRefusal(asked.reason!) ? 'Application already pending.' : asked.reason!,
      );
    }
    return const ApplyToGuildResult.ok(joined: false);
  }

  Future<ApplyToGuildResult> joinAsGuest(String guildId, String message) async {
    final current = sessionOf();
    if (current == null) return const ApplyToGuildResult.failed('Sign in to visit a guild.');
    final guild = await guildById(guildId);
    if (guild == null) return const ApplyToGuildResult.failed(remoteGuildMissing);
    final membership = await _membershipOf(current.userId);
    if (membership?.guildId == guildId) {
      return const ApplyToGuildResult.failed('Already a member of that guild.');
    }
    final guest = await _guestOf(current.userId);
    if (guest != null) {
      return ApplyToGuildResult.failed(
        guest.guildId == guildId
            ? 'Already a guest of that guild.'
            : 'Leave your current guest guild first.',
      );
    }

    if (guild.guestAutoAccept) {
      final facts = await factsOf();
      final seated = await transport.insert(
        RemoteTables.guildGuests,
        guildGuestRowFor(
          GuildGuest(
            guildId: guildId,
            userId: current.userId,
            username: facts.username,
            joinedAt: nowIso(),
            appearance: facts.appearance,
          ),
        ),
        columns: remoteGuildGuestColumns,
      );
      if (!seated.ok) return ApplyToGuildResult.failed(seated.reason!);
      await _clearRequests(guildId, current.userId, guest: true);
      return const ApplyToGuildResult.ok(joined: true);
    }

    final asked = await transport.insert(
      RemoteTables.guildApplications,
      guildApplicationRowFor(
        guildId: guildId,
        userId: current.userId,
        username: current.username,
        message: guildApplicationMessage(message),
        guest: true,
      ),
      columns: remoteGuildApplicationColumns,
    );
    if (!asked.ok) {
      return ApplyToGuildResult.failed(
        isDuplicateRefusal(asked.reason!) ? 'Guest request already pending.' : asked.reason!,
      );
    }
    return const ApplyToGuildResult.ok(joined: false);
  }

  Future<ActionResult> leaveGuest() async {
    final current = sessionOf();
    if (current == null) return const ActionResult.failed('Sign in first.');
    if (await _guestOf(current.userId) == null) {
      return const ActionResult.failed('Not a guest of a guild.');
    }
    final refused = await transport.delete(
      RemoteTables.guildGuests,
      equals: <String, Object?>{'user_id': current.userId},
    );
    return refused == null ? const ActionResult.ok() : ActionResult.failed(refused);
  }

  Future<ActionResult> leaveGuild() async {
    final current = sessionOf();
    if (current == null) return const ActionResult.failed('Sign in first.');
    final membership = await _membershipOf(current.userId);
    if (membership == null) return const ActionResult.failed('Not in a guild.');
    final guild = await guildById(membership.guildId);

    if (guild != null && guild.leaderId == current.userId) {
      if (await _memberCount(guild.id) > 1) {
        return const ActionResult.failed('Transfer leadership or remove members before leaving.');
      }
      // Everything hanging off the guild goes with it: the roster, the requests,
      // the guests, the hall, the projects. That is what the cascades are for.
      final refused = await transport.delete(
        RemoteTables.guilds,
        equals: <String, Object?>{'id': guild.id},
      );
      if (refused != null) return ActionResult.failed(refused);
      await _noteOwnGuild(current.userId, null);
      return const ActionResult.ok();
    }

    final refused = await transport.delete(
      RemoteTables.guildMembers,
      equals: <String, Object?>{'user_id': current.userId},
    );
    if (refused != null) return ActionResult.failed(refused);
    await _noteOwnGuild(current.userId, null);
    return const ActionResult.ok();
  }

  Future<ActionResult> decideGuildApplication(String applicationId, bool accept) async {
    final current = sessionOf();
    if (current == null) return const ActionResult.failed('Sign in first.');
    final found = await transport.select(
      RemoteTables.guildApplications,
      columns: remoteGuildApplicationColumns,
      equals: <String, Object?>{'id': applicationId},
      limit: 1,
    );
    final row = found.single;
    if (row == null) return const ActionResult.failed('Application not found.');
    final application = guildApplicationFrom(row);
    final guild = await guildById(application.guildId);
    if (guild == null || guild.leaderId != current.userId) {
      return const ActionResult.failed('Only the guild leader can decide applications.');
    }

    Future<ActionResult> drop() async {
      final refused = await transport.delete(
        RemoteTables.guildApplications,
        equals: <String, Object?>{'id': applicationId},
      );
      return refused == null ? const ActionResult.ok() : ActionResult.failed(refused);
    }

    if (!accept) return drop();

    final applicantIsMember = (await _membershipOf(application.userId))?.guildId;
    if (application.guest) {
      if (await _guestOf(application.userId) != null) {
        await drop();
        return const ActionResult.failed('Applicant is already a guest elsewhere.');
      }
      if (applicantIsMember == guild.id) {
        await drop();
        return const ActionResult.failed('Applicant already joined that guild.');
      }
      final seated = await transport.insert(
        RemoteTables.guildGuests,
        guildGuestRowFor(
          GuildGuest(
            guildId: guild.id,
            userId: application.userId,
            username: application.username,
            joinedAt: nowIso(),
            appearance: defaultPlayerAppearance,
          ),
        ),
        columns: remoteGuildGuestColumns,
      );
      if (!seated.ok) return ActionResult.failed(seated.reason!);
      return drop();
    }

    if (applicantIsMember != null) {
      await drop();
      return const ActionResult.failed('Applicant already joined another guild.');
    }
    if (await _memberCount(guild.id) >= guildMaxMembers) {
      await drop();
      return ActionResult.failed('Guild is full ($guildMaxMembers members).');
    }
    final seated = await transport.insert(
      RemoteTables.guildMembers,
      guildMemberRowFor(
        GuildMember(
          guildId: guild.id,
          userId: application.userId,
          username: application.username,
          role: guildRoleRecruit,
          joinedAt: nowIso(),
          // The applicant's own client fills in their look and level with its
          // next ranking update; a leader cannot read another player's save.
          appearance: defaultPlayerAppearance,
          totalLevel: 1,
        ),
      ),
      columns: remoteGuildMemberColumns,
    );
    if (!seated.ok) return ActionResult.failed(seated.reason!);
    await transport.delete(
      RemoteTables.guildGuests,
      equals: <String, Object?>{'guild_id': guild.id, 'user_id': application.userId},
    );
    return drop();
  }

  // --- Ranks and settings ---------------------------------------------------

  Future<ActionResult> setGuildMemberRole(
    String guildId,
    String targetUserId,
    GuildRole role,
  ) async {
    final current = sessionOf();
    if (current == null) return const ActionResult.failed('Sign in first.');
    final guild = await guildById(guildId);
    if (guild == null || guild.leaderId != current.userId) {
      return const ActionResult.failed('Only the leader can change roles.');
    }
    final refusal = memberRoleRefusal(guild, targetUserId, role);
    if (refusal != null) return ActionResult.failed(refusal);
    final refused = await transport.update(
      RemoteTables.guildMembers,
      <String, Object?>{'role': role},
      equals: <String, Object?>{'guild_id': guildId, 'user_id': targetUserId},
    );
    return refused == null ? const ActionResult.ok() : ActionResult.failed(refused);
  }

  /// Writes one guild setting, which only its leader may do.
  Future<ActionResult> _setGuildColumn(
    String guildId,
    RemoteRow row, {
    required String refusal,
  }) async {
    final current = sessionOf();
    if (current == null) return const ActionResult.failed('Sign in first.');
    final guild = await guildById(guildId);
    if (guild == null || guild.leaderId != current.userId) {
      return ActionResult.failed(refusal);
    }
    final refused = await transport.update(
      RemoteTables.guilds,
      row,
      equals: <String, Object?>{'id': guildId},
    );
    return refused == null ? const ActionResult.ok() : ActionResult.failed(refused);
  }

  Future<ActionResult> setGuildJoinPolicy(String guildId, GuildJoinPolicy joinPolicy) =>
      _setGuildColumn(
        guildId,
        <String, Object?>{'join_policy': joinPolicy},
        refusal: 'Only the leader can change join settings.',
      );

  Future<ActionResult> setGuildGuestAutoAccept(String guildId, bool guestAutoAccept) =>
      _setGuildColumn(
        guildId,
        <String, Object?>{'guest_auto_accept': guestAutoAccept},
        refusal: 'Only the leader can change join settings.',
      );

  Future<ActionResult> setGuildRankIconTheme(String guildId, String theme) => _setGuildColumn(
    guildId,
    <String, Object?>{'rank_icon_theme': normalizeRankIconTheme(theme)},
    refusal: 'Only the leader can change rank icons.',
  );

  Future<ActionResult> setGuildRankLabels(
    String guildId,
    Map<GuildRankKey, String> rankLabels,
  ) async {
    final guild = await guildById(guildId);
    return _setGuildColumn(
      guildId,
      <String, Object?>{
        'rank_labels': normalizeRankLabels(<String, Object?>{
          ...?guild?.rankLabels,
          ...rankLabels,
        }),
      },
      refusal: 'Only the leader can rename ranks.',
    );
  }

  Future<ActionResult> setGuildEmblem(String guildId, GuildEmblem emblem) => _setGuildColumn(
    guildId,
    <String, Object?>{'emblem': normalizeEmblem(emblem).toJson()},
    refusal: 'Only the leader can edit the banner.',
  );

  // --- Projects and challenges ----------------------------------------------

  Future<List<GuildProject>> guildProjects(String guildId) async {
    final result = await transport.select(
      RemoteTables.guildProjects,
      columns: remoteGuildProjectColumns,
      equals: <String, Object?>{'guild_id': guildId},
    );
    if (!result.ok) return const <GuildProject>[];
    return result.rows!.map(guildProjectFrom).toList();
  }

  Future<List<GuildChallenge>> guildChallenges(String guildId) async {
    final result = await transport.select(
      RemoteTables.guildChallenges,
      columns: remoteGuildChallengeColumns,
      equals: <String, Object?>{'guild_id': guildId},
    );
    if (!result.ok) return const <GuildChallenge>[];
    return result.rows!.map(guildChallengeFrom).toList();
  }

  Future<ContributeProjectResult> contributeGuildProject(String projectId, num amount) async {
    final current = sessionOf();
    if (current == null) return const ContributeProjectResult.failed('Sign in first.');
    final membership = await _membershipOf(current.userId);
    if (membership == null) return const ContributeProjectResult.failed('Join a guild first.');
    final found = await transport.select(
      RemoteTables.guildProjects,
      columns: remoteGuildProjectColumns,
      equals: <String, Object?>{'id': projectId},
      limit: 1,
    );
    final row = found.single;
    if (row == null) return const ContributeProjectResult.failed('Project not found.');
    final project = guildProjectFrom(row);
    if (project.guildId != membership.guildId) {
      return const ContributeProjectResult.failed('Project not found.');
    }
    final next = contributedProject(project, amount);
    final refused = await transport.update(
      RemoteTables.guildProjects,
      <String, Object?>{'contributed': next.contributed},
      equals: <String, Object?>{'id': projectId},
    );
    if (refused != null) return ContributeProjectResult.failed(refused);
    return ContributeProjectResult.ok(next);
  }

  // --- The hall -------------------------------------------------------------

  Future<GuildHallState?> guildHall(String guildId) async {
    if (await guildById(guildId) == null) return null;
    final result = await transport.select(
      RemoteTables.guildHalls,
      columns: remoteGuildHallColumns,
      equals: <String, Object?>{'guild_id': guildId},
      limit: 1,
    );
    final row = result.single;
    // A guild made before the hall table, or one whose row was never written,
    // has a hall that has simply had nothing done to it yet.
    return row == null ? GuildHallState.fresh(guildId) : guildHallFrom(row);
  }

  Future<GuildHallActionResult> payGuildDebt(PlayerSave save, num amount) async {
    final current = sessionOf();
    if (current == null) return const GuildHallActionResult.failed('Sign in first.');
    final membership = await _membershipOf(current.userId);
    if (membership == null) return const GuildHallActionResult.failed('Join a guild first.');
    if (!canPayGuildDebt(membership.role)) {
      return const GuildHallActionResult.failed('Recruits cannot pay the hall debt.');
    }
    final hall = await guildHall(membership.guildId);
    if (hall == null) return const GuildHallActionResult.failed(remoteGuildMissing);

    final paid = payGuildHallDebt(hall, current.userId, save, amount);
    if (!paid.ok) return paid;
    final refused = await transport.upsert(RemoteTables.guildHalls, <RemoteRow>[
      guildHallRowFor(paid.hall!),
    ]);
    if (refused != null) return GuildHallActionResult.failed(refused);
    return paid;
  }

  Future<GuildHallActionResult> contributeHallItem(
    PlayerSave save,
    int inventoryIndex,
    num quantity,
  ) async {
    final current = sessionOf();
    if (current == null) return const GuildHallActionResult.failed('Sign in first.');
    final membership = await _membershipOf(current.userId);
    if (membership == null) return const GuildHallActionResult.failed('Join a guild first.');
    final hall = await guildHall(membership.guildId);
    if (hall == null) return const GuildHallActionResult.failed(remoteGuildMissing);

    final given = donateToGuildHall(hall, save, inventoryIndex, quantity);
    if (!given.ok) return given;
    final refused = await transport.upsert(RemoteTables.guildHalls, <RemoteRow>[
      guildHallRowFor(given.hall!),
    ]);
    if (refused != null) return GuildHallActionResult.failed(refused);
    return given;
  }

  // --- Keeping this player's own rows current -------------------------------

  /// Records the guild on this player's profile, which is what a leaderboard
  /// row joins to for a guild name.
  Future<void> _noteOwnGuild(String userId, String? guildId) async {
    await transport.update(
      RemoteTables.profiles,
      <String, Object?>{'guild_id': guildId, 'updated_at': nowIso()},
      equals: <String, Object?>{'user_id': userId},
    );
  }

  /// The first project and challenge a new guild has, matching the offline one.
  Future<void> _seedGuildGoals(String guildId) async {
    await transport.insert(
      RemoteTables.guildProjects,
      guildProjectRowFor(
        GuildProject(
          id: '',
          guildId: guildId,
          name: guildStorehouseProjectName,
          description: guildStorehouseProjectDescription,
          goalAmount: guildStorehouseProjectGoal,
          contributed: 0,
          rewardLabel: guildStorehouseProjectReward,
        ),
      ),
      columns: remoteGuildProjectColumns,
    );
    await transport.insert(
      RemoteTables.guildChallenges,
      guildChallengeRowFor(
        GuildChallenge(
          id: '',
          guildId: guildId,
          name: guildMonsterChallengeName,
          boardKey: boardMonstersKilled,
          goalValue: guildMonsterChallengeGoal,
          currentValue: 0,
        ),
      ),
      columns: remoteGuildChallengeColumns,
    );
  }

  Future<void> _clearRequests(String guildId, String userId, {bool? guest}) async {
    await transport.delete(
      RemoteTables.guildApplications,
      equals: <String, Object?>{
        'guild_id': guildId,
        'user_id': userId,
        'guest': ?guest,
      },
    );
    if (guest == true) return;
    await transport.delete(
      RemoteTables.guildGuests,
      equals: <String, Object?>{'guild_id': guildId, 'user_id': userId},
    );
  }

  /// Refreshes this player's own roster row from [save].
  ///
  /// A roster carries each member's name, look, and level so it can be read in
  /// one query, which means every member keeps their own row honest. This runs
  /// with the ranking update, so a roster is as current as the boards are.
  Future<void> refreshOwnMemberRow(String guildId, MultiplayerSession session, PlayerSave save) {
    final facts = guildMemberFactsFrom(session, save);
    return transport.update(
      RemoteTables.guildMembers,
      <String, Object?>{
        'username': facts.username,
        'appearance_json': facts.appearance.toJson(),
        'total_level': facts.totalLevel,
      },
      equals: <String, Object?>{'guild_id': guildId, 'user_id': session.userId},
    );
  }
}
