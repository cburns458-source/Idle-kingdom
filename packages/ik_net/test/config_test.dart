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

  test('reads a view-shaped board row with its profile folded in', () {
    final entries = leaderboardEntriesFrom(<RemoteRow>[
      <String, Object?>{
        'user_id': 'usr_1',
        'board_key': boardTotalLevel,
        'value': 10,
        'profiles': <String, Object?>{
          'username': 'Hero',
          'appearance_json': <String, Object?>{},
          'guilds': <String, Object?>{'name': 'Iron League'},
        },
      },
      <String, Object?>{
        'user_id': 'usr_2',
        'board_key': boardTotalLevel,
        'value': 5,
        'profiles': <String, Object?>{
          'username': 'Adventurer',
          'appearance_json': defaultPlayerAppearance.toJson(),
          'guilds': null,
        },
      },
    ], boardTotalLevel);
    expect(entries.first.username, 'Hero');
    expect(entries.first.guildName, 'Iron League');
    expect(entries.first.appearance.toJson(), defaultPlayerAppearance.toJson());
    expect(entries.last.username, 'Adventurer');
    expect(entries.last.guildName, isNull);
  });

  test('an empty remote appearance_json does not throw', () {
    expect(playerAppearanceFromRemote(null).toJson(), defaultPlayerAppearance.toJson());
    expect(
      playerAppearanceFromRemote(<String, Object?>{}).toJson(),
      defaultPlayerAppearance.toJson(),
    );
    expect(
      playerAppearanceFromRemote(<String, Object?>{'skinTone': 'APR-0001'}).toJson(),
      defaultPlayerAppearance.copyWith(skinTone: 'APR-0001').toJson(),
    );

    final entry = leaderboardEntryFrom(
      <String, Object?>{
        'user_id': 'usr_1',
        'value': 10,
        'profiles': <String, Object?>{'username': 'Hero', 'appearance_json': <String, Object?>{}},
      },
      boardTotalLevel,
      0,
    );
    expect(entry.username, 'Hero');
    expect(entry.appearance.toJson(), defaultPlayerAppearance.toJson());

    final member = guildMemberFrom(<String, Object?>{
      'guild_id': 'gld_1',
      'user_id': 'usr_1',
      'username': 'Hero',
      'role': 'member',
      'joined_at': '2026-01-01T00:00:00.000Z',
      'appearance_json': <String, Object?>{},
    });
    expect(member.appearance.toJson(), defaultPlayerAppearance.toJson());
  });

  test('rejects a URL that is only a suffix after trim', () {
    expect(RemoteBackendConfig.from(url: '  ', anonKey: 'key'), isNull);
    expect(
      RemoteBackendConfig.from(url: 'https://abcd.supabase.co/rest/v1', anonKey: 'key')?.url,
      'https://abcd.supabase.co',
    );
  });
}
