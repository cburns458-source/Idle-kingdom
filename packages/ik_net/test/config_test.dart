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

  test('maps a dead access token to sign in again', () {
    expect(isExpiredAuthError('JWT expired'), isTrue);
    expect(friendlyRemoteError('JWT expired'), remoteSignInAgain);
    expect(friendlyRemoteError('invalid JWT'), remoteSignInAgain);
  });

  test('friend list rows use guild name and last-online like the roster', () {
    const friend = SocialContact(
      userId: 'usr_1',
      username: 'Vari',
      appearance: defaultPlayerAppearance,
      guildName: 'Devguild',
    );
    final online = friendListRows(
      const <SocialContact>[friend],
      presence: <ActivityPresence>[
        ActivityPresence(
          userId: 'usr_1',
          username: 'Vari',
          appearance: defaultPlayerAppearance,
          guildName: 'Devguild',
          locationId: 'LOC-0001',
          currentActivityId: null,
          skillId: null,
          skillLevel: null,
          outfitCosmeticId: null,
          mountCosmeticId: null,
          updatedAt: '2026-01-01T00:00:00.000Z',
          expiresAt: '2026-01-02T00:00:00.000Z',
        ),
      ],
      nowMs: DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
    ).single;
    expect(online.subtitle, 'Devguild · Online');
    expect(online.isOnline, isTrue);

    final unknown = friendListRows(const <SocialContact>[
      SocialContact(userId: 'usr_2', username: 'test', appearance: defaultPlayerAppearance),
    ]).single;
    expect(unknown.subtitle, 'Unknown');
    expect(friendshipPair('b', 'a'), (userA: 'a', userB: 'b'));
  });

  test('explains a skipped guild skill-milestone migration without the SQL column name', () {
    expect(
      friendlyRemoteError('column guilds.skill_milestone_settings does not exist'),
      remoteGuildSkillMilestonesUnavailable,
    );
    expect(remoteMissingGuildSkillMilestoneColumn(remoteGuildSkillMilestonesUnavailable), isTrue);
    expect(remoteMissingGuildSkillMilestoneColumn('Connection closed.'), isFalse);
  });

  test('explains a skipped chat-privacy migration without the SQL column name', () {
    expect(
      friendlyRemoteError('column profiles.privacy_direct_messages does not exist'),
      remoteChatPrivacyUnavailable,
    );
    expect(remoteMissingChatPrivacyColumn(remoteChatPrivacyUnavailable), isTrue);
    expect(remoteMissingChatPrivacyColumn('Connection closed.'), isFalse);
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
          'guilds': <String, Object?>{'name': 'Iron League', 'tag': 'IRN'},
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
    expect(entries.first.guildTag, 'IRN');
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

  test('matches a private channel by its pair parts, not a substring', () {
    const pair = 'dm:usr_0001:usr_0002';
    expect(dmChannelInvolves(pair, 'usr_0001'), isTrue);
    expect(dmChannelInvolves(pair, 'usr_0002'), isTrue);
    expect(dmChannelInvolves(pair, 'usr_000'), isFalse);
    expect(dmChannelInvolves('global', 'usr_0001'), isFalse);
  });

  test('rejects a URL that is only a suffix after trim', () {
    expect(RemoteBackendConfig.from(url: '  ', anonKey: 'key'), isNull);
    expect(
      RemoteBackendConfig.from(url: 'https://abcd.supabase.co/rest/v1', anonKey: 'key')?.url,
      'https://abcd.supabase.co',
    );
  });
}
