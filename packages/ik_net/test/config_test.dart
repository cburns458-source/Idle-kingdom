import 'package:ik_net/ik_net.dart';
import 'package:test/test.dart';

void main() {
  test('keeps a project origin unchanged', () {
    expect(normalizeRemoteBackendUrl('https://abcd.supabase.co'), 'https://abcd.supabase.co');
  });

  test('strips the REST and Auth suffixes the dashboard copies', () {
    expect(
      normalizeRemoteBackendUrl('https://abcd.supabase.co/rest/v1'),
      'https://abcd.supabase.co',
    );
    expect(
      normalizeRemoteBackendUrl('https://abcd.supabase.co/rest/v1/'),
      'https://abcd.supabase.co',
    );
    expect(
      normalizeRemoteBackendUrl('https://abcd.supabase.co/auth/v1'),
      'https://abcd.supabase.co',
    );
    expect(
      normalizeRemoteBackendUrl('https://abcd.supabase.co/functions/v1'),
      'https://abcd.supabase.co',
    );
    expect(
      normalizeRemoteBackendUrl('https://abcd.supabase.co/storage/v1'),
      'https://abcd.supabase.co',
    );
  });

  test('explains the PostgREST invalid-path error', () {
    expect(friendlyRemoteError('Invalid path specified in request URL'), remoteInvalidBackendUrl);
    expect(friendlyRemoteError('Invalid login credentials'), 'Invalid login credentials');
  });

  test('explains a missing leaderboard-to-profile relationship', () {
    const raw =
        "Could not find a relationship between 'leaderboard_snapshots' and 'profiles' in the schema cache";
    expect(isMissingLeaderboardProfileRelationship(raw), isTrue);
    expect(friendlyRemoteError(raw), remoteLeaderboardJoinUnavailable);
    expect(isMissingLeaderboardProfileRelationship('Connection closed.'), isFalse);
  });

  test('folds profiles onto a board that was read without an embed', () {
    final joined = attachLeaderboardProfileJoins(
      boardRows: <RemoteRow>[
        <String, Object?>{'user_id': 'usr_1', 'board_key': boardTotalLevel, 'value': 10},
        <String, Object?>{'user_id': 'usr_2', 'board_key': boardTotalLevel, 'value': 5},
      ],
      profiles: <RemoteRow>[
        <String, Object?>{'user_id': 'usr_1', 'username': 'Hero', 'guild_id': 'gld_1'},
      ],
      guilds: <RemoteRow>[
        <String, Object?>{'id': 'gld_1', 'name': 'Iron League'},
      ],
    );
    final entries = leaderboardEntriesFrom(joined, boardTotalLevel);
    expect(entries.first.username, 'Hero');
    expect(entries.first.guildName, 'Iron League');
    expect(entries.last.username, 'Adventurer');
    expect(entries.last.guildName, isNull);
  });

  test('rejects a URL that is only a suffix after trim', () {
    expect(RemoteBackendConfig.from(url: '  ', anonKey: 'key'), isNull);
    expect(
      RemoteBackendConfig.from(url: 'https://abcd.supabase.co/rest/v1', anonKey: 'key')?.url,
      'https://abcd.supabase.co',
    );
  });
}
