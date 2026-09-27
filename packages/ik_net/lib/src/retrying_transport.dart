/// Retries a dropped browser fetch before the screen is told the read failed.
///
/// Flutter web surfaces a dead `fetch` as `ClientException: Failed to fetch`.
/// That is often a one-shot reset while signup refresh and presence publish
/// share the same host. Trying the same call again recovers the row; hiding
/// the error does not.
library;

import 'remote.dart';
import 'remote_transport.dart';

/// Initial try plus this many repeats when the wire dies before a status.
const int remoteUnreachableAttempts = 3;

/// First repeat is immediate; the last waits so a reset can finish.
Future<void> defaultRemoteRetryDelay(int failedAttempt) {
  if (failedAttempt <= 1) return Future<void>.value();
  return Future<void>.delayed(Duration(milliseconds: 150 * (failedAttempt - 1)));
}

/// [RemoteTransport] that repeats an unreachable call a few times.
class RetryingTransport implements RemoteTransport {
  RetryingTransport(this.inner, {this.attempts = remoteUnreachableAttempts, this.delay});

  final RemoteTransport inner;
  final int attempts;
  final Future<void> Function(int failedAttempt)? delay;

  Future<T> _retry<T>(Future<T> Function() action, String? Function(T value) reasonOf) async {
    var last = await action();
    for (var failed = 1; failed < attempts; failed++) {
      final reason = reasonOf(last);
      if (reason == null || !isUnreachableRemoteError(reason)) return last;
      await (delay ?? defaultRemoteRetryDelay)(failed);
      last = await action();
    }
    return last;
  }

  @override
  Future<RemoteAuthResult> signUp({
    required String email,
    required String password,
    required String username,
  }) {
    return _retry(
      () => inner.signUp(email: email, password: password, username: username),
      (result) => result.reason,
    );
  }

  @override
  Future<RemoteAuthResult> signIn({required String email, required String password}) {
    return _retry(() => inner.signIn(email: email, password: password), (result) => result.reason);
  }

  @override
  Future<String?> updateAuthUsername(String username) {
    return _retry(() => inner.updateAuthUsername(username), (reason) => reason);
  }

  @override
  Future<String?> sendMagicLink(String email) {
    return _retry(() => inner.sendMagicLink(email), (reason) => reason);
  }

  @override
  Future<void> signOut() => inner.signOut();

  @override
  Future<String?> refreshSession() {
    return _retry(() => inner.refreshSession(), (reason) => reason);
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
    return _retry(
      () => inner.select(
        table,
        columns: columns,
        equals: equals,
        like: like,
        orderBy: orderBy,
        ascending: ascending,
        limit: limit,
      ),
      (result) => result.reason,
    );
  }

  @override
  Future<String?> upsert(String table, List<RemoteRow> rows, {String? onConflict}) {
    return _retry(() => inner.upsert(table, rows, onConflict: onConflict), (reason) => reason);
  }

  @override
  Future<RemoteQueryResult> insert(String table, RemoteRow row, {required String columns}) {
    return _retry(() => inner.insert(table, row, columns: columns), (result) => result.reason);
  }

  @override
  Future<String?> update(String table, RemoteRow row, {required Map<String, Object?> equals}) {
    return _retry(() => inner.update(table, row, equals: equals), (reason) => reason);
  }

  @override
  Future<String?> delete(String table, {required Map<String, Object?> equals}) {
    return _retry(() => inner.delete(table, equals: equals), (reason) => reason);
  }

  @override
  Future<RemoteInvokeResult> invoke(String function, RemoteRow body) {
    return _retry(() => inner.invoke(function, body), (result) => result.reason);
  }

  @override
  Future<num?> serverNowMs() => inner.serverNowMs();
}
