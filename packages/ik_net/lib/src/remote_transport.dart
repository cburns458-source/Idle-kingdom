/// The wire a remote backend is reached over.
///
/// `ik_net` decides what to ask for and how to read the answer; a client decides
/// how the bytes travel. Keeping the two apart is what lets the Flutter app use
/// Supabase, the web app use its own JavaScript client, and a test use a table
/// held in memory, all against the same service.
library;

import 'remote.dart';

/// One account as an auth provider describes it.
class RemoteAccount {
  const RemoteAccount({required this.userId, this.email, this.username, this.accessToken});

  final String userId;

  /// The address on the account, which may differ from the one just typed.
  final String? email;

  /// The name the account was created with, absent for accounts made elsewhere.
  final String? username;
  final String? accessToken;
}

class RemoteAuthResult {
  const RemoteAuthResult.ok(RemoteAccount this.account) : reason = null;

  const RemoteAuthResult.failed(this.reason) : account = null;

  final RemoteAccount? account;
  final String? reason;

  bool get ok => reason == null;
}

/// Rows a read returned, or why it could not be read.
class RemoteQueryResult {
  const RemoteQueryResult.ok(List<RemoteRow> this.rows) : reason = null;

  const RemoteQueryResult.failed(this.reason) : rows = null;

  final List<RemoteRow>? rows;
  final String? reason;

  bool get ok => reason == null;

  /// The first row, or null when the read matched nothing.
  RemoteRow? get single => (rows ?? const <RemoteRow>[]).firstOrNull;
}

class RemoteInvokeResult {
  const RemoteInvokeResult.ok(this.data) : reason = null;

  const RemoteInvokeResult.failed(this.reason) : data = null;

  final RemoteRow? data;
  final String? reason;

  bool get ok => reason == null;
}

/// What a remote backend has to be able to do.
///
/// Deliberately narrow: these are the calls the TypeScript client makes, so a
/// transport is a thin adapter rather than a second backend.
abstract interface class RemoteTransport {
  Future<RemoteAuthResult> signUp({
    required String email,
    required String password,
    required String username,
  });

  Future<RemoteAuthResult> signIn({required String email, required String password});

  /// Writes [username] onto the signed-in account's auth metadata.
  Future<String?> updateAuthUsername(String username);

  /// Sends a one-time sign-in link. Returns null when it went out.
  Future<String?> sendMagicLink(String email);

  Future<void> signOut();

  /// Mints a new access token from the stored refresh token.
  ///
  /// Returns null when the session is still good or was refreshed. A reason
  /// means the player has to sign in again; the local character stays put.
  Future<String?> refreshSession();

  Future<RemoteQueryResult> select(
    String table, {
    required String columns,
    Map<String, Object?> equals = const <String, Object?>{},
    Map<String, String> like = const <String, String>{},
    String? orderBy,
    bool ascending = true,
    int? limit,
  });

  /// Writes [rows], treating [onConflict] as the key that makes it an update.
  /// Returns null on success, or the reason it was refused.
  Future<String?> upsert(String table, List<RemoteRow> rows, {String? onConflict});

  /// Adds [row], failing rather than replacing when it is already there.
  ///
  /// This is how a first-come-first-served race is settled: whoever loses is
  /// told so by the refusal, instead of quietly overwriting the winner. The
  /// stored row is returned so the caller can show what actually landed.
  Future<RemoteQueryResult> insert(String table, RemoteRow row, {required String columns});

  /// Changes the columns in [row] on every row matching [equals].
  ///
  /// Separate from [upsert] because an update is the only write a guild's own
  /// officers are allowed: a row they may edit is not a row they may create.
  Future<String?> update(String table, RemoteRow row, {required Map<String, Object?> equals});

  /// Removes every row matching [equals]. Returns null when it went through.
  ///
  /// Never called without a filter: leaving a guild deletes one roster row, not
  /// a roster.
  Future<String?> delete(String table, {required Map<String, Object?> equals});

  Future<RemoteInvokeResult> invoke(String function, RemoteRow body);

  /// Server wall clock in milliseconds, or null when the project cannot answer.
  Future<num?> serverNowMs();
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
