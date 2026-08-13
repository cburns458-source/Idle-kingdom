import 'package:ik_net/ik_net.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The Supabase project this build talks to, or null for local play.
///
/// Supplied at build time the way the web client reads its Vite variables:
/// `flutter run --dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…`.
/// A build with neither runs entirely on the device, which is the default.
RemoteBackendConfig? remoteBackendConfigFromEnvironment() => RemoteBackendConfig.from(
  url: const String.fromEnvironment('SUPABASE_URL'),
  anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
);

/// `ik_net`'s transport, spoken over `supabase_flutter`.
///
/// Nothing here decides anything: the service says which table, which columns,
/// and which order, and this turns that into a query and hands the rows back.
/// That is what keeps the two clients agreeing about a backend neither of them
/// can see.
class SupabaseTransport implements RemoteTransport {
  const SupabaseTransport(this.client);

  /// Signs the project in and returns a transport onto it.
  ///
  /// Call once at startup, before the first screen asks for a session.
  static Future<SupabaseTransport> connect(RemoteBackendConfig config) async {
    // Supabase renamed the client-side key from "anon" to "publishable"; it is
    // the same value the web client passes as its anon key.
    final supabase = await Supabase.initialize(url: config.url, publishableKey: config.anonKey);
    return SupabaseTransport(supabase.client);
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
      return RemoteAuthResult.failed(error.message);
    } on Object catch (error) {
      return RemoteAuthResult.failed('$error');
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
      return RemoteAuthResult.failed(error.message);
    } on Object catch (error) {
      return RemoteAuthResult.failed('$error');
    }
  }

  @override
  Future<String?> sendMagicLink(String email) async {
    try {
      await client.auth.signInWithOtp(email: email);
      return null;
    } on AuthException catch (error) {
      return error.message;
    } on Object catch (error) {
      return '$error';
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await client.auth.signOut();
    } on Object {
      // The local session is already gone; a failed round trip does not bring
      // the player back.
    }
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
    try {
      var filter = client.from(table).select(columns);
      for (final entry in equals.entries) {
        filter = filter.eq(entry.key, entry.value as Object);
      }
      // Ordering and limiting have to come after every filter, which is why the
      // query is only narrowed once the loop above is done.
      final ordered = orderBy == null ? filter : filter.order(orderBy, ascending: ascending);
      final rows = await (limit == null ? ordered : ordered.limit(limit));
      return RemoteQueryResult.ok(rows.map((row) => Map<String, Object?>.from(row)).toList());
    } on PostgrestException catch (error) {
      return RemoteQueryResult.failed(error.message);
    } on Object catch (error) {
      return RemoteQueryResult.failed('$error');
    }
  }

  @override
  Future<String?> upsert(String table, List<RemoteRow> rows, {String? onConflict}) async {
    if (rows.isEmpty) return null;
    try {
      await client.from(table).upsert(rows, onConflict: onConflict);
      return null;
    } on PostgrestException catch (error) {
      return error.message;
    } on Object catch (error) {
      return '$error';
    }
  }

  @override
  Future<RemoteQueryResult> insert(String table, RemoteRow row, {required String columns}) async {
    try {
      final written = await client.from(table).insert(row).select(columns);
      return RemoteQueryResult.ok(
        written.map((stored) => Map<String, Object?>.from(stored)).toList(),
      );
    } on PostgrestException catch (error) {
      return RemoteQueryResult.failed(error.message);
    } on Object catch (error) {
      return RemoteQueryResult.failed('$error');
    }
  }

  @override
  Future<RemoteInvokeResult> invoke(String function, RemoteRow body) async {
    try {
      final response = await client.functions.invoke(function, body: body);
      final data = response.data;
      return RemoteInvokeResult.ok(data is Map ? Map<String, Object?>.from(data) : null);
    } on FunctionException catch (error) {
      return RemoteInvokeResult.failed('${error.details ?? error.reasonPhrase}');
    } on Object catch (error) {
      return RemoteInvokeResult.failed('$error');
    }
  }
}
