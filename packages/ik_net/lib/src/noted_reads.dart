/// A transport that remembers why a read was refused.
///
/// Every read in the hosted service answers with rows or with nothing, because
/// a screen missing one of its lists should still draw the others. That leaves
/// "this guild has no members yet" looking exactly like "the table this build
/// reads does not exist on your project yet", which is how a skipped migration
/// turns into a game that appears to do nothing.
///
/// Noticing the refusal in one place fixes that without every caller growing a
/// second return value: the reads still answer with what arrived, and the
/// screen asks afterwards whether anything went wrong.
library;

import 'remote.dart';
import 'remote_transport.dart';

class NotedReads implements RemoteTransport {
  NotedReads(this.inner);

  final RemoteTransport inner;

  /// The first refusal since it was last taken. First, not last, because the
  /// earliest failure is usually the cause and the rest are its echoes.
  String? _problem;

  /// The refusal to show, cleared so one bad read is not reported forever.
  String? take() {
    final held = _problem;
    _problem = null;
    return held;
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
    final result = await inner.select(
      table,
      columns: columns,
      equals: equals,
      orderBy: orderBy,
      ascending: ascending,
      limit: limit,
    );
    final reason = result.reason;
    if (reason != null) _problem ??= friendlyRemoteError(reason);
    return result;
  }

  @override
  Future<RemoteAuthResult> signUp({
    required String email,
    required String password,
    required String username,
  }) => inner.signUp(email: email, password: password, username: username);

  @override
  Future<RemoteAuthResult> signIn({required String email, required String password}) =>
      inner.signIn(email: email, password: password);

  @override
  Future<String?> updateAuthUsername(String username) => inner.updateAuthUsername(username);

  @override
  Future<String?> sendMagicLink(String email) => inner.sendMagicLink(email);

  @override
  Future<void> signOut() => inner.signOut();

  @override
  Future<String?> upsert(String table, List<RemoteRow> rows, {String? onConflict}) =>
      inner.upsert(table, rows, onConflict: onConflict);

  @override
  Future<RemoteQueryResult> insert(String table, RemoteRow row, {required String columns}) =>
      inner.insert(table, row, columns: columns);

  @override
  Future<String?> update(String table, RemoteRow row, {required Map<String, Object?> equals}) =>
      inner.update(table, row, equals: equals);

  @override
  Future<String?> delete(String table, {required Map<String, Object?> equals}) =>
      inner.delete(table, equals: equals);

  @override
  Future<RemoteInvokeResult> invoke(String function, RemoteRow body) =>
      inner.invoke(function, body);
}
