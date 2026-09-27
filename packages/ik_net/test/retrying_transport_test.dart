import 'package:ik_net/ik_net.dart';
import 'package:ik_net/testing.dart';
import 'package:test/test.dart';

void main() {
  test('repeats a dropped select and then returns the rows', () async {
    final inner = FakeTransport();
    inner.failOnce['select:${RemoteTables.profiles}'] =
        'ClientException: Failed to fetch, uri=https://example.supabase.co/rest/v1/profiles';

    final transport = RetryingTransport(inner, delay: (_) async {});
    final result = await transport.select(RemoteTables.profiles, columns: 'user_id');

    expect(result.ok, isTrue);
    expect(inner.calls.where((call) => call == 'select:${RemoteTables.profiles}'), hasLength(2));
  });

  test('gives up after the last unreachable attempt', () async {
    final inner = FakeTransport();
    inner.failNextRepeats = remoteUnreachableAttempts;
    inner.failNextWith =
        'ClientException: Failed to fetch, uri=https://example.supabase.co/rest/v1/profiles';

    final transport = RetryingTransport(inner, delay: (_) async {});
    final result = await transport.select(RemoteTables.profiles, columns: 'user_id');

    expect(result.ok, isFalse);
    expect(isUnreachableRemoteError(result.reason), isTrue);
    expect(
      inner.calls.where((call) => call == 'select:${RemoteTables.profiles}'),
      hasLength(remoteUnreachableAttempts),
    );
  });

  test('does not retry a skipped-migration refusal', () async {
    final inner = FakeTransport();
    inner.failNextWith = 'column leaderboard_snapshots.value_secondary does not exist';

    final transport = RetryingTransport(inner, delay: (_) async {});
    final result = await transport.select(RemoteTables.leaderboard, columns: 'value_secondary');

    expect(result.ok, isFalse);
    expect(result.reason, contains('value_secondary'));
    expect(inner.calls.where((call) => call == 'select:${RemoteTables.leaderboard}'), hasLength(1));
  });
}
