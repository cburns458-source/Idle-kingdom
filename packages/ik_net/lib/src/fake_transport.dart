import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'cloud_save.dart';
import 'fake_exchange.dart';
import 'guild_rules.dart';
import 'market.dart';
import 'remote.dart';
import 'remote_guilds.dart';
import 'remote_transport.dart';
import 'results.dart';
import 'service.dart';
import 'snapshots.dart';
import 'types.dart';

/// Writes a hosted save the way the game function would, then loads its version.
Future<CloudSyncResult> seedHostedSave(
  MultiplayerService service,
  FakeTransport transport,
  PlayerSave save,
) async {
  final userId = service.session?.userId;
  if (userId == null) return const CloudSyncResult.failed('Sign in required.');
  final refused = await transport.upsert(RemoteTables.saves, <RemoteRow>[
    <String, Object?>{
      ...saveRowFor(userId, save, playSessionId: service.session?.playSessionId),
      'version': 1,
      'rng_state': 1,
    },
  ]);
  if (refused != null) return CloudSyncResult.failed(refused);
  return service.pullSave();
}

/// A remote backend held in memory, standing in for the hosted one.
///
/// It is deliberately literal about the parts the service depends on — upserts
/// that replace on a conflict key, reads that filter and order, and a join from
/// a leaderboard row to its profile — because those are the assumptions that
/// would otherwise only be checked against a live project.
class FakeTransport implements RemoteTransport {
  FakeTransport({this.startIso = '2026-08-13T00:00:00.000Z', this.nowMs, this.database})
    : _project = _FakeProject();

  /// A second client on the project [other] is already connected to.
  ///
  /// The tables, the accounts, and the exchange are shared; who is signed in is
  /// not. That is what lets two players meet on one order book, which is the
  /// only way a market can be tested at all — a hosted project has many clients
  /// and one set of tables, and a single transport can only be one client.
  FakeTransport.joining(FakeTransport other)
    : startIso = other.startIso,
      nowMs = other.nowMs,
      database = other.database,
      _project = other._project;

  /// The instant the first stamped row is written at.
  final String startIso;

  /// Optional authoritative clock for [serverNowMs], matching a hosted now().
  final num Function()? nowMs;

  /// When set, [create_character] builds a real starting save.
  GameDatabase? database;

  /// When true, [signUp] creates the account and returns no session, matching a
  /// hosted project that still has Confirm email on.
  bool omitSignUpSession = false;

  /// When true, `game` is missing the way a live project is before ship.
  bool missingGameFunction = false;

  final _FakeProject _project;

  /// A fresh timestamp, a second later each time.
  ///
  /// Rows a real table stamps for itself are microseconds apart, which is what
  /// makes `order by created_at` mean anything; identical stamps would leave the
  /// order of a board undefined and a test passing by luck.
  String stamp() {
    final at = DateTime.parse(startIso).add(Duration(seconds: _project.stamps++));
    return at.toUtc().toIso8601String();
  }

  Map<String, List<RemoteRow>> get tables => _project.tables;

  /// Accounts by email, as an auth provider would hold them.
  Map<String, FakeAccount> get accounts => _project.accounts;

  /// Records an account the provider already knows.
  ///
  /// [username] is absent for one made outside the game, which is the case that
  /// leaves the session to name the player from their email.
  void seedAccount({
    required String email,
    String? username,
    String password = 'secret',
    String? userId,
  }) {
    final key = email.trim().toLowerCase();
    accounts[key] = FakeAccount(
      userId: userId ?? _nextId('usr'),
      email: key,
      password: password,
      username: username,
    );
  }

  /// Every call made, so a test can assert what went over the wire.
  List<String> get calls => _project.calls;

  /// Emails a magic link was requested for.
  List<String> get magicLinks => _project.magicLinks;

  /// The reason the next call of any kind should fail with, used once.
  String? failNextWith;

  /// False stands in for a project without the Wave E guild functions, so the
  /// client's older direct-write path can still be exercised.
  bool get hostsGuildLifecycleRpcs => _project.hostsGuildLifecycleRpcs;
  set hostsGuildLifecycleRpcs(bool value) => _project.hostsGuildLifecycleRpcs = value;

  /// How many times [failNextWith] applies before it clears. Defaults to one.
  int failNextRepeats = 1;

  /// Reasons keyed by the call they refuse, such as `insert:guild_members`, each
  /// used once. For making one step of a sequence fail rather than the next one.
  Map<String, String> get failOnce => _project.failOnce;

  /// Columns this stand-in pretends the project has not got, as a skipped
  /// migration would. A select or upsert that names one of them is refused.
  Set<String> get missingColumns => _project.missingColumns;

  /// Tables this stand-in pretends the project has not got, as a skipped
  /// migration would.
  Set<String> get missingTables => _project.missingTables;

  /// Every select's column list, so a test can see a retry drop missing ones.
  List<String> get selectedColumns => _project.selectedColumns;

  int _inFlight = 0;

  /// Peak overlapping calls on this client. Sequential reads stay at 1.
  int maxInFlight = 0;

  Future<T> _track<T>(Future<T> Function() run) async {
    _inFlight += 1;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    try {
      return await run();
    } finally {
      _inFlight -= 1;
    }
  }

  /// Every select `like` filter, as `table.column=pattern`.
  List<String> get selectedLikes => _project.selectedLikes;

  /// Set to answer the send-chat function with something unusable.
  RemoteRow? chatFunctionReply;

  /// The Bazaar exchange, which is a function call rather than a set of tables
  /// because its tables are closed to clients.
  FakeExchange get exchange => _project.exchange ??= FakeExchange(
    saves: tables[RemoteTables.saves]!,
    stamp: stamp,
    database: () => database,
  );

  bool signedOut = false;
  FakeAccount? _current;

  String _nextId(String prefix) => '${prefix}_${(_project.ids += 1).toString().padLeft(4, '0')}';

  String? _takeFailure(String call) {
    final named = failOnce.remove(call);
    if (named != null) return named;
    final reason = failNextWith;
    if (reason == null) return null;
    failNextRepeats -= 1;
    if (failNextRepeats <= 0) {
      failNextWith = null;
      failNextRepeats = 1;
    }
    return reason;
  }

  /// The PostgREST line a missing column produces, so a retry can match it.
  String? _missingColumnRefusal(String table, String named) {
    final asked = named.split(',').map((part) => part.trim()).toSet();
    for (final column in missingColumns) {
      if (asked.contains(column)) return 'column $table.$column does not exist';
    }
    return null;
  }

  /// The PostgREST line a missing table produces.
  String? _missingTableRefusal(String table) {
    if (!missingTables.contains(table)) return null;
    return 'Could not find the table \'public.$table\' in the schema cache';
  }

  /// Which columns make a row the same row, so an upsert replaces it.
  static const Map<String, List<String>> _keys = <String, List<String>>{
    RemoteTables.profiles: <String>['user_id'],
    RemoteTables.saves: <String>['user_id'],
    RemoteTables.leaderboard: <String>['user_id', 'board_key'],
    RemoteTables.chat: <String>['id'],
    RemoteTables.bountyClaims: <String>['hour_key', 'bounty_id'],
    RemoteTables.guilds: <String>['id'],
    RemoteTables.guildMembers: <String>['guild_id', 'user_id'],
    RemoteTables.guildApplications: <String>['guild_id', 'user_id'],
    RemoteTables.guildGuests: <String>['guild_id', 'user_id'],
    RemoteTables.guildHalls: <String>['guild_id'],
    RemoteTables.guildAchievements: <String>['guild_id', 'achievement_id'],
    RemoteTables.guildLogEntries: <String>['id'],
    RemoteTables.guildProjects: <String>['id'],
    RemoteTables.guildChallenges: <String>['id'],
    RemoteTables.guildPrivateMessages: <String>['guild_id'],
    RemoteTables.activityPresence: <String>['user_id'],
    RemoteTables.friendRequests: <String>['from_user_id', 'to_user_id'],
    RemoteTables.friendships: <String>['user_a', 'user_b'],
    RemoteTables.pvpSnapshots: <String>['user_id'],
    RemoteTables.rankedPvpResults: <String>['user_id', 'fight_id'],
  };

  /// Columns a table holds unique beyond its key, so an insert can lose a race.
  static const Map<String, List<String>> _unique = <String, List<String>>{
    RemoteTables.guilds: <String>['name', 'tag'],
  };

  /// The columns a table fills in for itself, the way a default does.
  RemoteRow _defaults(String table) => switch (table) {
    RemoteTables.bountyClaims => <String, Object?>{'claimed_at': stamp()},
    RemoteTables.guilds => <String, Object?>{
      'id': _nextId('gld'),
      'created_at': stamp(),
      'permissions': defaultGuildPermissionTable().toJson(),
      'banner': defaultGuildBanner.toJson(),
    },
    RemoteTables.guildAchievements => <String, Object?>{'unlocked_at': stamp()},
    RemoteTables.guildLogEntries => <String, Object?>{'id': _nextId('glg'), 'created_at': stamp()},
    RemoteTables.guildMembers => <String, Object?>{'joined_at': stamp()},
    RemoteTables.guildApplications => <String, Object?>{
      'id': _nextId('app'),
      'created_at': stamp(),
    },
    RemoteTables.guildGuests => <String, Object?>{'joined_at': stamp()},
    RemoteTables.guildProjects => <String, Object?>{'id': _nextId('gprj')},
    RemoteTables.guildChallenges => <String, Object?>{'id': _nextId('gch')},
    RemoteTables.friendRequests => <String, Object?>{'created_at': stamp()},
    RemoteTables.friendships => <String, Object?>{'created_at': stamp()},
    _ => const <String, Object?>{},
  };

  @override
  Future<RemoteAuthResult> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    calls.add('signUp:$email');
    final key = email.trim().toLowerCase();
    if (accounts.containsKey(key)) {
      return const RemoteAuthResult.failed('An account with that email already exists.');
    }
    final account = FakeAccount(
      userId: _nextId('usr'),
      email: key,
      password: password,
      username: username,
    );
    accounts[key] = account;
    if (omitSignUpSession) {
      _current = null;
      signedOut = true;
      return RemoteAuthResult.ok(
        RemoteAccount(userId: account.userId, email: account.email, username: account.username),
      );
    }
    _current = account;
    signedOut = false;
    return RemoteAuthResult.ok(
      RemoteAccount(
        userId: account.userId,
        email: account.email,
        username: account.username,
        accessToken: 'token_${account.userId}',
      ),
    );
  }

  @override
  Future<RemoteAuthResult> signIn({required String email, required String password}) async {
    calls.add('signIn:$email');
    final account = accounts[email.trim().toLowerCase()];
    if (account == null || account.password != password) {
      return const RemoteAuthResult.failed('Invalid login credentials.');
    }
    _current = account;
    signedOut = false;
    return RemoteAuthResult.ok(
      RemoteAccount(
        userId: account.userId,
        email: account.email,
        username: account.username,
        accessToken: 'token_${account.userId}',
      ),
    );
  }

  @override
  Future<String?> updateAuthUsername(String username) async {
    calls.add('updateAuthUsername:$username');
    final account = _current;
    if (account == null) return 'Sign in required.';
    account.username = username;
    return null;
  }

  @override
  Future<String?> sendMagicLink(String email) async {
    calls.add('magicLink:$email');
    final reason = _takeFailure('magicLink:$email');
    if (reason != null) return reason;
    magicLinks.add(email);
    return null;
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    _current = null;
    signedOut = true;
  }

  @override
  Future<String?> refreshSession() async {
    calls.add('refreshSession');
    final reason = _takeFailure('refreshSession');
    return reason == null ? null : friendlyRemoteError(reason);
  }

  @override
  Future<RemoteQueryResult> select(
    String table, {
    required String columns,
    Map<String, Object?> equals = const <String, Object?>{},
    Map<String, String> like = const <String, String>{},
    String? orderBy,
    bool ascending = true,
    int? limit,
  }) {
    return _track(() async {
      calls.add('select:$table');
      selectedColumns.add(columns);
      for (final entry in like.entries) {
        selectedLikes.add('$table.${entry.key}=${entry.value}');
      }
      final reason = _takeFailure('select:$table');
      if (reason != null) return RemoteQueryResult.failed(reason);
      final missingTable = _missingTableRefusal(table);
      if (missingTable != null) return RemoteQueryResult.failed(missingTable);
      final missing = _missingColumnRefusal(table, columns);
      if (missing != null) return RemoteQueryResult.failed(missing);

      final storedTable = table == RemoteTables.leaderboardEntries
          ? RemoteTables.leaderboard
          : table == RemoteTables.publicProfiles
          ? RemoteTables.profiles
          : table == RemoteTables.guildHallTiers
          ? RemoteTables.guildHalls
          : table;
      var rows = (tables[storedTable] ?? const <RemoteRow>[])
          .where((row) => equals.entries.every((filter) => row[filter.key] == filter.value))
          .where(
            (row) => like.entries.every((filter) => _matchesLike(row[filter.key], filter.value)),
          )
          .map((row) => <String, Object?>{...row})
          .toList();

      if (table == RemoteTables.publicProfiles) {
        rows = [for (final row in rows) _publicProfileRow(row)];
      }
      if (table == RemoteTables.guildPrivateMessages) {
        final me = _current?.userId;
        final membership = me == null ? null : _membershipFor(me);
        rows = [
          for (final row in rows)
            if (membership != null && membership['guild_id'] == row['guild_id']) row,
        ];
      }
      if (table == RemoteTables.guildHallTiers) {
        rows = [
          for (final row in rows)
            <String, Object?>{
              'guild_id': row['guild_id'],
              'completed_tiers': row['completed_tiers'] ?? const <Object?>[],
              'debt_paid_off': row['debt_paid_off'] == true,
            },
        ];
      }

      if (columns.contains('profiles')) {
        for (final row in rows) {
          row['profiles'] = _profileJoin(row['user_id']);
        }
      }
      if (orderBy != null) {
        rows.sort((a, b) => _compare(a[orderBy], b[orderBy]) * (ascending ? 1 : -1));
      }
      if (limit != null && rows.length > limit) rows = rows.sublist(0, limit);
      return RemoteQueryResult.ok(rows);
    });
  }

  RemoteRow _publicProfileRow(RemoteRow row) {
    final gearPublic = row['privacy_public_gear'] != false;
    return <String, Object?>{
      'user_id': row['user_id'],
      'username': row['username'],
      'appearance_json': row['appearance_json'],
      'guild_id': row['guild_id'],
      'privacy_public_gear': gearPublic,
      'equipment_json': gearPublic ? row['equipment_json'] : null,
      'privacy_direct_messages': row['privacy_direct_messages'],
      'privacy_local_chat': row['privacy_local_chat'],
      'name_color': row['name_color'],
      'motto': row['motto'],
      'pet_cosmetic_id': row['pet_cosmetic_id'],
      'updated_at': row['updated_at'],
    };
  }

  /// The profile a leaderboard read joins in, with its guild name folded in.
  ///
  /// Matches `leaderboard_entries`: a missing profile still yields a row named
  /// Adventurer, so other players are not dropped off the board.
  RemoteRow _profileJoin(Object? userId) {
    for (final profile in tables[RemoteTables.profiles]!) {
      if (profile['user_id'] != userId) continue;
      Object? guildName = profile['guild_name'];
      Object? guildTag;
      final guildId = profile['guild_id'];
      if (guildId != null) {
        for (final guild in tables[RemoteTables.guilds]!) {
          if (guild['id'] == guildId) {
            guildName ??= guild['name'];
            guildTag = guild['tag'];
            break;
          }
        }
      }
      final username = profile['username'];
      return <String, Object?>{
        'username': username is String && username.isNotEmpty ? username : 'Adventurer',
        'appearance_json': _appearanceJson(profile['appearance_json']),
        'guild_id': guildId,
        'guilds': guildName == null
            ? null
            : <String, Object?>{'name': guildName, if (guildTag != null) 'tag': guildTag},
      };
    }
    return <String, Object?>{
      'username': 'Adventurer',
      'appearance_json': defaultPlayerAppearance.toJson(),
      'guild_id': null,
      'guilds': null,
    };
  }

  Object _appearanceJson(Object? value) {
    if (value is Map && value.isNotEmpty) return value;
    return defaultPlayerAppearance.toJson();
  }

  static int _compare(Object? a, Object? b) {
    if (a is num && b is num) return a.compareTo(b);
    return '$a'.compareTo('$b');
  }

  /// SQL LIKE with `%` as the only wildcard, enough for `dm:%` inbox reads.
  static bool _matchesLike(Object? value, String pattern) {
    final text = '$value';
    final regex = RegExp('^${pattern.split('%').map(RegExp.escape).join('.*')}\$');
    return regex.hasMatch(text);
  }

  @override
  Future<String?> upsert(String table, List<RemoteRow> rows, {String? onConflict}) {
    return _track(() async {
      calls.add('upsert:$table');
      final reason = _takeFailure('upsert:$table');
      if (reason != null) return reason;
      final missingTable = _missingTableRefusal(table);
      if (missingTable != null) return missingTable;
      for (final row in rows) {
        final missing = _missingColumnRefusal(table, row.keys.join(','));
        if (missing != null) return missing;
      }

      if (table == RemoteTables.saves) {
        final blocked = _playSessionRefusal(rows);
        if (blocked != null) return blocked;
      }

      final key = onConflict?.split(',').map((part) => part.trim()).toList() ?? _keys[table]!;
      final stored = tables.putIfAbsent(table, () => <RemoteRow>[]);
      for (final row in rows) {
        final at = stored.indexWhere((existing) => key.every((k) => existing[k] == row[k]));
        // PostgREST upsert fires BEFORE INSERT on the payload, then BEFORE
        // UPDATE on the merge. INSERT mutations do not carry into UPDATE NEW.
        if (table == RemoteTables.profiles) {
          final incoming = <String, Object?>{...row};
          final insertBlocked = _profileGuardRefusal(null, incoming);
          if (insertBlocked != null) return insertBlocked;
          if (at < 0) {
            stored.add(incoming);
            continue;
          }
        }
        final next = at >= 0 ? <String, Object?>{...stored[at], ...row} : <String, Object?>{...row};
        if (table == RemoteTables.profiles) {
          final blocked = _profileGuardRefusal(stored[at], next);
          if (blocked != null) return blocked;
        }
        if (table == RemoteTables.guilds) {
          final blocked = _guildLeaderGuardRefusal(at >= 0 ? stored[at] : null, next);
          if (blocked != null) return blocked;
        }
        if (at >= 0) {
          stored[at] = next;
        } else {
          stored.add(next);
        }
      }
      return null;
    });
  }

  @override
  Future<RemoteQueryResult> insert(String table, RemoteRow row, {required String columns}) async {
    calls.add('insert:$table');
    final reason = _takeFailure('insert:$table');
    if (reason != null) return RemoteQueryResult.failed(reason);
    final missingTable = _missingTableRefusal(table);
    if (missingTable != null) return RemoteQueryResult.failed(missingTable);
    final missing = _missingColumnRefusal(table, '$columns,${row.keys.join(',')}');
    if (missing != null) return RemoteQueryResult.failed(missing);

    final key = _keys[table]!;
    final stored = tables.putIfAbsent(table, () => <RemoteRow>[]);
    final written = <String, Object?>{..._defaults(table), ...row};
    if (table == RemoteTables.bountyClaims) {
      return const RemoteQueryResult.failed('permission denied for table bounty_claims');
    }
    if (table == RemoteTables.rankedPvpResults) {
      return const RemoteQueryResult.failed('permission denied for table ranked_pvp_results');
    }
    if (table == RemoteTables.profiles) {
      final blocked = _profileGuardRefusal(null, written);
      if (blocked != null) return RemoteQueryResult.failed(blocked);
    }
    if (stored.any((existing) => key.every((k) => existing[k] == written[k]))) {
      return RemoteQueryResult.failed(duplicateKeyRefusal);
    }
    for (final column in _unique[table] ?? const <String>[]) {
      if (!written.containsKey(column)) continue;
      if (stored.any((existing) => existing[column] == written[column])) {
        return RemoteQueryResult.failed(duplicateKeyRefusal);
      }
    }
    stored.add(written);
    return RemoteQueryResult.ok(<RemoteRow>[
      <String, Object?>{...written},
    ]);
  }

  @override
  Future<String?> update(
    String table,
    RemoteRow row, {
    required Map<String, Object?> equals,
  }) async {
    calls.add('update:$table');
    final reason = _takeFailure('update:$table');
    if (reason != null) return reason;
    final missing = _missingColumnRefusal(table, row.keys.join(','));
    if (missing != null) return missing;
    if (equals.isEmpty) return 'An update needs a filter.';

    final stored = tables.putIfAbsent(table, () => <RemoteRow>[]);
    for (var i = 0; i < stored.length; i++) {
      if (!equals.entries.every((filter) => stored[i][filter.key] == filter.value)) continue;
      final next = <String, Object?>{...stored[i], ...row};
      if (table == RemoteTables.profiles) {
        final blocked = _profileGuardRefusal(stored[i], next);
        if (blocked != null) return blocked;
      }
      if (table == RemoteTables.guilds) {
        final blocked = _guildLeaderGuardRefusal(stored[i], next);
        if (blocked != null) return blocked;
      }
      stored[i] = next;
      if (table == RemoteTables.guildMembers) {
        final guildId = next['guild_id'];
        if (guildId is String) _unlockFakeGuildAchievements(guildId);
      }
    }
    return null;
  }

  @override
  Future<String?> delete(String table, {required Map<String, Object?> equals}) async {
    calls.add('delete:$table');
    final reason = _takeFailure('delete:$table');
    if (reason != null) return reason;
    final missingTable = _missingTableRefusal(table);
    if (missingTable != null) return missingTable;
    if (equals.isEmpty) return 'A delete needs a filter.';

    final stored = tables.putIfAbsent(table, () => <RemoteRow>[]);
    stored.removeWhere((row) => equals.entries.every((filter) => row[filter.key] == filter.value));
    return null;
  }

  /// Matches send-chat: public profile name, then auth metadata, else Adventurer.
  String _publicChatUsername(FakeAccount sender) {
    String? publicName(Object? raw) {
      if (raw is! String) return null;
      final trimmed = raw.trim();
      if (trimmed.isEmpty || isPendingAccountUsername(trimmed)) return null;
      return remoteUsername(trimmed);
    }

    for (final profile in tables[RemoteTables.profiles] ?? const <RemoteRow>[]) {
      if (profile['user_id'] != sender.userId) continue;
      final named = publicName(profile['username']);
      if (named != null) return named;
      break;
    }
    final fromMeta = publicName(sender.username);
    if (fromMeta != null) return fromMeta;
    for (final save in tables[RemoteTables.saves] ?? const <RemoteRow>[]) {
      if (save['user_id'] != sender.userId) continue;
      final payload = save['payload'];
      if (payload is Map) {
        final named = publicName(payload['characterName']);
        if (named != null) return named;
      }
      break;
    }
    return 'Adventurer';
  }

  /// Matches send-chat: equipped title from the hosted save, never the request.
  String? _chatTitleForSender(FakeAccount sender) {
    for (final save in tables[RemoteTables.saves] ?? const <RemoteRow>[]) {
      if (save['user_id'] != sender.userId) continue;
      return chatTitleFromSavePayload(save['payload'], database);
    }
    return null;
  }

  num _clockMs() => nowMs?.call() ?? DateTime.parse(startIso).millisecondsSinceEpoch;

  String _clockIso() =>
      DateTime.fromMillisecondsSinceEpoch(_clockMs().round(), isUtc: true).toIso8601String();

  /// Matches the SQL trigger on profiles: guild tag and weekly rename cooldown.
  String? _profileGuardRefusal(RemoteRow? old, RemoteRow next) {
    final guildId = next['guild_id'];
    if (guildId != null) {
      final userId = next['user_id'];
      final members = tables[RemoteTables.guildMembers] ?? const <RemoteRow>[];
      final member = members.any((row) => row['user_id'] == userId && row['guild_id'] == guildId);
      if (!member) return remoteProfileGuildTagMismatch;
    }

    if (old == null) {
      next[remoteUsernameRenamedAtColumn] = null;
      return null;
    }

    final oldName = '${old['username'] ?? ''}';
    final newName = '${next['username'] ?? ''}';
    final oldStamp = old[remoteUsernameRenamedAtColumn];
    final newStamp = next[remoteUsernameRenamedAtColumn];
    if (newName == oldName) {
      if (newStamp != oldStamp) return remoteUsernameRenamedAtLocked;
      return null;
    }

    if (oldName.isEmpty ||
        isPendingAccountUsername(oldName) ||
        oldName.toLowerCase() == 'adventurer') {
      next[remoteUsernameRenamedAtColumn] = oldStamp;
      return null;
    }

    if (oldStamp is String && oldStamp.isNotEmpty) {
      final remaining = usernameRenameRemainingMs(oldStamp, _clockMs());
      if (remaining != null) return usernameRenameCooldownReason(remaining);
    }
    next[remoteUsernameRenamedAtColumn] = _clockIso();
    return null;
  }

  /// Matches the SQL trigger: only the current leader may write leader_id.
  String? _guildLeaderGuardRefusal(RemoteRow? old, RemoteRow next) {
    if (old == null) return null;
    if (old['leader_id'] == next['leader_id']) return null;
    if (_current?.userId == old['leader_id']) return null;
    return remoteGuildLeaderIdLocked;
  }

  /// Matches the SQL trigger: a kicked device may not write the account save.
  String? _playSessionRefusal(List<RemoteRow> rows) {
    for (final row in rows) {
      final userId = row['user_id'];
      RemoteRow? profile;
      for (final candidate in tables[RemoteTables.profiles]!) {
        if (candidate['user_id'] == userId) {
          profile = candidate;
          break;
        }
      }
      final active = profile?[remotePlaySessionColumn];
      if (active is! String || active.isEmpty) continue;
      if (row['play_session_id'] != active) return remoteSignedInElsewhere;
    }
    return null;
  }

  /// What a unique-key violation reads as, standing in for the database's own
  /// wording, which a caller must not depend on.
  static const String duplicateKeyRefusal = 'duplicate key value violates unique constraint';

  RemoteInvokeResult _invokeGame(RemoteRow body) {
    final caller = _current;
    if (caller == null) return const RemoteInvokeResult.failed('Not signed in.');
    final action = body['action'] as String? ?? '';
    if (action == 'command') {
      final commandName = body['command'];
      if (commandName is String && commandName.isNotEmpty) calls.add('game:$commandName');
    }
    final seated = _playSessionRefusal(<RemoteRow>[
      <String, Object?>{'user_id': caller.userId, 'play_session_id': body['playSessionId']},
    ]);
    if (seated != null) return RemoteInvokeResult.failed(seated);
    final saves = tables[RemoteTables.saves]!;
    RemoteRow? row;
    for (final candidate in saves) {
      if (candidate['user_id'] == caller.userId) {
        row = candidate;
        break;
      }
    }
    if (action == 'command' && body['command'] == 'create_character') {
      if (row != null) {
        return RemoteInvokeResult.ok(<String, Object?>{
          'ok': true,
          'phase': 2,
          'save': row['payload'],
          'version': row['version'] ?? 1,
          'rngState': row['rng_state'] ?? 1,
        });
      }
      final args = (body['args'] as Map?) ?? const <Object?, Object?>{};
      final db = database;
      Map<String, Object?> payload;
      if (db != null) {
        var save = createNewSave(db, _clockMs()).copyWith(characterName: args['name'] as String?);
        final raceId = args['raceId'];
        if (raceId is String && raceId.isNotEmpty) {
          final assigned = assignRace(db, save, raceId);
          if (assigned.ok) save = assigned.save!;
        }
        if (args['appearance'] is Map) {
          save = save.copyWith(
            appearance: PlayerAppearance.fromJson(<String, Object?>{
              ...save.appearance.toJson(),
              ...Map<String, Object?>.from(args['appearance'] as Map),
            }),
          );
        }
        payload = save.toJson();
      } else {
        payload = <String, Object?>{
          'characterName': args['name'],
          'raceId': args['raceId'],
          if (args['appearance'] is Map) 'appearance': args['appearance'],
          'gold': 0,
          'saveVersion': 60,
        };
      }
      final created = <String, Object?>{
        'user_id': caller.userId,
        'save_version': payload['saveVersion'] ?? 60,
        'updated_at': stamp(),
        'payload': payload,
        'version': 1,
        'rng_state': 1,
      };
      saves.add(created);
      return RemoteInvokeResult.ok(<String, Object?>{
        'ok': true,
        'phase': 2,
        'save': payload,
        'version': 1,
        'rngState': 1,
      });
    }
    if (row == null) {
      return const RemoteInvokeResult.failed('No cloud save.');
    }
    if (body['command'] == 'set_loadout') {
      _overlaySetLoadout(row, body);
    }
    if (body['command'] == 'guild_create') return _foundGuildCommand(caller.userId, body, row);
    final hallCommand = _applyGuildHallCommand(caller.userId, body, row);
    if (hallCommand != null) return hallCommand;
    final ranked = _applyRankedPvpFight(caller.userId, caller.username ?? 'Adventurer', body, row);
    if (ranked != null) return ranked;
    final bounty = _applyBountyTurnIn(caller.userId, caller.username ?? 'Adventurer', body, row);
    if (bounty != null) return bounty;
    final plaza = _applyPlazaShopBuy(caller.userId, body, row);
    if (plaza != null) return plaza;
    final version = ((row['version'] as num?) ?? 1).toInt() + 1;
    row['version'] = version;
    row['updated_at'] = stamp();
    _publishPhase3(caller.userId, caller.username ?? 'Adventurer', body, row);
    return RemoteInvokeResult.ok(<String, Object?>{
      'ok': true,
      'phase': 2,
      'action': action,
      'save': row['payload'],
      'version': version,
      'rngState': row['rng_state'] ?? 1,
    });
  }

  void _publishPhase3(String userId, String username, RemoteRow body, RemoteRow saveRow) {
    final db = database;
    final payload = saveRow['payload'];
    if (db == null || payload is! Map) return;
    PlayerSave save;
    try {
      save = parseSave(Map<String, Object?>.from(payload), _clockMs());
    } on Object {
      return;
    }
    final command = body['command'] as String? ?? '';
    _overlayPublishedPvp(userId, username, save);
    if (command == 'submit_leaderboard') {
      final nowIso = isoFromMs(_clockMs());
      final rows = leaderboardRowsFor(userId, buildLeaderboardSnapshot(db, save), nowIso);
      final boards = tables[RemoteTables.leaderboard]!;
      for (final row in rows) {
        boards.removeWhere(
          (existing) =>
              existing['user_id'] == row['user_id'] && existing['board_key'] == row['board_key'],
        );
        boards.add(row);
      }
      final profiles = tables[RemoteTables.profiles]!;
      final at = profiles.indexWhere((row) => row['user_id'] == userId);
      if (at >= 0) {
        final patch = <String, Object?>{
          ...profiles[at],
          'appearance_json': appearanceJsonForPlayerSave(save),
        };
        if (!missingColumns.contains(remoteEquipmentJsonColumn)) {
          patch[remoteEquipmentJsonColumn] = publicEquipmentFromSave(save)
              .map((row) => row.toJson())
              .toList();
        }
        if (!missingColumns.contains(remoteMottoColumn)) {
          patch[remoteMottoColumn] = save.motto;
        }
        if (!missingColumns.contains(remotePetCosmeticIdColumn)) {
          patch[remotePetCosmeticIdColumn] = save.cosmetics.equipped[petCosmeticSlotId];
        }
        profiles[at] = patch;
      }
    }
    if (command == 'save_pvp_equipment') {
      final snapshots = tables[RemoteTables.pvpSnapshots]!;
      snapshots.removeWhere((row) => row['user_id'] == userId);
      snapshots.add(
        pvpSnapshotRowFor(
          session: MultiplayerSession(
            userId: userId,
            email: '',
            username: username,
            accessToken: '',
          ),
          save: save,
          updatedAt: isoFromMs(_clockMs()),
        ),
      );
    }
  }

  void _overlayPublishedPvp(String userId, String username, PlayerSave live) {
    final snapshots = tables[RemoteTables.pvpSnapshots]!;
    final at = snapshots.indexWhere((row) => row['user_id'] == userId);
    if (at < 0) return;
    final existing = pvpSnapshotPayloadFrom(snapshots[at]);
    if (existing == null) return;
    PlayerSave snapshot;
    try {
      snapshot = parseSave(existing, _clockMs());
    } on Object {
      return;
    }
    snapshots[at] = pvpSnapshotRowFor(
      session: MultiplayerSession(userId: userId, email: '', username: username, accessToken: ''),
      save: overlayPvpLiveStats(snapshot, live),
      updatedAt: isoFromMs(_clockMs()),
    );
  }

  RemoteInvokeResult? _applyGuildHallCommand(String userId, RemoteRow body, RemoteRow saveRow) {
    final command = body['command'] as String? ?? '';
    if (command != 'guild_pay_hall_debt' &&
        command != 'guild_chip_in_hall_gold' &&
        command != 'guild_donate_hall_item' &&
        command != 'guild_withdraw_hall_item' &&
        command != 'guild_bank_deposit' &&
        command != 'guild_bank_withdraw' &&
        command != 'guild_bank_take_up_for_grabs' &&
        command != 'guild_bank_move_up_for_grabs') {
      return null;
    }
    final membership = _membershipFor(userId);
    if (membership == null) return const RemoteInvokeResult.failed('Join a guild first.');
    final halls = tables[RemoteTables.guildHalls]!;
    final at = halls.indexWhere((row) => row['guild_id'] == membership['guild_id']);
    if (at < 0) return const RemoteInvokeResult.failed('Guild hall not found.');
    final hall = guildHallFrom(halls[at]);
    final role = '${membership['role'] ?? ''}';
    if ((command == 'guild_pay_hall_debt' || command == 'guild_chip_in_hall_gold') &&
        !canChipInGuildGold(role)) {
      return const RemoteInvokeResult.failed('Recruits cannot chip in gold.');
    }
    if (command.startsWith('guild_bank_') && !guildHallBankUnlocked(hall.completedTiers)) {
      return const RemoteInvokeResult.failed('The counting room is not built yet.');
    }
    final payload = saveRow['payload'];
    if (payload is! Map)
      return const RemoteInvokeResult.failed('The cloud save could not be read.');
    PlayerSave save;
    try {
      save = parseSave(Map<String, Object?>.from(payload), _clockMs());
    } on Object {
      return const RemoteInvokeResult.failed('The cloud save could not be read.');
    }
    final args = (body['args'] as Map?) ?? const <Object?, Object?>{};
    final guildRow = _guildRow(membership['guild_id']);
    final table = normalizeGuildPermissionTable(guildRow?['permissions']);
    if (command == 'guild_bank_deposit' && !guildMay(role, guildPermissionDeposit, table)) {
      return const RemoteInvokeResult.failed('You cannot deposit in the guild bank.');
    }
    if (command == 'guild_bank_withdraw' && !guildMay(role, guildPermissionWithdraw, table)) {
      return const RemoteInvokeResult.failed('You cannot withdraw from the guild bank.');
    }
    if (command == 'guild_bank_withdraw' &&
        !guildMayWithdrawAtLevel(_asNum(membership['total_level']))) {
      return const RemoteInvokeResult.failed(guildBankLevelWithdrawRefusal);
    }
    if (command == 'guild_bank_take_up_for_grabs' && !guildMayWithdrawAtLevel(totalLevel(save))) {
      return const RemoteInvokeResult.failed(guildBankLevelTakeRefusal);
    }
    if (command == 'guild_bank_move_up_for_grabs' &&
        !guildMay(role, guildPermissionMoveUpForGrabs, table)) {
      return const RemoteInvokeResult.failed('You cannot move items to Up for grabs.');
    }
    final GuildHallActionResult result;
    if (command == 'guild_pay_hall_debt' || command == 'guild_chip_in_hall_gold') {
      result = chipInGuildHallGold(hall, userId, save, _asNum(args['amount']));
    } else if (command == 'guild_donate_hall_item') {
      final index = _asNum(args['inventoryIndex']).toInt();
      final itemId = index >= 0 && index < save.inventory.length
          ? save.inventory[index].itemId
          : null;
      result = itemId != null && bazaarItemBound(database, itemId)
          ? const GuildHallActionResult.failed(bazaarBoundItem)
          : donateToGuildHall(hall, save, index, _asNum(args['quantity']), userId: userId);
    } else if (command == 'guild_bank_deposit') {
      final index = _asNum(args['inventoryIndex']).toInt();
      final itemId = index >= 0 && index < save.inventory.length
          ? save.inventory[index].itemId
          : null;
      if (itemId != null && bazaarItemBound(database, itemId)) {
        return const RemoteInvokeResult.failed(bazaarBoundItem);
      }
      final deposited = depositToGuildBank(
        hall.bank,
        save,
        index,
        _asNum(args['quantity']),
        () => 'gb-${_clockMs()}',
        db: database,
      );
      result = deposited.ok
          ? GuildHallActionResult.ok(hall.copyWith(bank: deposited.bank), save: deposited.save)
          : GuildHallActionResult.failed(deposited.reason ?? 'Could not deposit.');
    } else if (command == 'guild_bank_withdraw') {
      final withdrawn = withdrawFromGuildBank(
        hall.bank,
        save,
        args['itemId'] as String? ?? '',
        _asNum(args['quantity']),
        args['enchantmentId'] as String?,
      );
      result = withdrawn.ok
          ? GuildHallActionResult.ok(hall.copyWith(bank: withdrawn.bank), save: withdrawn.save)
          : GuildHallActionResult.failed(withdrawn.reason ?? 'Could not withdraw.');
    } else if (command == 'guild_bank_take_up_for_grabs') {
      final taken = takeGuildBankUpForGrabs(
        hall.bank,
        save,
        args['itemId'] as String? ?? '',
        _asNum(args['quantity']),
        args['enchantmentId'] as String?,
      );
      result = taken.ok
          ? GuildHallActionResult.ok(hall.copyWith(bank: taken.bank), save: taken.save)
          : GuildHallActionResult.failed(taken.reason ?? 'Could not take.');
    } else if (command == 'guild_bank_move_up_for_grabs') {
      final moved = moveGuildBankToUpForGrabs(
        hall.bank,
        save,
        args['itemId'] as String? ?? '',
        _asNum(args['quantity']),
        args['enchantmentId'] as String?,
        () => 'gb-${_clockMs()}',
      );
      result = moved.ok
          ? GuildHallActionResult.ok(hall.copyWith(bank: moved.bank), save: moved.save)
          : GuildHallActionResult.failed(moved.reason ?? 'Could not move.');
    } else {
      result = const GuildHallActionResult.failed(
        'That hall action is not available in this stand-in.',
      );
    }
    if (!result.ok) return RemoteInvokeResult.failed(result.reason ?? 'Guild hall action failed.');
    final nextHall = result.hall!.copyWith(hallRevision: hall.hallRevision + 1);
    halls[at] = <String, Object?>{...halls[at], ...guildHallRowFor(nextHall)};
    _unlockFakeGuildAchievements('${membership['guild_id']}');
    if (result.goldChipped > 0 || result.donatedItem != null) {
      _appendGuildLog('${membership['guild_id']}', <String, Object?>{
        'kind': guildLogKindDonation,
        'actor_user_id': userId,
        'actor_username': '${membership['username'] ?? 'Adventurer'}',
        'gold': result.goldChipped,
        'items': result.donatedItem == null
            ? const <Object?>[]
            : <Object?>[result.donatedItem!.toJson()],
      });
    }
    for (final tierId in result.tiersFinishedNow) {
      _appendGuildLog('${membership['guild_id']}', <String, Object?>{
        'kind': guildLogKindTierComplete,
        'actor_user_id': userId,
        'actor_username': '${membership['username'] ?? 'Adventurer'}',
        'tier_id': tierId,
        'message': guildHallTierFinishLine(tierId) ?? '',
      });
    }
    final next = result.save ?? save;
    saveRow['payload'] = next.toJson();
    final version = ((saveRow['version'] as num?) ?? 1).toInt() + 1;
    saveRow['version'] = version;
    saveRow['updated_at'] = stamp();
    _publishPhase3(userId, _current?.username ?? 'Adventurer', body, saveRow);
    return RemoteInvokeResult.ok(<String, Object?>{
      'ok': true,
      'phase': 2,
      'save': next.toJson(),
      'version': version,
      'rngState': saveRow['rng_state'] ?? 1,
    });
  }

  static const String saveVersionConflictReason = 'Save version conflict. Sync and retry.';

  bool _saveVersionConflicts(RemoteRow body, RemoteRow saveRow) {
    final expected = body['version'];
    if (expected is! num) return false;
    return expected.toInt() != ((saveRow['version'] as num?) ?? 1).toInt();
  }

  RemoteInvokeResult _saveVersionConflictResult({num? winsRemaining}) {
    return RemoteInvokeResult.ok(<String, Object?>{
      'error': saveVersionConflictReason,
      'phase': 2,
      'conflict': true,
      if (winsRemaining != null) 'winsRemaining': winsRemaining,
    });
  }

  RemoteInvokeResult _rankedFightRefusal(String error, num winsRemaining) {
    return RemoteInvokeResult.ok(<String, Object?>{
      'error': error,
      'phase': 2,
      'winsRemaining': winsRemaining,
    });
  }

  RemoteInvokeResult? _applyRankedPvpFight(
    String userId,
    String username,
    RemoteRow body,
    RemoteRow saveRow,
  ) {
    if (body['command'] != 'ranked_pvp_fight') return null;
    final args = (body['args'] as Map?) ?? const <Object?, Object?>{};
    final payload = saveRow['payload'];
    num winsRemaining = rankedPvpDailyCap;
    PlayerSave? parsedSave;
    if (payload is Map) {
      try {
        parsedSave = parseSave(Map<String, Object?>.from(payload), _clockMs());
        winsRemaining = rankedWinsRemaining(parsedSave, _clockMs());
      } on Object {
        parsedSave = null;
      }
    }
    if (args.containsKey('won')) {
      return _rankedFightRefusal(rankedPvpFakedWinRefusal, winsRemaining);
    }
    final requested = args['fightId'];
    final results = tables.putIfAbsent(RemoteTables.rankedPvpResults, () => <RemoteRow>[]);
    if (requested is String && requested.isNotEmpty) {
      RemoteRow? existing;
      for (final row in results) {
        if (row['user_id'] == userId && row['fight_id'] == requested) {
          existing = row;
          break;
        }
      }
      if (existing == null) return _rankedFightRefusal(rankedPvpUnknownFightRefusal, winsRemaining);
      // Already recorded: return the stored row even if the app still has the
      // pre-fight save version (a lost first response).
      return RemoteInvokeResult.ok(<String, Object?>{
        'ok': true,
        'phase': 2,
        'save': saveRow['payload'],
        'version': saveRow['version'] ?? 1,
        'rngState': saveRow['rng_state'] ?? 1,
        'wroteSave': false,
        'fightId': existing['fight_id'],
        'rounds': existing['rounds'] ?? const <Object?>[],
        'pvpOutcome': existing['outcome'],
        'goldGained': 0,
        'pointsGained': existing['points_paid'] ?? 0,
        'plazaPoints': plazaResponseInt(parsedSave?.plazaPoints),
        'code': existing['code'],
        'winsRemaining': existing['wins_remaining'] ?? 0,
        'youMaxHp': existing['you_max_hp'] ?? 0,
        'themMaxHp': existing['them_max_hp'] ?? 0,
      });
    }
    final db = database;
    if (db == null) return _rankedFightRefusal('No other players to fight.', winsRemaining);
    if (parsedSave == null) {
      return _rankedFightRefusal('The cloud save could not be read.', winsRemaining);
    }
    final save = parsedSave;
    final snapshots = tables[RemoteTables.pvpSnapshots] ?? const <RemoteRow>[];
    final candidates = <ArenaOpponent>[];
    final payloads = <String, PlayerSave>{};
    for (final row in snapshots) {
      final id = row['user_id'];
      if (id is! String || id == userId) continue;
      final snap = pvpSnapshotPayloadFrom(row);
      if (snap == null) continue;
      try {
        final them = parseSave(snap, _clockMs());
        candidates.add(
          ArenaOpponent(
            userId: id,
            username: row['username'] as String? ?? 'Adventurer',
            combatLevel: combatLevelOf(them),
            totalLevel: totalLevel(them),
          ),
        );
        payloads[id] = them;
      } on Object {
        continue;
      }
    }
    final pick = pickRankedOpponent(combatLevelOf(save), totalLevel(save), candidates);
    if (pick == null) return _rankedFightRefusal('No other players to fight.', winsRemaining);
    final them = payloads[pick.userId]!;
    final rng = Mulberry32(((saveRow['rng_state'] as num?) ?? 1).toInt());
    final fight = simulatePvpFight(db, save, them, rng.asFunction);
    final applied = applyRankedPvpResult(save, fight.outcome == 'win', _clockMs());
    final fightId = '11111111-1111-1111-1111-${(results.length + 1).toString().padLeft(12, '0')}';
    results.add(<String, Object?>{
      'user_id': userId,
      'fight_id': fightId,
      'opponent_id': pick.userId,
      'outcome': fight.outcome,
      'gold_paid': 0,
      'points_paid': applied.pointsGained,
      'code': applied.code,
      'rounds': fight.rounds.map((round) => round.toJson()).toList(),
      'you_max_hp': fight.youMaxHp,
      'them_max_hp': fight.themMaxHp,
      'wins_remaining': applied.winsRemaining,
    });
    if (_saveVersionConflicts(body, saveRow)) {
      results.removeWhere((row) => row['user_id'] == userId && row['fight_id'] == fightId);
      return _saveVersionConflictResult(winsRemaining: winsRemaining);
    }
    saveRow['payload'] = applied.save.toJson();
    final version = ((saveRow['version'] as num?) ?? 1).toInt() + 1;
    saveRow['version'] = version;
    saveRow['updated_at'] = stamp();
    return RemoteInvokeResult.ok(<String, Object?>{
      'ok': true,
      'phase': 2,
      'save': applied.save.toJson(),
      'version': version,
      'rngState': rng.state,
      'fightId': fightId,
      'rounds': fight.rounds.map((round) => round.toJson()).toList(),
      'pvpOutcome': fight.outcome,
      'goldGained': 0,
      'pointsGained': applied.pointsGained,
      'plazaPoints': plazaPointsOf(applied.save),
      'code': applied.code,
      'winsRemaining': applied.winsRemaining,
      'youMaxHp': fight.youMaxHp,
      'themMaxHp': fight.themMaxHp,
      'opponent': pick.toJson(),
    });
  }

  RemoteInvokeResult? _applyBountyTurnIn(
    String userId,
    String username,
    RemoteRow body,
    RemoteRow saveRow,
  ) {
    if (body['command'] != 'bounty_turn_in') return null;
    final args = (body['args'] as Map?) ?? const <Object?, Object?>{};
    final bountyId = args['bountyId'];
    if (bountyId is! String || bountyId.isEmpty) {
      return const RemoteInvokeResult.failed('Missing bounty.');
    }
    final payload = saveRow['payload'];
    if (payload is! Map)
      return const RemoteInvokeResult.failed('The cloud save could not be read.');
    PlayerSave save;
    try {
      save = parseSave(Map<String, Object?>.from(payload), _clockMs());
    } on Object {
      return const RemoteInvokeResult.failed('The cloud save could not be read.');
    }
    final nowMs = _clockMs();
    final board = hourlyBountyBoard(nowMs);
    BountyDefinition? bounty;
    for (final row in board.bounties) {
      if (row.id == bountyId) {
        bounty = row;
        break;
      }
    }
    if (bounty == null) {
      return const RemoteInvokeResult.failed('That bounty is not on the current board.');
    }
    final prepared = prepareBountyTurnIn(save, bounty, nowMs);
    if (!prepared.ok) return RemoteInvokeResult.failed(prepared.reason!);
    final claims = tables[RemoteTables.bountyClaims]!;
    RemoteRow? existing;
    for (final row in claims) {
      if (row['hour_key'] == board.hourKey && row['bounty_id'] == bountyId) {
        existing = row;
        break;
      }
    }
    final firstCompleter = existing == null || existing['user_id'] == userId;
    if (existing == null) {
      claims.add(<String, Object?>{
        'hour_key': board.hourKey,
        'bounty_id': bountyId,
        'user_id': userId,
        'username': username,
        'claimed_at': stamp(),
      });
    } else if (existing['user_id'] == userId &&
        (prepared.save!.bountyClaimedIds.contains(bountyId))) {
      return const RemoteInvokeResult.failed('You already claimed this bounty.');
    }
    if (_saveVersionConflicts(body, saveRow)) {
      if (existing == null) {
        claims.removeWhere(
          (row) => row['hour_key'] == board.hourKey && row['bounty_id'] == bountyId,
        );
      }
      return _saveVersionConflictResult();
    }
    final rewarded = applyBountyReward(prepared.save!, bounty, firstCompleter);
    saveRow['payload'] = rewarded.save.toJson();
    final version = ((saveRow['version'] as num?) ?? 1).toInt() + 1;
    saveRow['version'] = version;
    saveRow['updated_at'] = stamp();
    final claim = claims.firstWhere(
      (row) => row['hour_key'] == board.hourKey && row['bounty_id'] == bountyId,
    );
    return RemoteInvokeResult.ok(<String, Object?>{
      'ok': true,
      'phase': 2,
      'save': rewarded.save.toJson(),
      'version': version,
      'rngState': saveRow['rng_state'] ?? 1,
      'goldGained': 0,
      'pointsGained': rewarded.pointsGained,
      'plazaPoints': plazaPointsOf(rewarded.save),
      'firstCompleter': firstCompleter,
      'claim': <String, Object?>{
        'hourKey': claim['hour_key'],
        'bountyId': claim['bounty_id'],
        'userId': claim['user_id'],
        'username': claim['username'],
        'claimedAt': claim['claimed_at'],
      },
    });
  }

  RemoteInvokeResult? _applyPlazaShopBuy(String userId, RemoteRow body, RemoteRow saveRow) {
    if (body['command'] != 'plaza_shop_buy') return null;
    final args = (body['args'] as Map?) ?? const <Object?, Object?>{};
    final itemId = args['itemId'];
    if (itemId is! String || itemId.isEmpty) {
      return const RemoteInvokeResult.failed('Missing item.');
    }
    final db = database;
    if (db == null)
      return const RemoteInvokeResult.failed('The plaza shop does not sell that item.');
    final payload = saveRow['payload'];
    if (payload is! Map)
      return const RemoteInvokeResult.failed('The cloud save could not be read.');
    PlayerSave save;
    try {
      save = parseSave(Map<String, Object?>.from(payload), _clockMs());
    } on Object {
      return const RemoteInvokeResult.failed('The cloud save could not be read.');
    }
    final bought = purchasePlazaShopItem(db, save, itemId, args['points'] ?? args['amount']);
    if (!bought.ok) return RemoteInvokeResult.failed(bought.reason!);
    if (_saveVersionConflicts(body, saveRow)) return _saveVersionConflictResult();
    saveRow['payload'] = bought.save!.toJson();
    final version = ((saveRow['version'] as num?) ?? 1).toInt() + 1;
    saveRow['version'] = version;
    saveRow['updated_at'] = stamp();
    return RemoteInvokeResult.ok(<String, Object?>{
      'ok': true,
      'phase': 2,
      'save': bought.save!.toJson(),
      'version': version,
      'rngState': saveRow['rng_state'] ?? 1,
      'pointsGained': 0,
      'plazaPoints': bought.plazaPoints,
      'pointsSpent': bought.pointsSpent,
    });
  }

  @override
  Future<RemoteInvokeResult> invoke(String function, RemoteRow body) {
    return _track(() async {
      calls.add('invoke:$function');
      final reason = _takeFailure('invoke:$function');
      if (reason != null) return RemoteInvokeResult.failed(reason);
      if (function == remoteBazaarMarketFunction) {
        final caller = _current;
        if (caller == null) return const RemoteInvokeResult.failed('Not signed in.');
        return exchange.call(
          userId: caller.userId,
          username: caller.username ?? 'Adventurer',
          body: body,
        );
      }
      if (function == remoteGameFunction) {
        if (missingGameFunction) {
          return const RemoteInvokeResult.failed('Requested function was not found');
        }
        return _invokeGame(body);
      }
      if (function != remoteSendChatFunction) {
        return RemoteInvokeResult.failed('No such function: $function');
      }
      if (chatFunctionReply != null) return RemoteInvokeResult.ok(chatFunctionReply);

      final sender = _current;
      if (sender == null) return const RemoteInvokeResult.failed('Not signed in.');
      final row = <String, Object?>{
        'id': _nextId('msg'),
        'channel_key': body['channelKey'],
        'user_id': sender.userId,
        'username': _publicChatUsername(sender),
        'body': body['body'],
        'created_at': stamp(),
        // Equipped title from the hosted save. A client-supplied title is ignored.
        'title': _chatTitleForSender(sender),
      };
      tables[RemoteTables.chat]!.add(row);
      return RemoteInvokeResult.ok(<String, Object?>{...row});
    });
  }

  @override
  Future<RemoteInvokeResult> rpc(String function, RemoteRow args) {
    return _track(() async {
      calls.add('rpc:$function');
      final reason = _takeFailure('rpc:$function');
      if (reason != null) return RemoteInvokeResult.failed(reason);

      if (function == RemoteRpcs.guildSetBanner) {
        final guildId = args['p_guild'];
        final me = _current?.userId;
        if (me == null) {
          return RemoteInvokeResult.ok(<String, Object?>{'ok': false, 'reason': 'Sign in first.'});
        }
        final guilds = tables[RemoteTables.guilds]!;
        final at = guilds.indexWhere((row) => row['id'] == guildId);
        if (at < 0) {
          return RemoteInvokeResult.ok(<String, Object?>{
            'ok': false,
            'reason': 'That guild could not be found.',
          });
        }
        final membership = _membershipFor(me);
        final role = '${membership?['role'] ?? ''}';
        final leaderId = '${guilds[at]['leader_id']}';
        final manager = me == leaderId || role == guildRoleOfficer;
        if (!manager || membership?['guild_id'] != guildId) {
          return RemoteInvokeResult.ok(<String, Object?>{
            'ok': false,
            'reason': guildBannerRoleRefusal,
          });
        }
        final unlocks = tables[RemoteTables.guildAchievements]!
            .where((row) => row['guild_id'] == guildId)
            .map((row) => '${row['achievement_id'] ?? ''}');
        final parsed = normalizeGuildBanner(args['p_banner'], unlocks);
        if (!parsed.ok || parsed.banner == null) {
          return RemoteInvokeResult.ok(<String, Object?>{
            'ok': false,
            'reason': parsed.reason ?? guildBannerColourRefusal,
          });
        }
        guilds[at] = <String, Object?>{...guilds[at], 'banner': parsed.banner!.toJson()};
        return RemoteInvokeResult.ok(<String, Object?>{
          'ok': true,
          'banner': parsed.banner!.toJson(),
        });
      }

      if (function == RemoteRpcs.guildSetMotto) {
        final guildId = args['p_guild'];
        final motto = guildMottoFromInput('${args['p_motto'] ?? ''}');
        final me = _current?.userId;
        if (me == null) {
          return RemoteInvokeResult.ok(<String, Object?>{'ok': false, 'reason': 'Sign in first.'});
        }
        final guilds = tables[RemoteTables.guilds]!;
        final at = guilds.indexWhere((row) => row['id'] == guildId);
        if (at < 0) {
          return RemoteInvokeResult.ok(<String, Object?>{
            'ok': false,
            'reason': 'That guild could not be found.',
          });
        }
        final membership = _membershipFor(me);
        final role = '${membership?['role'] ?? ''}';
        final leaderId = '${guilds[at]['leader_id']}';
        final manager = me == leaderId || role == guildRoleOfficer;
        if (!manager || membership?['guild_id'] != guildId) {
          return RemoteInvokeResult.ok(<String, Object?>{
            'ok': false,
            'reason': 'Only the guild leader or an officer can edit the motto.',
          });
        }
        guilds[at] = <String, Object?>{...guilds[at], 'description': motto};
        return RemoteInvokeResult.ok(<String, Object?>{'ok': true, 'motto': motto});
      }

      if (function == RemoteRpcs.guildSetMessage) {
        final guildId = args['p_guild'];
        final body = guildPrivateMessageFromInput('${args['p_body'] ?? ''}');
        final me = _current?.userId;
        if (me == null) {
          return RemoteInvokeResult.ok(<String, Object?>{'ok': false, 'reason': 'Sign in first.'});
        }
        final membership = _membershipFor(me);
        final role = '${membership?['role'] ?? ''}';
        final guilds = tables[RemoteTables.guilds]!;
        RemoteRow? guild;
        for (final row in guilds) {
          if (row['id'] == guildId) {
            guild = row;
            break;
          }
        }
        final leaderId = '${guild?['leader_id'] ?? ''}';
        final manager = me == leaderId || role == guildRoleOfficer;
        if (!manager || membership?['guild_id'] != guildId) {
          return RemoteInvokeResult.ok(<String, Object?>{
            'ok': false,
            'reason': 'Only the guild leader or an officer can edit the guild message.',
          });
        }
        final stored = tables.putIfAbsent(RemoteTables.guildPrivateMessages, () => <RemoteRow>[]);
        final at = stored.indexWhere((row) => row['guild_id'] == guildId);
        final row = <String, Object?>{
          'guild_id': guildId,
          'body': body,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'updated_by': me,
        };
        if (at < 0) {
          stored.add(row);
        } else {
          stored[at] = row;
        }
        return RemoteInvokeResult.ok(<String, Object?>{'ok': true, 'body': body});
      }

      if (function == RemoteRpcs.guildContributeProject) {
        final projectId = args['p_project_id'];
        final amount = _asNum(args['p_amount']);
        final stored = tables[RemoteTables.guildProjects]!;
        final at = stored.indexWhere((row) => row['id'] == projectId);
        if (at < 0) return const RemoteInvokeResult.failed('Project not found.');
        final next = <String, Object?>{
          ...stored[at],
          'contributed': _asNum(stored[at]['contributed']) + amount,
        };
        stored[at] = next;
        return RemoteInvokeResult.ok(next);
      }

      if (function == RemoteRpcs.guildSetPermissions) {
        final guildId = args['p_guild_id'];
        final perms = args['p_permissions'];
        final stored = tables[RemoteTables.guilds]!;
        final at = stored.indexWhere((row) => row['id'] == guildId);
        if (at < 0) return const RemoteInvokeResult.failed('Guild not found.');
        if (stored[at]['leader_id'] != _current?.userId) {
          return const RemoteInvokeResult.failed('Only the leader can change permissions.');
        }
        stored[at] = <String, Object?>{...stored[at], 'permissions': perms};
        return RemoteInvokeResult.ok(<String, Object?>{'ok': true, 'permissions': perms});
      }

      if (function == RemoteRpcs.guildSetMemberRole) {
        final guildId = args['p_guild_id'];
        final target = args['p_target_user_id'];
        final role = args['p_role'];
        final stored = tables[RemoteTables.guildMembers]!;
        final at = stored.indexWhere(
          (row) => row['guild_id'] == guildId && row['user_id'] == target,
        );
        if (at < 0) return const RemoteInvokeResult.failed('Member not found.');
        final next = <String, Object?>{...stored[at], 'role': role};
        stored[at] = next;
        _appendGuildLog('$guildId', <String, Object?>{
          'kind': guildLogKindRankChange,
          'actor_user_id': target,
          'actor_username': next['username'] ?? 'Adventurer',
          'role': role,
          'target_user_id': target,
          'target_username': next['username'] ?? 'Adventurer',
          'message': '${next['username'] ?? 'Adventurer'} is now $role.',
        });
        return RemoteInvokeResult.ok(next);
      }

      if (function == RemoteRpcs.guildPayHallDebt) {
        final amount = _asNum(args['p_amount']);
        final membership = _membershipFor(_current?.userId);
        if (membership == null) {
          return const RemoteInvokeResult.failed('Join a guild first.');
        }
        final stored = tables[RemoteTables.guildHalls]!;
        final at = stored.indexWhere((row) => row['guild_id'] == membership['guild_id']);
        if (at < 0) return const RemoteInvokeResult.failed('Guild hall not found.');
        final hall = stored[at];
        final remaining = _asNum(hall['debt_remaining']);
        final pay = amount < remaining ? amount : remaining;
        final paidBy = <String, Object?>{
          ..._asMap(hall['debt_paid_by']),
          '${_current!.userId}': _asNum(_asMap(hall['debt_paid_by'])['${_current!.userId}']) + pay,
        };
        final nextRemaining = remaining - pay;
        final next = <String, Object?>{
          ...hall,
          'debt_remaining': nextRemaining,
          'debt_paid_by': paidBy,
          'debt_paid_off': nextRemaining <= 0,
        };
        stored[at] = next;
        return RemoteInvokeResult.ok(next);
      }

      if (function == RemoteRpcs.guildDonateHallItem) {
        final itemId = '${args['p_item_id']}';
        final quantity = _asNum(args['p_quantity']);
        final membership = _membershipFor(_current?.userId);
        if (membership == null) {
          return const RemoteInvokeResult.failed('Join a guild first.');
        }
        final stored = tables[RemoteTables.guildHalls]!;
        final at = stored.indexWhere((row) => row['guild_id'] == membership['guild_id']);
        if (at < 0) return const RemoteInvokeResult.failed('Guild hall not found.');
        final hall = stored[at];
        final store = [for (final entry in _asList(hall['storehouse'])) _asMap(entry)];
        var found = false;
        for (var i = 0; i < store.length; i++) {
          if (store[i]['itemId'] == itemId) {
            store[i] = <String, Object?>{
              'itemId': itemId,
              'quantity': _asNum(store[i]['quantity']) + quantity,
            };
            found = true;
            break;
          }
        }
        if (!found) {
          store.add(<String, Object?>{'itemId': itemId, 'quantity': quantity});
        }
        final next = <String, Object?>{...hall, 'storehouse': store};
        stored[at] = next;
        return RemoteInvokeResult.ok(next);
      }

      if (RemoteRpcs.guildLifecycle.contains(function)) {
        if (!hostsGuildLifecycleRpcs) return RemoteInvokeResult.failed(_missingRpc(function));
        final me = _current?.userId;
        if (me == null) return const RemoteInvokeResult.failed('Sign in first.');
        return RemoteInvokeResult.ok(_guildLifecycleRpc(me, function, args));
      }

      if (function == RemoteRpcs.blockPlayer || function == RemoteRpcs.unblockPlayer) {
        return _blockRpc(function, args);
      }
      if (function == RemoteRpcs.listMyBlocks) return _listBlocksRpc();
      if (function == RemoteRpcs.reportPlayer) return _reportRpc(args);
      if (function == RemoteRpcs.usernameAvailable) return _usernameAvailableRpc(args);
      if (function == RemoteRpcs.renameUsername) return _renameUsernameRpc(args);

      return RemoteInvokeResult.failed('No such function: $function');
    });
  }

  List<RemoteRow> _socialRows(String table) => tables.putIfAbsent(table, () => <RemoteRow>[]);

  /// PostgREST's answer for a function the project has not created.
  static String _missingRpc(String function) =>
      'Could not find the function public.$function in the schema cache';

  void _unlockFakeGuildAchievements(String guildId) {
    GuildHallState hall = GuildHallState.fresh(guildId);
    for (final row in tables[RemoteTables.guildHalls]!) {
      if (row['guild_id'] == guildId) {
        hall = guildHallFrom(row);
        break;
      }
    }
    var strong = 0;
    for (final row in tables[RemoteTables.guildMembers]!) {
      if (row['guild_id'] == guildId && _asNum(row['total_level']) >= guildAchievementMemberLevel) {
        strong += 1;
      }
    }
    final unlocked = <String, String>{
      for (final row in tables[RemoteTables.guildAchievements]!)
        if (row['guild_id'] == guildId &&
            row['achievement_id'] is String &&
            row['unlocked_at'] is String)
          row['achievement_id'] as String: row['unlocked_at'] as String,
    };
    final evaluated = evaluateGuildAchievements(
      GuildAchievementSnapshot(
        completedTiers: hall.completedTiers,
        goldContributed: hall.goldContributed,
        goldContributedBy: hall.goldContributedBy,
        donatedBy: hall.donatedBy,
        membersAtLevel500: strong,
        unlocked: unlocked,
      ),
      stamp(),
    );
    final stored = tables.putIfAbsent(RemoteTables.guildAchievements, () => <RemoteRow>[]);
    for (final id in evaluated.newlyUnlocked) {
      stored.add(<String, Object?>{
        'guild_id': guildId,
        'achievement_id': id,
        'unlocked_at': evaluated.unlocked[id] ?? stamp(),
      });
    }
  }

  static RemoteRow _refused(String reason) => <String, Object?>{'ok': false, 'reason': reason};

  /// The name, look, and level a roster row copies, as the SQL helper reads them.
  RemoteRow _memberFacts(String userId, [String? fallbackName]) {
    RemoteRow? profile;
    for (final row in tables[RemoteTables.profiles]!) {
      if (row['user_id'] == userId) profile = row;
    }
    num level = 1;
    for (final row in tables[RemoteTables.leaderboard]!) {
      if (row['user_id'] == userId && row['board_key'] == boardTotalLevel) {
        level = _asNum(row['value']);
      }
    }
    final named = profile?['username'];
    return <String, Object?>{
      'username': named is String && named.isNotEmpty
          ? named
          : (fallbackName?.isNotEmpty ?? false)
          ? fallbackName
          : 'Adventurer',
      'appearance_json': profile?['appearance_json'] ?? const <String, Object?>{},
      'total_level': level,
    };
  }

  void _tagProfile(String userId, String? guildId) {
    final profiles = tables[RemoteTables.profiles]!;
    for (var i = 0; i < profiles.length; i++) {
      if (profiles[i]['user_id'] == userId) {
        profiles[i] = <String, Object?>{...profiles[i], 'guild_id': guildId};
      }
    }
  }

  int _rosterSize(String guildId) =>
      tables[RemoteTables.guildMembers]!.where((row) => row['guild_id'] == guildId).length;

  RemoteRow? _guildRow(Object? guildId) {
    for (final row in tables[RemoteTables.guilds]!) {
      if (row['id'] == guildId) return row;
    }
    return null;
  }

  /// Mirrors guild_create_hosted: every row a new guild needs, or none.
  RemoteRow _foundGuild(String userId, RemoteRow wanted) {
    final name = '${wanted['name'] ?? ''}'.trim();
    final tag = '${wanted['tag'] ?? ''}'.trim().toUpperCase();
    if (name.isEmpty || tag.isEmpty) return _refused('Enter a guild name and tag.');
    if (_membershipFor(userId) != null) {
      return _refused('Leave your current guild before creating another.');
    }
    final guilds = tables[RemoteTables.guilds]!;
    if (guilds.any((row) => row['name'] == name || row['tag'] == tag)) {
      return _refused(remoteGuildNameTaken);
    }
    final guild = <String, Object?>{
      ..._defaults(RemoteTables.guilds),
      ...wanted,
      'name': name,
      'tag': tag,
      'leader_id': userId,
    };
    guilds.add(guild);
    final id = guild['id']! as String;
    tables[RemoteTables.guildMembers]!.add(<String, Object?>{
      'guild_id': id,
      'user_id': userId,
      'role': guildRoleLeader,
      'joined_at': stamp(),
      ..._memberFacts(userId),
    });
    _tagProfile(userId, id);
    tables[RemoteTables.guildApplications]!.removeWhere((row) => row['user_id'] == userId);
    tables[RemoteTables.guildGuests]!.removeWhere((row) => row['user_id'] == userId);
    tables[RemoteTables.guildHalls]!.add(guildHallRowFor(GuildHallState.fresh(id)));
    final founderName = '${_memberFacts(userId)['username'] ?? 'Adventurer'}';
    _appendGuildLog(id, <String, Object?>{
      'kind': guildLogKindJoin,
      'actor_user_id': userId,
      'actor_username': founderName,
      'role': guildRoleLeader,
      'message': '$founderName joined the guild.',
    });
    tables[RemoteTables.guildProjects]!.add(<String, Object?>{
      ..._defaults(RemoteTables.guildProjects),
      'guild_id': id,
      'name': guildStorehouseProjectName,
      'description': guildStorehouseProjectDescription,
      'goal_amount': guildStorehouseProjectGoal,
      'contributed': 0,
      'reward_label': guildStorehouseProjectReward,
    });
    tables[RemoteTables.guildChallenges]!.add(<String, Object?>{
      ..._defaults(RemoteTables.guildChallenges),
      'guild_id': id,
      'name': guildMonsterChallengeName,
      'board_key': boardMonstersKilled,
      'goal_value': guildMonsterChallengeGoal,
      'current_value': 0,
    });
    tables.putIfAbsent(RemoteTables.guildPrivateMessages, () => <RemoteRow>[]).add(
      <String, Object?>{'guild_id': id, 'body': '', 'updated_at': stamp(), 'updated_by': null},
    );
    return <String, Object?>{'ok': true, 'guild': guild};
  }

  void _dropGuild(String guildId) {
    tables[RemoteTables.guilds]!.removeWhere((row) => row['id'] == guildId);
    for (final table in <String>[
      RemoteTables.guildMembers,
      RemoteTables.guildApplications,
      RemoteTables.guildGuests,
      RemoteTables.guildHalls,
      RemoteTables.guildProjects,
      RemoteTables.guildChallenges,
      RemoteTables.guildPrivateMessages,
      RemoteTables.guildLogEntries,
    ]) {
      tables[table]!.removeWhere((row) => row['guild_id'] == guildId);
    }
    final profiles = tables[RemoteTables.profiles]!;
    for (var i = 0; i < profiles.length; i++) {
      if (profiles[i]['guild_id'] == guildId) {
        profiles[i] = <String, Object?>{...profiles[i], 'guild_id': null};
      }
    }
  }

  /// Mirrors the Wave E guild functions in supabase/migrations.
  RemoteRow _guildLifecycleRpc(String me, String function, RemoteRow args) {
    final members = tables[RemoteTables.guildMembers]!;
    final guests = tables[RemoteTables.guildGuests]!;
    final applications = tables[RemoteTables.guildApplications]!;

    if (function == RemoteRpcs.guildJoinOpen) {
      final guildId = args['p_guild_id'];
      final guild = _guildRow(guildId);
      if (guild == null) return _refused(remoteGuildMissing);
      if (_membershipFor(me) != null) return _refused('Already in a guild.');
      if (_rosterSize('$guildId') >= guildMaxMembers) {
        return _refused('That guild is full ($guildMaxMembers members).');
      }
      if (guild['join_policy'] != guildJoinOpen) return _refused('That guild takes applications.');
      members.add(<String, Object?>{
        'guild_id': guildId,
        'user_id': me,
        'role': guildRoleRecruit,
        'joined_at': stamp(),
        ..._memberFacts(me),
      });
      applications.removeWhere((row) => row['user_id'] == me && row['guild_id'] == guildId);
      guests.removeWhere((row) => row['user_id'] == me && row['guild_id'] == guildId);
      _tagProfile(me, '$guildId');
      final joiner = '${_memberFacts(me)['username'] ?? 'Adventurer'}';
      _appendGuildLog('$guildId', <String, Object?>{
        'kind': guildLogKindJoin,
        'actor_user_id': me,
        'actor_username': joiner,
        'role': guildRoleRecruit,
        'message': '$joiner joined the guild.',
      });
      return const <String, Object?>{'ok': true, 'joined': true};
    }

    if (function == RemoteRpcs.guildJoinGuest) {
      final guildId = args['p_guild_id'];
      final guild = _guildRow(guildId);
      if (guild == null) return _refused(remoteGuildMissing);
      if (members.any((row) => row['user_id'] == me && row['guild_id'] == guildId)) {
        return _refused('Already a member of that guild.');
      }
      final visiting = guests.where((row) => row['user_id'] == me).firstOrNull;
      if (visiting != null) {
        return _refused(
          visiting['guild_id'] == guildId
              ? 'Already a guest of that guild.'
              : 'Leave your current guest guild first.',
        );
      }
      if (guild['guest_auto_accept'] != true) {
        return _refused('That guild asks guests to request a visit.');
      }
      final facts = _memberFacts(me);
      guests.add(<String, Object?>{
        'guild_id': guildId,
        'user_id': me,
        'username': facts['username'],
        'appearance_json': facts['appearance_json'],
        'joined_at': stamp(),
      });
      applications.removeWhere(
        (row) => row['user_id'] == me && row['guild_id'] == guildId && row['guest'] == true,
      );
      return const <String, Object?>{'ok': true, 'joined': true};
    }

    if (function == RemoteRpcs.guildDecideApplication) {
      final application = applications
          .where((row) => row['id'] == args['p_application_id'])
          .firstOrNull;
      if (application == null) return _refused('Application not found.');
      final guildId = application['guild_id'];
      final guild = _guildRow(guildId);
      if (guild == null) return _refused(remoteGuildMissing);
      final actor = members
          .where((row) => row['user_id'] == me && row['guild_id'] == guildId)
          .firstOrNull;
      if (guild['leader_id'] != me && actor?['role'] != guildRoleOfficer) {
        return _refused('Only the guild leader or an officer can decide applications.');
      }
      applications.remove(application);
      if (args['p_accept'] != true) return const <String, Object?>{'ok': true};

      final applicant = '${application['user_id']}';
      final memberOf = _membershipFor(applicant)?['guild_id'];
      final facts = _memberFacts(applicant, application['username'] as String?);
      if (application['guest'] == true) {
        if (guests.any((row) => row['user_id'] == applicant)) {
          return _refused('Applicant is already a guest elsewhere.');
        }
        if (memberOf == guildId) return _refused('Applicant already joined that guild.');
        guests.add(<String, Object?>{
          'guild_id': guildId,
          'user_id': applicant,
          'username': facts['username'],
          'appearance_json': facts['appearance_json'],
          'joined_at': stamp(),
        });
        return const <String, Object?>{'ok': true};
      }
      if (memberOf != null) return _refused('Applicant already joined another guild.');
      if (_rosterSize('$guildId') >= guildMaxMembers) {
        return _refused('Guild is full ($guildMaxMembers members).');
      }
      members.add(<String, Object?>{
        'guild_id': guildId,
        'user_id': applicant,
        'role': guildRoleRecruit,
        'joined_at': stamp(),
        ...facts,
      });
      guests.removeWhere((row) => row['guild_id'] == guildId && row['user_id'] == applicant);
      _tagProfile(applicant, '$guildId');
      _appendGuildLog('$guildId', <String, Object?>{
        'kind': guildLogKindJoin,
        'actor_user_id': applicant,
        'actor_username': facts['username'] ?? 'Adventurer',
        'role': guildRoleRecruit,
        'message': '${facts['username'] ?? 'Adventurer'} joined the guild.',
      });
      return const <String, Object?>{'ok': true};
    }

    if (function == RemoteRpcs.guildLeave) {
      final membership = _membershipFor(me);
      if (membership == null) return _refused('Not in a guild.');
      final guildId = '${membership['guild_id']}';
      final guild = _guildRow(guildId);
      if (guild != null && guild['leader_id'] == me) {
        if (_rosterSize(guildId) > 1) {
          return _refused('Transfer leadership or remove members before leaving.');
        }
        _dropGuild(guildId);
      } else {
        _appendGuildLog(guildId, <String, Object?>{
          'kind': guildLogKindLeave,
          'actor_user_id': me,
          'actor_username': membership['username'] ?? 'Adventurer',
          'role': membership['role'],
          'message': '${membership['username'] ?? 'Adventurer'} left the guild.',
        });
        members.removeWhere((row) => row['user_id'] == me);
      }
      _tagProfile(me, null);
      return const <String, Object?>{'ok': true};
    }

    // guild_kick
    final guildId = args['p_guild_id'];
    final target = args['p_target'];
    final guild = _guildRow(guildId);
    if (guild == null) return _refused(remoteGuildMissing);
    if (guild['leader_id'] != me) return _refused('Only the leader can remove members.');
    if (target == guild['leader_id']) return _refused('Cannot remove the leader.');
    final kicked = members.firstWhere(
      (row) => row['guild_id'] == guildId && row['user_id'] == target,
      orElse: () => const <String, Object?>{},
    );
    if (kicked.isNotEmpty) {
      _appendGuildLog('$guildId', <String, Object?>{
        'kind': guildLogKindLeave,
        'actor_user_id': target,
        'actor_username': kicked['username'] ?? 'Adventurer',
        'role': kicked['role'],
        'message': '${kicked['username'] ?? 'Adventurer'} left the guild.',
      });
    }
    members.removeWhere((row) => row['guild_id'] == guildId && row['user_id'] == target);
    final profiles = tables[RemoteTables.profiles]!;
    for (var i = 0; i < profiles.length; i++) {
      if (profiles[i]['user_id'] == target && profiles[i]['guild_id'] == guildId) {
        profiles[i] = <String, Object?>{...profiles[i], 'guild_id': null};
      }
    }
    return const <String, Object?>{'ok': true};
  }

  /// The game function's `guild_create`: charge the gold and found the guild together.
  RemoteInvokeResult _foundGuildCommand(String userId, RemoteRow body, RemoteRow saveRow) {
    if (!hostsGuildLifecycleRpcs) {
      return RemoteInvokeResult.failed(_missingRpc('guild_create_hosted'));
    }
    final payload = saveRow['payload'];
    if (payload is! Map) {
      return const RemoteInvokeResult.failed('The cloud save could not be read.');
    }
    final save = parseSave(Map<String, Object?>.from(payload), _clockMs());
    final args = _asMap(body['args']);
    final refusal = createGuildRefusalFor(
      name: '${args['name'] ?? ''}',
      tag: '${args['tag'] ?? ''}',
      goldAvailable: save.gold,
    );
    if (refusal != null) return RemoteInvokeResult.failed(refusal);
    final founded = _foundGuild(userId, <String, Object?>{
      ..._asMap(args['guild']),
      'name': args['name'],
      'tag': args['tag'],
    });
    if (founded['ok'] != true) {
      return RemoteInvokeResult.failed('${founded['reason'] ?? 'The guild was not created.'}');
    }
    final next = save.copyWith(gold: save.gold - guildCreateGoldCost);
    saveRow['payload'] = next.toJson();
    final version = ((saveRow['version'] as num?) ?? 1).toInt() + 1;
    saveRow['version'] = version;
    saveRow['updated_at'] = stamp();
    return RemoteInvokeResult.ok(<String, Object?>{
      'ok': true,
      'phase': 2,
      'action': 'command',
      'command': 'guild_create',
      'save': next.toJson(),
      'version': version,
      'rngState': saveRow['rng_state'] ?? 1,
      'guild': founded['guild'],
    });
  }

  RemoteInvokeResult _blockRpc(String function, RemoteRow args) {
    final me = _current?.userId;
    if (me == null) return const RemoteInvokeResult.failed('Sign in first.');
    final target = args['p_target'];
    if (target is! String || target.isEmpty || target == me) {
      return const RemoteInvokeResult.ok(<String, Object?>{
        'ok': false,
        'reason': 'You cannot ignore yourself.',
      });
    }
    final known = tables[RemoteTables.profiles]!.any((row) => row['user_id'] == target);
    if (!known) {
      return const RemoteInvokeResult.ok(<String, Object?>{
        'ok': false,
        'reason': 'That player was not found.',
      });
    }
    final rows = _socialRows('player_blocks');
    if (function == RemoteRpcs.unblockPlayer) {
      rows.removeWhere((row) => row['user_id'] == me && row['blocked_user_id'] == target);
    } else if (!rows.any((row) => row['user_id'] == me && row['blocked_user_id'] == target)) {
      rows.add(<String, Object?>{'user_id': me, 'blocked_user_id': target, 'created_at': stamp()});
    }
    return const RemoteInvokeResult.ok(<String, Object?>{'ok': true});
  }

  RemoteInvokeResult _listBlocksRpc() {
    final me = _current?.userId;
    if (me == null) return const RemoteInvokeResult.failed('Sign in first.');
    final ids = <String>[
      for (final row in _socialRows('player_blocks'))
        if (row['user_id'] == me && row['blocked_user_id'] is String)
          row['blocked_user_id'] as String,
    ];
    return RemoteInvokeResult.ok(<String, Object?>{'blocked_user_ids': ids});
  }

  RemoteInvokeResult _reportRpc(RemoteRow args) {
    final me = _current?.userId;
    if (me == null) return const RemoteInvokeResult.failed('Sign in first.');
    final target = args['p_target'];
    if (target is! String || target.isEmpty || target == me) {
      return const RemoteInvokeResult.ok(<String, Object?>{
        'ok': false,
        'reason': 'You cannot report yourself.',
      });
    }
    final stored = reportReasonForStorage('${args['p_reason'] ?? ''}');
    if (stored == null) {
      return const RemoteInvokeResult.ok(<String, Object?>{
        'ok': false,
        'reason': 'Choose a reason.',
      });
    }
    final rows = _socialRows('chat_reports');
    final cutoff = _clockMs() - const Duration(days: 1).inMilliseconds;
    var recent = 0;
    for (final row in rows) {
      if (row['reporter_id'] != me) continue;
      final at = DateTime.tryParse('${row['created_at'] ?? ''}');
      if (at != null && at.millisecondsSinceEpoch > cutoff) recent += 1;
    }
    if (recent >= reportsPerDay) {
      return const RemoteInvokeResult.ok(<String, Object?>{
        'ok': false,
        'reason': 'You have sent enough reports today.',
      });
    }
    rows.add(<String, Object?>{
      'id': _nextId('rpt'),
      'reporter_id': me,
      'target_user_id': target,
      'reason': stored,
      'created_at': _clockIso(),
    });
    return const RemoteInvokeResult.ok(<String, Object?>{'ok': true});
  }

  RemoteInvokeResult _usernameAvailableRpc(RemoteRow args) {
    final name = remoteUsername('${args['p_name'] ?? ''}');
    if (name.length < 2) return const RemoteInvokeResult.ok(<String, Object?>{'value': false});
    final me = _current?.userId;
    final taken = tables[RemoteTables.profiles]!.any((row) {
      final username = row['username'];
      return row['user_id'] != me &&
          username is String &&
          username.toLowerCase() == name.toLowerCase();
    });
    return RemoteInvokeResult.ok(<String, Object?>{'value': !taken});
  }

  RemoteInvokeResult _renameUsernameRpc(RemoteRow args) {
    final me = _current;
    if (me == null) return const RemoteInvokeResult.failed('Sign in first.');
    final cleaned = remoteUsername('${args['p_name'] ?? ''}');
    if (cleaned.length < 2) {
      return const RemoteInvokeResult.ok(<String, Object?>{
        'ok': false,
        'reason': 'Enter a name to continue.',
      });
    }
    final profiles = tables[RemoteTables.profiles]!;
    final at = profiles.indexWhere((row) => row['user_id'] == me.userId);
    if (at < 0) {
      return const RemoteInvokeResult.ok(<String, Object?>{
        'ok': false,
        'reason': 'Sign in required.',
      });
    }
    final current = profiles[at];
    final oldName = '${current['username'] ?? ''}';
    if (oldName.toLowerCase() == cleaned.toLowerCase()) {
      return const RemoteInvokeResult.ok(<String, Object?>{'ok': true});
    }
    final taken = profiles.any((row) {
      final username = row['username'];
      return row['user_id'] != me.userId &&
          username is String &&
          username.toLowerCase() == cleaned.toLowerCase();
    });
    if (taken) {
      return const RemoteInvokeResult.ok(<String, Object?>{
        'ok': false,
        'reason': 'That name is taken.',
      });
    }
    final next = <String, Object?>{...current, 'username': cleaned};
    final refusal = _profileGuardRefusal(current, next);
    if (refusal != null) {
      return RemoteInvokeResult.ok(<String, Object?>{'ok': false, 'reason': refusal});
    }
    profiles[at] = next;
    me.username = cleaned;
    return const RemoteInvokeResult.ok(<String, Object?>{'ok': true});
  }

  void _overlaySetLoadout(RemoteRow row, RemoteRow body) {
    final payload = row['payload'];
    if (payload is! Map) return;
    final args = body['args'];
    if (args is! Map) return;
    final next = Map<String, Object?>.from(payload);
    final equipment = next['equipment'];
    final equipmentMap = equipment is Map
        ? Map<String, Object?>.from(equipment.map((key, value) => MapEntry('$key', value)))
        : <String, Object?>{};
    final existing = equipmentMap['slots'];
    final worn = existing is Map
        ? Map<String, Object?>.from(existing.map((key, value) => MapEntry('$key', value)))
        : <String, Object?>{};
    for (final key in worn.keys.toList()) {
      worn[key] = null;
    }
    final desired = args['slots'];
    if (desired is List) {
      for (final entry in desired) {
        if (entry is! Map) continue;
        final slotId = entry['slotId'];
        final itemId = entry['itemId'];
        if (slotId is! String || itemId is! String) continue;
        worn[slotId] = <String, Object?>{
          'itemId': itemId,
          'quantity': entry['quantity'] is num ? entry['quantity'] : 1,
          if (entry['enchantmentId'] is String) 'enchantmentId': entry['enchantmentId'],
          if (entry['favorite'] == true) 'favorite': true,
        };
      }
    }
    equipmentMap['slots'] = worn;
    next['equipment'] = equipmentMap;
    final preset = args['activeEquipmentPresetIndex'];
    if (preset is num) next['activeEquipmentPresetIndex'] = preset;
    row['payload'] = next;
  }

  void _appendGuildLog(String guildId, Map<String, Object?> entry) {
    final incoming = GuildLogEntry.fromJson(<String, Object?>{
      'id': _nextId('glg'),
      'guildId': guildId,
      'createdAt': stamp(),
      ...entry,
    });
    final logs = tables[RemoteTables.guildLogEntries]!;
    final newestRows = [...logs.where((row) => row['guild_id'] == guildId)]
      ..sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
    final newest = newestRows.isEmpty
        ? null
        : GuildLogEntry.fromJson(<String, Object?>{
            'id': newestRows.first['id'],
            'guildId': newestRows.first['guild_id'],
            'kind': newestRows.first['kind'],
            'createdAt': newestRows.first['created_at'],
            'actorUserId': newestRows.first['actor_user_id'],
            'actorUsername': newestRows.first['actor_username'] ?? '',
            'message': newestRows.first['message'] ?? '',
            'gold': newestRows.first['gold'] ?? 0,
            'items': newestRows.first['items'] ?? const <Object?>[],
          });
    final merged = mergeGuildLogDonation(newest, incoming);
    if (merged.merged && merged.entry != null) {
      final at = logs.indexWhere((row) => row['id'] == merged.entry!.id);
      if (at >= 0) {
        logs[at] = <String, Object?>{
          ...logs[at],
          'gold': merged.entry!.gold,
          'items': merged.entry!.items.map((row) => row.toJson()).toList(),
          'message': merged.entry!.message,
        };
        return;
      }
    }
    logs.add(<String, Object?>{
      'id': incoming.id,
      'guild_id': guildId,
      'kind': incoming.kind,
      'created_at': incoming.createdAt,
      'actor_user_id': incoming.actorUserId,
      'actor_username': incoming.actorUsername,
      'role': incoming.role,
      'target_user_id': incoming.targetUserId,
      'target_username': incoming.targetUsername,
      'tier_id': incoming.tierId,
      'message': incoming.message,
      'gold': incoming.gold,
      'items': incoming.items.map((row) => row.toJson()).toList(),
    });
  }

  RemoteRow? _membershipFor(String? userId) {
    if (userId == null) return null;
    for (final row in tables[RemoteTables.guildMembers]!) {
      if (row['user_id'] == userId) return row;
    }
    return null;
  }

  static num _asNum(Object? value) => value is num ? value : num.tryParse('$value') ?? 0;

  static Map<String, Object?> _asMap(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) {
      return <String, Object?>{for (final entry in value.entries) '${entry.key}': entry.value};
    }
    return <String, Object?>{};
  }

  static List<Object?> _asList(Object? value) => value is List<Object?> ? value : const <Object?>[];

  @override
  Future<num?> serverNowMs() async {
    calls.add('serverNowMs');
    final reason = _takeFailure('serverNowMs');
    if (reason != null) return null;
    return nowMs?.call();
  }
}

/// Everything one project holds, as opposed to one client connected to it.
///
/// Split out so [FakeTransport.joining] can hand a second client the same
/// tables, the same accounts, and the same exchange without also handing it the
/// same session.
class _FakeProject {
  final Map<String, List<RemoteRow>> tables = <String, List<RemoteRow>>{
    RemoteTables.profiles: <RemoteRow>[],
    RemoteTables.saves: <RemoteRow>[],
    RemoteTables.leaderboard: <RemoteRow>[],
    RemoteTables.chat: <RemoteRow>[],
    RemoteTables.bountyClaims: <RemoteRow>[],
    RemoteTables.guilds: <RemoteRow>[],
    RemoteTables.guildMembers: <RemoteRow>[],
    RemoteTables.guildApplications: <RemoteRow>[],
    RemoteTables.guildGuests: <RemoteRow>[],
    RemoteTables.guildHalls: <RemoteRow>[],
    RemoteTables.guildAchievements: <RemoteRow>[],
    RemoteTables.guildLogEntries: <RemoteRow>[],
    RemoteTables.guildProjects: <RemoteRow>[],
    RemoteTables.guildChallenges: <RemoteRow>[],
    RemoteTables.guildPrivateMessages: <RemoteRow>[],
    RemoteTables.activityPresence: <RemoteRow>[],
    RemoteTables.friendRequests: <RemoteRow>[],
    RemoteTables.friendships: <RemoteRow>[],
    RemoteTables.pvpSnapshots: <RemoteRow>[],
    RemoteTables.rankedPvpResults: <RemoteRow>[],
  };

  final Map<String, FakeAccount> accounts = <String, FakeAccount>{};
  final List<String> calls = <String>[];
  final List<String> magicLinks = <String>[];
  final Map<String, String> failOnce = <String, String>{};
  bool hostsGuildLifecycleRpcs = true;
  final Set<String> missingColumns = <String>{};
  final Set<String> missingTables = <String>{};
  final List<String> selectedColumns = <String>[];
  final List<String> selectedLikes = <String>[];

  FakeExchange? exchange;
  int stamps = 0;
  int ids = 0;
}

class FakeAccount {
  FakeAccount({required this.userId, required this.email, required this.password, this.username});

  final String userId;
  final String email;
  final String password;

  /// Null for an account created outside the game, which carries no name.
  String? username;
}
