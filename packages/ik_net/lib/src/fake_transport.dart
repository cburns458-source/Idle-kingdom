import 'remote.dart';
import 'remote_transport.dart';

/// A remote backend held in memory, standing in for the hosted one.
///
/// It is deliberately literal about the parts the service depends on — upserts
/// that replace on a conflict key, reads that filter and order, and a join from
/// a leaderboard row to its profile — because those are the assumptions that
/// would otherwise only be checked against a live project.
class FakeTransport implements RemoteTransport {
  FakeTransport({this.startIso = '2026-08-13T00:00:00.000Z'});

  /// The instant the first stamped row is written at.
  final String startIso;

  /// A fresh timestamp, a second later each time.
  ///
  /// Rows a real table stamps for itself are microseconds apart, which is what
  /// makes `order by created_at` mean anything; identical stamps would leave the
  /// order of a board undefined and a test passing by luck.
  String stamp() {
    final at = DateTime.parse(startIso).add(Duration(seconds: _stamps++));
    return at.toUtc().toIso8601String();
  }

  int _stamps = 0;

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
  };

  /// Accounts by email, as an auth provider would hold them.
  final Map<String, FakeAccount> accounts = <String, FakeAccount>{};

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
  final List<String> calls = <String>[];

  /// Emails a magic link was requested for.
  final List<String> magicLinks = <String>[];

  /// The reason the next call of any kind should fail with, used once.
  String? failNextWith;

  /// Reasons keyed by the call they refuse, such as `insert:bazaar_posts`, each
  /// used once. For making one step of a sequence fail rather than the next one.
  final Map<String, String> failOnce = <String, String>{};

  /// Set to answer the send-chat function with something unusable.
  RemoteRow? chatFunctionReply;

  bool signedOut = false;
  int _ids = 0;
  FakeAccount? _current;

  String _nextId(String prefix) => '${prefix}_${(_ids += 1).toString().padLeft(4, '0')}';

  String? _takeFailure(String call) {
    final named = failOnce.remove(call);
    if (named != null) return named;
    final reason = failNextWith;
    failNextWith = null;
    return reason;
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
  Future<RemoteQueryResult> select(
    String table, {
    required String columns,
    Map<String, Object?> equals = const <String, Object?>{},
    String? orderBy,
    bool ascending = true,
    int? limit,
  }) async {
    calls.add('select:$table');
    final reason = _takeFailure('select:$table');
    if (reason != null) return RemoteQueryResult.failed(reason);

    var rows = (tables[table] ?? const <RemoteRow>[])
        .where((row) => equals.entries.every((filter) => row[filter.key] == filter.value))
        .map((row) => <String, Object?>{...row})
        .toList();

    if (columns.contains('profiles(')) {
      for (final row in rows) {
        row['profiles'] = _profileJoin(row['user_id']);
      }
    }
    if (orderBy != null) {
      rows.sort((a, b) => _compare(a[orderBy], b[orderBy]) * (ascending ? 1 : -1));
    }
    if (limit != null && rows.length > limit) rows = rows.sublist(0, limit);
    return RemoteQueryResult.ok(rows);
  }

  /// The profile a leaderboard read joins in, with its guild name folded in.
  RemoteRow? _profileJoin(Object? userId) {
    for (final profile in tables[RemoteTables.profiles]!) {
      if (profile['user_id'] != userId) continue;
      return <String, Object?>{
        'username': profile['username'],
        'appearance_json': profile['appearance_json'],
        'guild_id': profile['guild_id'],
        'guilds': profile['guild_name'] == null
            ? null
            : <String, Object?>{'name': profile['guild_name']},
      };
    }
    return null;
  }

  static int _compare(Object? a, Object? b) {
    if (a is num && b is num) return a.compareTo(b);
    return '$a'.compareTo('$b');
  }

  @override
  Future<String?> upsert(String table, List<RemoteRow> rows, {String? onConflict}) async {
    calls.add('upsert:$table');
    final reason = _takeFailure('upsert:$table');
    if (reason != null) return reason;

    if (table == RemoteTables.saves) {
      final blocked = _playSessionRefusal(rows);
      if (blocked != null) return blocked;
    }

    final key = onConflict?.split(',').map((part) => part.trim()).toList() ?? _keys[table]!;
    final stored = tables.putIfAbsent(table, () => <RemoteRow>[]);
    for (final row in rows) {
      final at = stored.indexWhere((existing) => key.every((k) => existing[k] == row[k]));
      if (at >= 0) {
        stored[at] = <String, Object?>{...stored[at], ...row};
      } else {
        stored.add(<String, Object?>{...row});
      }
    }
    return null;
  }

  @override
  Future<RemoteQueryResult> insert(String table, RemoteRow row, {required String columns}) async {
    calls.add('insert:$table');
    final reason = _takeFailure('insert:$table');
    if (reason != null) return RemoteQueryResult.failed(reason);

    final key = _keys[table]!;
    final stored = tables.putIfAbsent(table, () => <RemoteRow>[]);
    final written = <String, Object?>{..._defaults(table), ...row};
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
    if (equals.isEmpty) return 'An update needs a filter.';

    final stored = tables.putIfAbsent(table, () => <RemoteRow>[]);
    for (var i = 0; i < stored.length; i++) {
      if (!equals.entries.every((filter) => stored[i][filter.key] == filter.value)) continue;
      stored[i] = <String, Object?>{...stored[i], ...row};
    }
    return null;
  }

  @override
  Future<String?> delete(String table, {required Map<String, Object?> equals}) async {
    calls.add('delete:$table');
    final reason = _takeFailure('delete:$table');
    if (reason != null) return reason;
    if (equals.isEmpty) return 'A delete needs a filter.';

    final stored = tables.putIfAbsent(table, () => <RemoteRow>[]);
    stored.removeWhere((row) => equals.entries.every((filter) => row[filter.key] == filter.value));
    return null;
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

  @override
  Future<RemoteInvokeResult> invoke(String function, RemoteRow body) async {
    calls.add('invoke:$function');
    final reason = _takeFailure('invoke:$function');
    if (reason != null) return RemoteInvokeResult.failed(reason);
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
      'username': sender.username ?? 'Adventurer',
      'body': body['body'],
      'created_at': stamp(),
    };
    tables[RemoteTables.chat]!.add(row);
    return RemoteInvokeResult.ok(<String, Object?>{...row});
  }
}

class FakeAccount {
  FakeAccount({required this.userId, required this.email, required this.password, this.username});

  final String userId;
  final String email;
  final String password;

  /// Null for an account created outside the game, which carries no name.
  final String? username;
}
