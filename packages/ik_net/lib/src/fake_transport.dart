import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

import 'cloud_save.dart';
import 'fake_exchange.dart';
import 'guild_rules.dart';
import 'remote.dart';
import 'remote_guilds.dart';
import 'remote_service.dart';
import 'remote_transport.dart';
import 'results.dart';
import 'types.dart';

/// Writes a hosted save the way the game function would, then loads its version.
Future<CloudSyncResult> seedHostedSave(
  RemoteMultiplayerService service,
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

  /// How many times [failNextWith] applies before it clears. Defaults to one.
  int failNextRepeats = 1;

  /// Reasons keyed by the call they refuse, such as `insert:bazaar_posts`, each
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
  FakeExchange get exchange =>
      _project.exchange ??= FakeExchange(saves: tables[RemoteTables.saves]!, stamp: stamp);

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
    for (final column in missingColumns) {
      if (named.contains(column)) return 'column $table.$column does not exist';
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
    RemoteTables.bazaarPosts: <String>['id'],
    RemoteTables.guilds: <String>['id'],
    RemoteTables.guildMembers: <String>['guild_id', 'user_id'],
    RemoteTables.guildApplications: <String>['guild_id', 'user_id'],
    RemoteTables.guildGuests: <String>['guild_id', 'user_id'],
    RemoteTables.guildHalls: <String>['guild_id'],
    RemoteTables.guildProjects: <String>['id'],
    RemoteTables.guildChallenges: <String>['id'],
    RemoteTables.activityPresence: <String>['user_id'],
    RemoteTables.friendRequests: <String>['from_user_id', 'to_user_id'],
    RemoteTables.friendships: <String>['user_a', 'user_b'],
    RemoteTables.pvpSnapshots: <String>['user_id'],
  };

  /// Columns a table holds unique beyond its key, so an insert can lose a race.
  static const Map<String, List<String>> _unique = <String, List<String>>{
    RemoteTables.guilds: <String>['name', 'tag'],
  };

  /// The columns a table fills in for itself, the way a default does.
  RemoteRow _defaults(String table) => switch (table) {
    RemoteTables.bountyClaims => <String, Object?>{'claimed_at': stamp()},
    RemoteTables.bazaarPosts => <String, Object?>{'id': _nextId('bzr'), 'created_at': stamp()},
    RemoteTables.guilds => <String, Object?>{'id': _nextId('gld'), 'created_at': stamp()},
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

    if (isPendingAccountUsername(oldName)) {
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
    final hallCommand = _applyGuildHallCommand(caller.userId, body, row);
    if (hallCommand != null) return hallCommand;
    final version = ((row['version'] as num?) ?? 1).toInt() + 1;
    row['version'] = version;
    row['updated_at'] = stamp();
    return RemoteInvokeResult.ok(<String, Object?>{
      'ok': true,
      'phase': 2,
      'action': action,
      'save': row['payload'],
      'version': version,
      'rngState': row['rng_state'] ?? 1,
    });
  }

  RemoteInvokeResult? _applyGuildHallCommand(String userId, RemoteRow body, RemoteRow saveRow) {
    final command = body['command'] as String? ?? '';
    if (command != 'guild_pay_hall_debt' &&
        command != 'guild_donate_hall_item' &&
        command != 'guild_withdraw_hall_item') {
      return null;
    }
    final membership = _membershipFor(userId);
    if (membership == null) return const RemoteInvokeResult.failed('Join a guild first.');
    final halls = tables[RemoteTables.guildHalls]!;
    final at = halls.indexWhere((row) => row['guild_id'] == membership['guild_id']);
    if (at < 0) return const RemoteInvokeResult.failed('Guild hall not found.');
    final hall = guildHallFrom(halls[at]);
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
    final GuildHallActionResult result;
    if (command == 'guild_pay_hall_debt') {
      result = payGuildHallDebt(hall, userId, save, _asNum(args['amount']));
    } else if (command == 'guild_donate_hall_item') {
      result = donateToGuildHall(
        hall,
        save,
        _asNum(args['inventoryIndex']).toInt(),
        _asNum(args['quantity']),
      );
    } else {
      result = const GuildHallActionResult.failed('Withdraw is not available in this stand-in.');
    }
    if (!result.ok) return RemoteInvokeResult.failed(result.reason ?? 'Guild hall action failed.');
    halls[at] = <String, Object?>{...halls[at], ...guildHallRowFor(result.hall!)};
    final next = result.save ?? save;
    saveRow['payload'] = next.toJson();
    final version = ((saveRow['version'] as num?) ?? 1).toInt() + 1;
    saveRow['version'] = version;
    saveRow['updated_at'] = stamp();
    return RemoteInvokeResult.ok(<String, Object?>{
      'ok': true,
      'phase': 2,
      'save': next.toJson(),
      'version': version,
      'rngState': saveRow['rng_state'] ?? 1,
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

      return RemoteInvokeResult.failed('No such function: $function');
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
    RemoteTables.bazaarPosts: <RemoteRow>[],
    RemoteTables.guilds: <RemoteRow>[],
    RemoteTables.guildMembers: <RemoteRow>[],
    RemoteTables.guildApplications: <RemoteRow>[],
    RemoteTables.guildGuests: <RemoteRow>[],
    RemoteTables.guildHalls: <RemoteRow>[],
    RemoteTables.guildProjects: <RemoteRow>[],
    RemoteTables.guildChallenges: <RemoteRow>[],
    RemoteTables.activityPresence: <RemoteRow>[],
    RemoteTables.friendRequests: <RemoteRow>[],
    RemoteTables.friendships: <RemoteRow>[],
    RemoteTables.pvpSnapshots: <RemoteRow>[],
  };

  final Map<String, FakeAccount> accounts = <String, FakeAccount>{};
  final List<String> calls = <String>[];
  final List<String> magicLinks = <String>[];
  final Map<String, String> failOnce = <String, String>{};
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
