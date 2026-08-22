import 'package:ik_net/ik_net.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// The channels the key fixture spells out, in the order it recorded them.
const List<ChatChannel> _channels = <ChatChannel>[
  ChatChannel.global(),
  ChatChannel.local('LOC-0002'),
  ChatChannel.local('citadel'),
  ChatChannel.guild('gld_0001'),
  ChatChannel.dm('usr_0001:usr_0002'),
];

const GuildEmblem _emblem = GuildEmblem(color: '#2f6b3a', symbol: 'tree');

List<Object?> _json(List<Object?> rows) => rows;

List<Map<String, Object?>> _presenceJson(List<ActivityPresence> rows) =>
    rows.map((row) => row.toJson()).toList();

List<Map<String, Object?>> _messageJson(List<ChatMessage> rows) =>
    rows.map((row) => row.toJson()).toList();

List<Map<String, Object?>> _entryJson(List<LeaderboardEntry> rows) =>
    rows.map((row) => row.toJson()).toList();

void main() {
  group('multiplayer keys parity', () {
    for (final fixture in loadParityFixtures('multiplayer/keys')) {
      test(fixture.name, () {
        expect(
          checkParity(fixture, <String, Object?>{
            'channelKeys': _channels.map(chatChannelKey).toList(),
            'dmPairKeys': <String>[
              dmPairKey('usr_b', 'usr_a'),
              dmPairKey('usr_a', 'usr_b'),
              dmPairKey('usr_a', 'usr_a'),
            ],
            'cooldowns': <String, Object?>{
              'global': ChatCooldownSeconds.global,
              'local': ChatCooldownSeconds.local,
              'guild': ChatCooldownSeconds.guild,
              'dm': ChatCooldownSeconds.dm,
            },
            'presenceTtlSeconds': presenceTtlSeconds,
            'presenceAwayTtlSeconds': presenceAwayTtlSeconds,
            'guild': <String, Object?>{
              'createGoldCost': guildCreateGoldCost,
              'maxMembers': guildMaxMembers,
              'colors': guildEmblemColors,
              'symbols': guildEmblemSymbols,
              'emojiToSymbol': guildEmblemEmojiToSymbol,
              'defaultRankLabels': defaultGuildRankLabels,
              'promotable': promotableGuildRanks,
            },
            'citadel': <String, Object?>{
              'locationId': citadelLocationId(),
              'chatLocationId': citadelChatLocationIdOf(),
              'channelKey': citadelLocalChannelKey(),
              'summary': citadelHubSummary(4).toJson(),
              'emptySummary': citadelHubSummary(0).toJson(),
            },
            'profanity': <String>[
              filterProfanity('hello there'),
              filterProfanity('what the fuck'),
              filterProfanity('SHIT and shit'),
              filterProfanity('classic scunthorpe'),
            ],
          }),
          isNull,
        );
      });
    }
  });

  group('leaderboard snapshot parity', () {
    for (final fixture in loadParityFixtures('multiplayer/snapshot')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final keys = launchBoardKeys(db);
        expect(
          checkParity(fixture, <String, Object?>{
            'boards': buildLeaderboardSnapshot(db, save).toJson(),
            'boardKeys': keys,
            'labels': <MultiplayerBoardKey>[
              ...keys,
              'skill:SKL-9999',
              'not-a-board',
            ].map((key) => <String, Object?>{'key': key, 'label': boardLabel(db, key)}).toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('account parity', () {
    for (final fixture in loadParityFixtures('multiplayer/accounts')) {
      test(fixture.name, () {
        final harness = BackendHarness(startMs: fixture.inputField<num>('nowMs'));
        final refusals = <Object?>[
          harness.backend.signUp('not-an-email', 'Hero', 'secret').toJson(),
          harness.backend.signUp('hero@example.com', 'H', 'secret').toJson(),
          harness.backend.signUp('hero@example.com', 'Hero', 'abc').toJson(),
        ];
        final created = harness.backend.signUp('  HERO@Example.com ', '  Hero  ', 'secret');
        final duplicates = <Object?>[
          harness.backend.signUp('hero@example.com', 'Other', 'secret').toJson(),
          harness.backend.signUp('other@example.com', 'HERO', 'secret').toJson(),
        ];
        final signedIn = harness.backend.signIn(' hero@EXAMPLE.com ', 'secret');
        final wrongPassword = harness.backend.signIn('hero@example.com', 'nope');
        final unknown = harness.backend.signIn('nobody@example.com', 'secret');
        final profile = harness.backend.getProfile('usr_0001');
        harness.advance(60000);
        final renamed = harness.backend.upsertProfile(
          'usr_0001',
          username: 'Renamed',
          privacyPublicSkills: false,
        );
        final missing = harness.backend.upsertProfile('usr_9999', username: 'Ghost');
        final adopted = harness.backend.registerProfile('usr_remote', 'Rowan');
        harness.backend.upsertProfile('usr_remote', privacyPublicSkills: false);
        final readopted = harness.backend.registerProfile('usr_remote', 'Renamed');
        expect(
          checkParity(fixture, <String, Object?>{
            'refusals': _json(refusals),
            'created': created.toJson(),
            'duplicates': _json(duplicates),
            'signedIn': signedIn.toJson(),
            'wrongPassword': wrongPassword.toJson(),
            'unknown': unknown.toJson(),
            'profile': profile?.toJson(),
            'renamed': renamed?.toJson(),
            'missing': missing?.toJson(),
            'adopted': adopted.toJson(),
            'readopted': readopted.toJson(),
            'doc': harness.doc(),
          }),
          isNull,
        );
      });
    }
  });

  group('cloud save parity', () {
    for (final fixture in loadParityFixtures('multiplayer/cloud-save')) {
      test(fixture.name, () {
        final save = saveOf(fixture);
        if (fixture.name == 'validation') {
          expect(
            checkParity(fixture, <String, Object?>{
              'clean': softValidateSave(save).toJson(),
              'negativeGold': softValidateSave(save.copyWith(gold: -1)).toJson(),
              'hugeGold': softValidateSave(save.copyWith(gold: 1000000001)).toJson(),
              'infiniteGold': softValidateSave(save.copyWith(gold: double.infinity)).toJson(),
              'zeroLevel': softValidateSave(
                save.copyWith(
                  skills: save.skills.indexed
                      .map((entry) => entry.$1 == 0 ? entry.$2.copyWith(level: 0) : entry.$2)
                      .toList(),
                ),
              ).toJson(),
              'negativeXp': softValidateSave(
                save.copyWith(
                  skills: save.skills.indexed
                      .map((entry) => entry.$1 == 1 ? entry.$2.copyWith(xp: -5) : entry.$2)
                      .toList(),
                ),
              ).toJson(),
            }),
            isNull,
          );
          return;
        }

        final harness = BackendHarness(startMs: fixture.inputField<num>('nowMs'));
        final session = harness.signUp('hero@example.com', 'Hero');
        final newer = save.copyWith(updatedAt: '2026-06-01T00:00:00.000Z', gold: 400);
        final older = save.copyWith(updatedAt: '2026-01-01T00:00:00.000Z', gold: 10);
        final first = harness.backend.writeCloudSave(session.userId, newer);
        final conflict = harness.backend.writeCloudSave(session.userId, older);
        final bumped = harness.backend.writeCloudSave(
          session.userId,
          older.copyWith(saveVersion: save.saveVersion + 1),
        );
        final unstamped = harness.backend.writeCloudSave(
          session.userId,
          save.copyWith(updatedAt: ''),
        );
        final forced = harness.backend.writeCloudSave(
          session.userId,
          older.copyWith(gold: 11),
          force: true,
        );
        expect(
          checkParity(fixture, <String, Object?>{
            'first': first.toJson(),
            'conflict': conflict.toJson(),
            'bumped': bumped.toJson(),
            'unstamped': unstamped.toJson(),
            'forced': forced.toJson(),
            'read': harness.backend.readCloudSave(session.userId)?.toJson(),
            'missing': harness.backend.readCloudSave('usr_9999')?.toJson(),
          }),
          isNull,
        );
      });
    }
  });

  group('leaderboard listing parity', () {
    for (final fixture in loadParityFixtures('multiplayer/leaderboard')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final harness = BackendHarness(startMs: fixture.inputField<num>('nowMs'));
        final hero = harness.signUp('hero@example.com', 'Hero');
        final rival = harness.signUp('rival@example.com', 'Rival');
        final heroSave = saveOf(fixture, 'heroSave');
        final rivalSave = saveOf(fixture, 'rivalSave');
        harness.backend.writeCloudSave(hero.userId, heroSave);
        harness.backend.writeCloudSave(rival.userId, rivalSave);
        harness.backend.submitLeaderboardSnapshot(db, hero.userId, heroSave);
        harness.backend.submitLeaderboardSnapshot(db, rival.userId, rivalSave);
        harness.backend.submitLeaderboardSnapshot(db, 'usr_9999', heroSave);
        harness.backend.createGuild(
          hero,
          const CreateGuildInput(
            name: 'Oak Guard',
            tag: 'OAK',
            description: 'For the kingdom',
            emblem: _emblem,
          ),
          100,
        );
        harness.backend.applyToGuild(rival, 'gld_0003', '');
        expect(
          checkParity(fixture, <String, Object?>{
            'totalLevel': _entryJson(harness.backend.listLeaderboard(boardTotalLevel)),
            'monsters': _entryJson(harness.backend.listLeaderboard(boardMonstersKilled)),
            'goldTie': _entryJson(harness.backend.listLeaderboard(boardGoldEarned)),
            'limited': _entryJson(harness.backend.listLeaderboard(boardMonstersKilled, 1)),
            'guilds': _entryJson(harness.backend.listLeaderboard(boardGuildTotalLevel)),
            'empty': _entryJson(harness.backend.listLeaderboard('skill:SKL-9999')),
          }),
          isNull,
        );
      });
    }
  });

  group('chat parity', () {
    for (final fixture in loadParityFixtures('multiplayer/chat')) {
      test(fixture.name, () {
        final harness = BackendHarness(startMs: fixture.inputField<num>('nowMs'));
        if (fixture.name == 'channels-and-cooldowns') {
          final hero = harness.signUp('hero@example.com', 'Hero');
          final sent = harness.backend.sendChat(
            hero,
            const ChatChannel.global(),
            '  Hello world  ',
          );
          final tooSoon = harness.backend.sendChat(hero, const ChatChannel.global(), 'Again');
          final empty = harness.backend.sendChat(hero, const ChatChannel.global(), '   ');
          final otherRoom = harness.backend.sendChat(
            hero,
            const ChatChannel.local('citadel'),
            'Anyone here?',
          );
          final notInGuild = harness.backend.sendChat(
            hero,
            const ChatChannel.guild('gld_0001'),
            'Hi',
          );
          harness.advance(10000);
          final stillTooSoon = harness.backend.sendChat(hero, const ChatChannel.global(), 'Third');
          harness.advance(20000);
          final afterCooldown = harness.backend.sendChat(
            hero,
            const ChatChannel.global(),
            'what the fuck',
          );
          final long = harness.backend.sendChat(
            hero,
            const ChatChannel.local('LOC-0002'),
            'x' * 300,
          );
          expect(
            checkParity(fixture, <String, Object?>{
              'sent': sent.toJson(),
              'tooSoon': tooSoon.toJson(),
              'empty': empty.toJson(),
              'otherRoom': otherRoom.toJson(),
              'notInGuild': notInGuild.toJson(),
              'stillTooSoon': stillTooSoon.toJson(),
              'afterCooldown': afterCooldown.toJson(),
              'longBodyLength': long.ok ? long.message!.body.length : null,
              'global': _messageJson(
                harness.backend.listChat(const ChatChannel.global(), hero.userId),
              ),
              'citadel': _messageJson(
                harness.backend.listChat(const ChatChannel.local('citadel'), hero.userId),
              ),
            }),
            isNull,
          );
          return;
        }

        final hero = harness.signUp('hero@example.com', 'Hero');
        final rival = harness.signUp('rival@example.com', 'Rival');
        final loud = harness.signUp('loud@example.com', 'Loud');
        final pair = ChatChannel.dm(dmPairKey(hero.userId, rival.userId));
        harness.backend.sendChat(hero, pair, 'Trade?');
        harness.advance(3000);
        harness.backend.sendChat(rival, pair, 'Sure');
        harness.advance(3000);
        const readAt = '2026-08-12T21:00:03.000Z';
        harness.backend.sendChat(loud, const ChatChannel.global(), 'Buying everything');
        harness.backend.sendChat(rival, const ChatChannel.global(), 'Ignore that');
        harness.backend.muteUser(hero.userId, loud.userId);
        harness.backend.muteUser(hero.userId, loud.userId);
        harness.backend.blockUser(hero.userId, 'usr_9999');
        harness.backend.reportUser(hero.userId, loud.userId, '   ');
        harness.backend.reportUser(hero.userId, loud.userId, 'y' * 250);
        expect(
          checkParity(fixture, <String, Object?>{
            'dms': _messageJson(harness.backend.listDirectMessages(hero.userId)),
            'unreadAll': harness.backend.countUnreadDirectMessages(hero.userId, null),
            'unreadSince': harness.backend.countUnreadDirectMessages(hero.userId, readAt),
            'unreadForRival': harness.backend.countUnreadDirectMessages(rival.userId, null),
            'globalForHero': _messageJson(
              harness.backend.listChat(const ChatChannel.global(), hero.userId),
            ),
            'globalForRival': _messageJson(
              harness.backend.listChat(const ChatChannel.global(), rival.userId),
            ),
            'mutes': harness.doc(),
          }),
          isNull,
        );
      });
    }
  });

  group('guild parity', () {
    for (final fixture in loadParityFixtures('multiplayer/guilds')) {
      test(fixture.name, () {
        switch (fixture.name) {
          case 'create-and-browse':
            _replayGuildBrowse(fixture);
          case 'applications-and-ranks':
            _replayGuildRanks(fixture);
          default:
            _replayGuildCapacity(fixture);
        }
      });
    }
  });

  group('presence parity', () {
    for (final fixture in loadParityFixtures('multiplayer/presence')) {
      test(fixture.name, () {
        if (fixture.name == 'from-save') {
          final save = saveOf(fixture);
          final dressed = save.copyWith(
            currentLocationId: 'LOC-0003',
            currentActivityId: 'ACT-0002',
            cosmetics: CosmeticsState(
              unlocked: save.cosmetics.unlocked,
              equipped: <String, String?>{
                ...save.cosmetics.equipped,
                outfitCosmeticSlotId: 'COS-0001',
                petCosmeticSlotId: 'COS-0004',
              },
            ),
          );
          final noSkills = save.copyWith(skills: const <SkillProgress>[]);
          final noCombat = save.copyWith(
            skills: save.skills.where((skill) => skill.skillId != 'SKL-0001').toList(),
          );
          expect(
            checkParity(fixture, <String, Object?>{
              'dressed': _presenceInputJson(presenceFromSave(dressed)),
              'noSkills': _presenceInputJson(presenceFromSave(noSkills)),
              'noCombat': _presenceInputJson(presenceFromSave(noCombat)),
            }),
            isNull,
          );
          return;
        }

        final harness = BackendHarness(startMs: fixture.inputField<num>('nowMs'));
        final appearance = PlayerAppearance.fromJson(
          fixture.inputField<Map<String, Object?>>('appearance'),
        );
        final hero = harness.signUp('hero@example.com', 'Hero');
        final rival = harness.signUp('rival@example.com', 'Rival');
        final published = harness.backend.upsertPresence(
          hero,
          PresenceInput(
            appearance: appearance,
            locationId: 'LOC-0028',
            currentActivityId: 'ACT-0001',
            skillId: 'SKL-0001',
            skillLevel: 7,
            outfitCosmeticId: 'COS-0001',
            mountCosmeticId: null,
          ),
        );
        harness.advance(30000);
        final second = harness.backend.upsertPresence(
          rival,
          PresenceInput(
            appearance: appearance,
            locationId: 'LOC-0028',
            currentActivityId: null,
            skillId: 'SKL-0002',
            skillLevel: 3,
            outfitCosmeticId: null,
            mountCosmeticId: null,
          ),
        );
        final plaza = harness.backend.listPresence(locationId: 'LOC-0028');
        final byActivity = harness.backend.listPresence(
          locationId: 'LOC-0028',
          activityId: 'ACT-0001',
        );
        final elsewhere = harness.backend.listPresence(locationId: 'LOC-0002');
        final anyLocation = harness.backend.listPresence();
        harness.advance(presenceTtlSeconds * 1000 + 1000);
        final afterHeartbeat = harness.backend.listPresence(locationId: 'LOC-0028');
        harness.advance(presenceAwayTtlSeconds * 1000);
        final afterExpiry = harness.backend.listPresence(locationId: 'LOC-0028');
        harness.backend.clearPresence(rival.userId);
        expect(
          checkParity(fixture, <String, Object?>{
            'published': published.toJson(),
            'second': second.toJson(),
            'plaza': _presenceJson(plaza),
            'byActivity': _presenceJson(byActivity),
            'elsewhere': _presenceJson(elsewhere),
            'anyLocation': _presenceJson(anyLocation),
            'afterHeartbeat': _presenceJson(afterHeartbeat),
            'afterExpiry': _presenceJson(afterExpiry),
            'cleared': _presenceJson(harness.backend.listPresence()),
          }),
          isNull,
        );
      });
    }
  });

  group('bounty claim parity', () {
    for (final fixture in loadParityFixtures('multiplayer/bounty-claims')) {
      test(fixture.name, () {
        final harness = BackendHarness(startMs: fixture.inputField<num>('nowMs'));
        final first = harness.signUp('first@example.com', 'First');
        final second = harness.signUp('second@example.com', 'Second');
        final claimed = harness.backend.claimBounty(first, '2026-08-12T21', 'BNT-0001');
        harness.advance(5000);
        final repeated = harness.backend.claimBounty(first, '2026-08-12T21', 'BNT-0001');
        final lost = harness.backend.claimBounty(second, '2026-08-12T21', 'BNT-0001');
        final otherBounty = harness.backend.claimBounty(second, '2026-08-12T21', 'BNT-0002');
        final nextHour = harness.backend.claimBounty(second, '2026-08-12T22', 'BNT-0001');
        expect(
          checkParity(fixture, <String, Object?>{
            'claimed': claimed.toJson(),
            'repeated': repeated.toJson(),
            'lost': lost.toJson(),
            'otherBounty': otherBounty.toJson(),
            'nextHour': nextHour.toJson(),
            'thisHour': harness.backend
                .listBountyClaims('2026-08-12T21')
                .map((row) => row.toJson())
                .toList(),
            'lookup': harness.backend.getBountyClaim('2026-08-12T21', 'BNT-0002')?.toJson(),
            'missing': harness.backend.getBountyClaim('2026-08-12T21', 'BNT-9999')?.toJson(),
          }),
          isNull,
        );
      });
    }
  });

  group('bazaar parity', () {
    for (final fixture in loadParityFixtures('multiplayer/bazaar')) {
      test(fixture.name, () {
        final harness = BackendHarness(startMs: fixture.inputField<num>('nowMs'));
        final hero = harness.signUp('hero@example.com', 'Hero');
        final rival = harness.signUp('rival@example.com', 'Rival');
        final posted = harness.backend.postBazaar(hero, bazaarPostTrade, '  Selling copper ore  ');
        final tooSoon = harness.backend.postBazaar(hero, bazaarPostMessage, 'Also this');
        final empty = harness.backend.postBazaar(rival, bazaarPostMessage, '  ');
        final unknownKind = harness.backend.postBazaar(rival, 'auction', 'Bid now');
        final otherPlayer = harness.backend.postBazaar(
          rival,
          bazaarPostRecruit,
          'Guild needs members',
        );
        harness.advance(10000);
        final afterCooldown = harness.backend.postBazaar(hero, bazaarPostMessage, 'what the shit');
        expect(
          checkParity(fixture, <String, Object?>{
            'posted': posted.toJson(),
            'tooSoon': tooSoon.toJson(),
            'empty': empty.toJson(),
            'unknownKind': unknownKind.toJson(),
            'otherPlayer': otherPlayer.toJson(),
            'afterCooldown': afterCooldown.toJson(),
            'all': harness.backend.listBazaarPosts().map((row) => row.toJson()).toList(),
            'limited': harness.backend.listBazaarPosts(2).map((row) => row.toJson()).toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('local db parity', () {
    for (final fixture in loadParityFixtures('multiplayer/local-db')) {
      test(fixture.name, () {
        final harness = BackendHarness(
          startMs: fixture.inputField<num>('nowMs'),
          seed: fixture.inputField<String>('seed'),
        );
        final guilds = harness.backend.listGuilds().map((row) => row.toJson()).toList();
        final members = harness.backend
            .guildMembers('gld_legacy')
            .map((row) => row.toJson())
            .toList();
        harness.backend.muteUser('usr_legacy', 'usr_other');
        expect(
          checkParity(fixture, <String, Object?>{
            'guilds': guilds,
            'members': members,
            'afterWrite': harness.doc(),
          }),
          isNull,
        );
      });
    }
  });

  group('public profile parity', () {
    for (final fixture in loadParityFixtures('multiplayer/public-profile')) {
      test(fixture.name, () {
        final harness = BackendHarness(startMs: fixture.inputField<num>('nowMs'));
        final hero = harness.signUp('hero@example.com', 'Hero');
        final shy = harness.signUp('shy@example.com', 'Shy');
        final save = saveOf(fixture);
        harness.backend.writeCloudSave(hero.userId, save);
        harness.backend.writeCloudSave(shy.userId, save);
        harness.backend.upsertProfile(shy.userId, privacyPublicSkills: false);
        final friendRequest = harness.backend.sendFriendRequest(hero.userId, shy.userId);
        final duplicateRequest = harness.backend.sendFriendRequest(hero.userId, shy.userId);
        final self = harness.backend.sendFriendRequest(hero.userId, hero.userId);
        final accepted = harness.backend.sendFriendRequest(shy.userId, hero.userId);
        final alreadyFriends = harness.backend.sendFriendRequest(hero.userId, shy.userId);
        expect(
          checkParity(fixture, <String, Object?>{
            'open': harness.backend.publicProfile(hero.userId)?.toJson(),
            'private': harness.backend.publicProfile(shy.userId)?.toJson(),
            'noAccount': harness.backend.publicProfile('usr_9999')?.toJson(),
            'noSave': harness.backend
                .publicProfile(
                  hero.userId,
                  save.copyWith(
                    skills: const <SkillProgress>[],
                    achievements: const <AchievementProgress>[],
                  ),
                )
                ?.toJson(),
            'friendRequest': friendRequest.toJson(),
            'duplicateRequest': duplicateRequest.toJson(),
            'self': self.toJson(),
            'accepted': accepted.toJson(),
            'alreadyFriends': alreadyFriends.toJson(),
          }),
          isNull,
        );
      });
    }
  });

  group('remote row parity', () {
    for (final fixture in loadParityFixtures('multiplayer/remote')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        final save = saveOf(fixture);
        final nowIso = fixture.inputField<String>('nowIso');
        List<RemoteRow> rowsOf(String key) =>
            fixture.inputField<List<Object?>>(key).map((value) => asJsonMap(value)).toList();
        final saveRows = rowsOf('saveRows');
        final records = saveRows.map((row) => remoteSaveRowFrom('usr_0001', row)).toList();
        expect(
          checkParity(fixture, <String, Object?>{
            'names': <String, Object?>{
              'tables': <String, Object?>{
                'profiles': RemoteTables.profiles,
                'saves': RemoteTables.saves,
                'leaderboard': RemoteTables.leaderboard,
                'leaderboardEntries': RemoteTables.leaderboardEntries,
                'chat': RemoteTables.chat,
                'bountyClaims': RemoteTables.bountyClaims,
                'bazaarPosts': RemoteTables.bazaarPosts,
                'guilds': RemoteTables.guilds,
                'guildMembers': RemoteTables.guildMembers,
              },
              'sendChat': remoteSendChatFunction,
              'saveColumns': remoteSaveColumns,
              'chatColumns': remoteChatColumns,
              'leaderboardColumns': remoteLeaderboardColumns,
              'leaderboardConflict': remoteLeaderboardConflict,
              'bountyClaimColumns': remoteBountyClaimColumns,
              'bazaarColumns': remoteBazaarColumns,
              'chatLimit': remoteChatLimit,
              'bazaarLimit': remoteBazaarLimit,
              'usernameMaxLength': remoteUsernameMaxLength,
            },
            'messages': <String, Object?>{
              'notConfigured': remoteNotConfigured,
              'signUpFailed': remoteSignUpFailed,
              'signInFailed': remoteSignInFailed,
              'magicLinkUnavailable': remoteMagicLinkUnavailable,
              'chatSendFailed': remoteChatSendFailed,
              'bazaarPostFailed': remoteBazaarPostFailed,
              'saveConflict': remoteSaveConflict,
            },
            'usernames': <String>['  Rowan  ', 'a' * 40, ''].map(remoteUsername).toList(),
            'emails': <String>[
              '  HERO@Example.com ',
              'plain@example.com',
            ].map(remoteEmail).toList(),
            'signUpSession': sessionFromSignUp(
              'usr_0001',
              '  HERO@Example.com ',
              ' Rowan ',
              'token',
            ).toJson(),
            'signUpWithoutToken': sessionFromSignUp('usr_0001', 'a@b.co', 'Rowan', null).toJson(),
            'signInSessions': <Object?>[
              sessionFromSignIn(
                'usr_0001',
                'hero@example.com',
                'typed@x.co',
                'Rowan',
                'token',
              ).toJson(),
              sessionFromSignIn('usr_0001', 'hero@example.com', 'typed@x.co', null, null).toJson(),
              sessionFromSignIn('usr_0001', null, '  TYPED@X.co ', null, null).toJson(),
            ],
            'profileRow': profileRowForSignUp(
              sessionFromSignUp('usr_0001', 'a@b.co', 'Rowan', null),
            ),
            'saveRow': saveRowFor('usr_0001', save),
            'cloudRecords': records.map((record) => record?.toJson()).toList(),
            'newer': records
                .map((record) => record == null ? null : isRemoteSaveNewer(record, save))
                .toList(),
            'leaderboardRows': leaderboardRowsFor(
              'usr_0001',
              buildLeaderboardSnapshot(db, save),
              nowIso,
            ),
            'entries': leaderboardEntriesFrom(
              rowsOf('boardRows'),
              boardTotalLevel,
            ).map((entry) => entry.toJson()).toList(),
            'chatMessages': rowsOf('chatRows').map((row) => chatMessageFrom(row).toJson()).toList(),
            'functionMessages': <Object?>[
              chatMessageFromFunction(<String, Object?>{
                'id': 'msg_1',
                'channelKey': 'global',
                'userId': 'usr_0001',
                'username': 'Hero',
                'body': 'Hi',
                'createdAt': nowIso,
              })?.toJson(),
              chatMessageFromFunction(rowsOf('chatRows').first)?.toJson(),
              chatMessageFromFunction(<String, Object?>{'accepted': true})?.toJson(),
              chatMessageFromFunction(null)?.toJson(),
            ],
            'claimRow': bountyClaimRowFor(_remoteSession, '2026-08-12T21', 'BNT-0001'),
            'claims': rowsOf('claimRows').map((row) => bountyClaimFrom(row).toJson()).toList(),
            'bazaarRow': bazaarPostRowFor(_remoteSession, bazaarPostTrade, 'Selling copper ore'),
            'bazaarPosts': bazaarPostsFrom(rowsOf('bazaarRows'))
                .map((post) => post.toJson())
                .toList(),
            'preparedPosts': <Object?>[
              prepareBazaarPost(bazaarPostMessage, '  Hello there  ').toJson(),
              prepareBazaarPost(bazaarPostMessage, '   ').toJson(),
              prepareBazaarPost(bazaarPostTrade, 'fuck ${'a' * 400}').toJson(),
              prepareBazaarPost('shouting', 'Hello').toJson(),
            ],
            'defaultAppearance': defaultPlayerAppearance.toJson(),
          }),
          isNull,
        );
      });
    }
  });
}

/// The account every remote row in these scenarios is written by.
const MultiplayerSession _remoteSession = MultiplayerSession(
  userId: 'usr_0001',
  email: 'hero@example.com',
  username: 'Hero',
  accessToken: 'token',
);

Map<String, Object?> _presenceInputJson(PresenceInput input) => <String, Object?>{
  'appearance': input.appearance.toJson(),
  'locationId': input.locationId,
  'currentActivityId': input.currentActivityId,
  'skillId': input.skillId,
  'skillLevel': input.skillLevel,
  'outfitCosmeticId': input.outfitCosmeticId,
  'mountCosmeticId': input.mountCosmeticId,
};

void _replayGuildBrowse(ParityFixture fixture) {
  final harness = BackendHarness(startMs: fixture.inputField<num>('nowMs'));
  final leader = harness.signUp('leader@example.com', 'Leader');
  final refusals = <Object?>[
    harness.backend
        .createGuild(leader, const CreateGuildInput(name: 'Ab', tag: 'AB', emblem: _emblem), 100)
        .toJson(),
    harness.backend
        .createGuild(
          leader,
          const CreateGuildInput(name: 'Iron League', tag: 'I', emblem: _emblem),
          100,
        )
        .toJson(),
    harness.backend
        .createGuild(
          leader,
          const CreateGuildInput(name: 'Iron League', tag: 'IRON5', emblem: _emblem),
          100,
        )
        .toJson(),
    harness.backend
        .createGuild(
          leader,
          const CreateGuildInput(name: 'Iron League', tag: 'IRN', emblem: _emblem),
          10,
        )
        .toJson(),
  ];
  final created = harness.backend.createGuild(
    leader,
    CreateGuildInput(
      name: 'Iron League',
      tag: 'irn',
      description: 'd' * 200,
      emblem: const GuildEmblem(color: '#3d5a80', symbol: '🛡️'),
    ),
    guildCreateGoldCost,
  );
  final again = harness.backend.createGuild(
    leader,
    const CreateGuildInput(name: 'Second Guild', tag: 'SEC', emblem: _emblem),
    100,
  );
  final other = harness.signUp('other@example.com', 'Other');
  final takenName = harness.backend.createGuild(
    other,
    const CreateGuildInput(name: 'IRON LEAGUE', tag: 'XYZ', emblem: _emblem),
    100,
  );
  final takenTag = harness.backend.createGuild(
    other,
    const CreateGuildInput(name: 'Bronze League', tag: 'irn', emblem: _emblem),
    100,
  );
  final made = harness.backend.createGuild(
    other,
    const CreateGuildInput(name: 'Aardvark Alliance', tag: 'AA', emblem: _emblem),
    100,
  );
  expect(
    checkParity(fixture, <String, Object?>{
      'refusals': _json(refusals),
      'created': created.toJson(),
      'again': again.toJson(),
      'takenName': takenName.toJson(),
      'takenTag': takenTag.toJson(),
      'made': made.toJson(),
      'listed': harness.backend.listGuilds().map((row) => row.toJson()).toList(),
      'guild': harness.backend.getGuild('gld_0002')?.toJson(),
      'missing': harness.backend.getGuild('gld_9999')?.toJson(),
      'members': harness.backend.guildMembers('gld_0002').map((row) => row.toJson()).toList(),
      'projects': harness.backend.guildProjects('gld_0002').map((row) => row.toJson()).toList(),
      'challenges': harness.backend.guildChallenges('gld_0002').map((row) => row.toJson()).toList(),
    }),
    isNull,
  );
}

void _replayGuildRanks(ParityFixture fixture) {
  final db = databaseOf(fixture);
  final harness = BackendHarness(startMs: fixture.inputField<num>('nowMs'));
  final leader = harness.signUp('leader@example.com', 'Leader');
  final joiner = harness.signUp('join@example.com', 'Joiner');
  final walkIn = harness.signUp('walk@example.com', 'WalkIn');
  final created = harness.backend.createGuild(
    leader,
    const CreateGuildInput(name: 'Iron League', tag: 'IRN', emblem: _emblem),
    guildCreateGoldCost,
  );
  final guildId = created.ok ? created.guild!.id : 'gld_0002';
  final notLeader = harness.backend.setGuildJoinPolicy(joiner.userId, guildId, guildJoinClosed);
  harness.backend.setGuildJoinPolicy(leader.userId, guildId, guildJoinClosed);
  final applied = harness.backend.applyToGuild(joiner, guildId, 'p' * 200);
  final duplicate = harness.backend.applyToGuild(joiner, guildId, 'again');
  final unknownGuild = harness.backend.applyToGuild(joiner, 'gld_9999', '');
  final applications = harness.backend.listApplications(guildId);
  final rejected = harness.backend.decideApplication(joiner.userId, applications[0].id, true);
  final accepted = harness.backend.decideApplication(leader.userId, applications[0].id, true);
  final goneApplication = harness.backend.decideApplication(
    leader.userId,
    applications[0].id,
    true,
  );
  harness.backend.setGuildJoinPolicy(leader.userId, guildId, guildJoinOpen);
  final walkedIn = harness.backend.applyToGuild(walkIn, guildId, '');
  final alreadyIn = harness.backend.applyToGuild(joiner, guildId, '');
  final promoted = harness.backend.setMemberRole(
    leader.userId,
    guildId,
    joiner.userId,
    guildRoleOfficer,
  );
  final cannotPromoteToLeader = harness.backend.setMemberRole(
    leader.userId,
    guildId,
    joiner.userId,
    guildRoleLeader,
  );
  final cannotDemoteLeader = harness.backend.setMemberRole(
    leader.userId,
    guildId,
    leader.userId,
    guildRoleMember,
  );
  final labels = harness.backend.setGuildRankLabels(leader.userId, guildId, <String, String>{
    'officer': 'Captain',
    'leader': 'Guildmaster',
    'recruit': '   ',
    'member': 'A rank name well past the limit',
  });
  final emblem = harness.backend.setGuildEmblem(
    leader.userId,
    guildId,
    const GuildEmblem(color: '#7a2f2f', symbol: 'dragon'),
  );
  final leaderCannotLeave = harness.backend.leaveGuild(leader.userId);
  final contributed = harness.backend.contributeToProject(
    joiner.userId,
    harness.backend.guildProjects(guildId)[0].id,
    2500.7,
  );
  final contributedTooLittle = harness.backend.contributeToProject(
    joiner.userId,
    harness.backend.guildProjects(guildId)[0].id,
    0,
  );
  final outsiderContribution = harness.backend.contributeToProject(
    'usr_9999',
    harness.backend.guildProjects(guildId)[0].id,
    5,
  );
  harness.backend.submitLeaderboardSnapshot(db, joiner.userId, saveOf(fixture, 'killSave'));
  harness.backend.refreshGuildChallengeAggregates(guildId);
  final memberLeft = harness.backend.leaveGuild(walkIn.userId);
  final notInGuild = harness.backend.leaveGuild('usr_9999');
  expect(
    checkParity(fixture, <String, Object?>{
      'notLeader': notLeader.toJson(),
      'applied': applied.toJson(),
      'duplicate': duplicate.toJson(),
      'unknownGuild': unknownGuild.toJson(),
      'applications': applications.map((row) => row.toJson()).toList(),
      'rejected': rejected.toJson(),
      'accepted': accepted.toJson(),
      'goneApplication': goneApplication.toJson(),
      'walkedIn': walkedIn.toJson(),
      'alreadyIn': alreadyIn.toJson(),
      'promoted': promoted.toJson(),
      'cannotPromoteToLeader': cannotPromoteToLeader.toJson(),
      'cannotDemoteLeader': cannotDemoteLeader.toJson(),
      'labels': labels.toJson(),
      'emblem': emblem.toJson(),
      'leaderCannotLeave': leaderCannotLeave.toJson(),
      'contributed': contributed.toJson(),
      'contributedTooLittle': contributedTooLittle.toJson(),
      'outsiderContribution': outsiderContribution.toJson(),
      'memberLeft': memberLeft.toJson(),
      'notInGuild': notInGuild.toJson(),
      'guild': harness.backend.getGuild(guildId)?.toJson(),
      'members': harness.backend.guildMembers(guildId).map((row) => row.toJson()).toList(),
      'challenges': harness.backend.guildChallenges(guildId).map((row) => row.toJson()).toList(),
      'leaderProfile': harness.backend.getProfile(leader.userId)?.toJson(),
      'walkInProfile': harness.backend.getProfile(walkIn.userId)?.toJson(),
    }),
    isNull,
  );
}

void _replayGuildCapacity(ParityFixture fixture) {
  final harness = BackendHarness(startMs: fixture.inputField<num>('nowMs'));
  final leader = harness.signUp('cap@example.com', 'Cap');
  final created = harness.backend.createGuild(
    leader,
    const CreateGuildInput(name: 'Full House', tag: 'FUL', emblem: _emblem),
    guildCreateGoldCost,
  );
  final guildId = created.ok ? created.guild!.id : 'gld_0002';
  for (var index = 0; index < guildMaxMembers - 1; index += 1) {
    final member = harness.signUp('u$index@example.com', 'User$index');
    harness.backend.applyToGuild(member, guildId, '');
  }
  final overflow = harness.signUp('overflow@example.com', 'Overflow');
  final blocked = harness.backend.applyToGuild(overflow, guildId, '');
  harness.backend.setGuildJoinPolicy(leader.userId, guildId, guildJoinClosed);
  final applied = harness.backend.applyToGuild(overflow, guildId, 'let me in');
  expect(
    checkParity(fixture, <String, Object?>{
      'memberCount': harness.backend.listGuilds().firstOrNull?.memberCount,
      'blocked': blocked.toJson(),
      'applied': applied.toJson(),
    }),
    isNull,
  );
}
