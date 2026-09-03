import 'package:ik_net/ik_net.dart';
import 'package:supabase/supabase.dart';

/// `ik_net`'s transport, spoken over the Dart `supabase` package (no Flutter).
///
/// Mirrors `app_flutter/lib/src/net/supabase_transport.dart` so the live bot
/// and the client agree about the same hosted project.
class DartSupabaseTransport implements RemoteTransport {
  const DartSupabaseTransport(this.client);

  /// Opens a client against [config]. Call once before the first auth request.
  static DartSupabaseTransport connect(RemoteBackendConfig config) {
    return DartSupabaseTransport(
      SupabaseClient(
        config.url,
        config.anonKey,
        authOptions: const AuthClientOptions(autoRefreshToken: true),
      ),
    );
  }

  final SupabaseClient client;

  @override
  Future<RemoteAuthResult> signUp({
    required String email,
    required String password,
    required String username,
  }) async {
    try {
      final response = await client.auth.signUp(
        email: email,
        password: password,
        data: <String, Object?>{'username': username},
      );
      final user = response.user;
      if (user == null) return const RemoteAuthResult.failed(remoteSignUpFailed);
      return RemoteAuthResult.ok(
        RemoteAccount(
          userId: user.id,
          email: user.email,
          username: username,
          accessToken: response.session?.accessToken,
        ),
      );
    } on AuthException catch (error) {
      return RemoteAuthResult.failed(friendlyRemoteError(error.message));
    } on Object catch (error) {
      return RemoteAuthResult.failed(friendlyRemoteError('$error'));
    }
  }

  @override
  Future<RemoteAuthResult> signIn({required String email, required String password}) async {
    try {
      final response = await client.auth.signInWithPassword(email: email, password: password);
      final user = response.user;
      if (user == null) return const RemoteAuthResult.failed(remoteSignInFailed);
      final name = user.userMetadata?['username'];
      return RemoteAuthResult.ok(
        RemoteAccount(
          userId: user.id,
          email: user.email,
          username: name is String ? name : null,
          accessToken: response.session?.accessToken,
        ),
      );
    } on AuthException catch (error) {
      return RemoteAuthResult.failed(friendlyRemoteError(error.message));
    } on Object catch (error) {
      return RemoteAuthResult.failed(friendlyRemoteError('$error'));
    }
  }

  @override
  Future<String?> updateAuthUsername(String username) async {
    try {
      await client.auth.updateUser(UserAttributes(data: <String, Object?>{'username': username}));
      return null;
    } on AuthException catch (error) {
      return friendlyRemoteError(error.message);
    } on Object catch (error) {
      return friendlyRemoteError('$error');
    }
  }

  @override
  Future<String?> sendMagicLink(String email) async {
    try {
      await client.auth.signInWithOtp(email: email);
      return null;
    } on AuthException catch (error) {
      return friendlyRemoteError(error.message);
    } on Object catch (error) {
      return friendlyRemoteError('$error');
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await client.auth.signOut();
    } on Object {
      // The local session is already gone.
    }
  }

  @override
  Future<String?> refreshSession() async {
    try {
      await client.auth.refreshSession();
      return null;
    } on AuthException catch (error) {
      return isExpiredAuthError(error.message)
          ? remoteSignInAgain
          : friendlyRemoteError(error.message);
    } on Object catch (error) {
      return friendlyRemoteError('$error');
    }
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
    return _retryAuth(() async {
      var filter = client.from(table).select(columns);
      for (final entry in equals.entries) {
        filter = filter.eq(entry.key, entry.value as Object);
      }
      for (final entry in like.entries) {
        filter = filter.like(entry.key, entry.value);
      }
      final ordered = orderBy == null ? filter : filter.order(orderBy, ascending: ascending);
      final rows = await (limit == null ? ordered : ordered.limit(limit));
      return RemoteQueryResult.ok(rows.map((row) => Map<String, Object?>.from(row)).toList());
    }, RemoteQueryResult.failed);
  }

  @override
  Future<String?> upsert(String table, List<RemoteRow> rows, {String? onConflict}) async {
    if (rows.isEmpty) return null;
    return _retryAuth(() async {
      await client.from(table).upsert(rows, onConflict: onConflict);
      return null;
    }, (reason) => reason);
  }

  @override
  Future<RemoteQueryResult> insert(String table, RemoteRow row, {required String columns}) {
    return _retryAuth(() async {
      final written = await client.from(table).insert(row).select(columns);
      return RemoteQueryResult.ok(
        written.map((stored) => Map<String, Object?>.from(stored)).toList(),
      );
    }, RemoteQueryResult.failed);
  }

  @override
  Future<String?> update(
    String table,
    RemoteRow row, {
    required Map<String, Object?> equals,
  }) async {
    if (equals.isEmpty) return 'An update needs a filter.';
    if (row.isEmpty) return null;
    return _retryAuth(() async {
      var filter = client.from(table).update(row);
      for (final entry in equals.entries) {
        filter = filter.eq(entry.key, entry.value as Object);
      }
      await filter;
      return null;
    }, (reason) => reason);
  }

  @override
  Future<String?> delete(String table, {required Map<String, Object?> equals}) async {
    if (equals.isEmpty) return 'A delete needs a filter.';
    return _retryAuth(() async {
      var filter = client.from(table).delete();
      for (final entry in equals.entries) {
        filter = filter.eq(entry.key, entry.value as Object);
      }
      await filter;
      return null;
    }, (reason) => reason);
  }

  @override
  Future<RemoteInvokeResult> invoke(String function, RemoteRow body) {
    return _retryAuth(() async {
      final response = await client.functions.invoke(function, body: body);
      final data = response.data;
      return RemoteInvokeResult.ok(data is Map ? Map<String, Object?>.from(data) : null);
    }, RemoteInvokeResult.failed);
  }

  @override
  Future<num?> serverNowMs() {
    return _retryAuth(() async {
      final value = await client.rpc<dynamic>('server_now_ms');
      if (value is num) return value;
      if (value is String) return num.tryParse(value);
      return null;
    }, (_) => null);
  }

  Future<T> _retryAuth<T>(Future<T> Function() action, T Function(String reason) onFail) async {
    try {
      return await action();
    } catch (error) {
      final message = _authErrorMessage(error);
      if (!isExpiredAuthError(message)) {
        return onFail(friendlyRemoteError(message ?? '$error'));
      }
      final refreshed = await refreshSession();
      if (refreshed != null) return onFail(refreshed);
      try {
        return await action();
      } catch (retried) {
        return onFail(friendlyRemoteError(_authErrorMessage(retried) ?? '$retried'));
      }
    }
  }

  String? _authErrorMessage(Object error) {
    if (error is AuthException) return error.message;
    if (error is PostgrestException) return error.message;
    if (error is FunctionException) return '${error.details ?? error.reasonPhrase}';
    return error.toString();
  }
}
