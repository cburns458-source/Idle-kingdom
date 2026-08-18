import 'package:ik_net/ik_net.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

const PlayerAppearance _appearance = PlayerAppearance(
  skinTone: 'APR-0001',
  hairstyle: 'APR-0004',
  hairColor: 'APR-0007',
  expression: 'APR-0011',
  beard: 'APR-0014',
  genderPresentation: 'APR-0017',
);

const GuildEmblem _emblem = GuildEmblem(color: '#3d5a80', symbol: 'shield');

GuildRecord _guild({
  String name = 'Iron League',
  String tag = 'IRN',
  String description = 'For the kingdom',
  GuildJoinPolicy joinPolicy = guildJoinOpen,
  Map<GuildRankKey, String>? rankLabels,
}) {
  return GuildRecord(
    id: 'gld_1',
    name: name,
    tag: tag,
    description: description,
    emblem: _emblem,
    leaderId: 'usr_1',
    joinPolicy: joinPolicy,
    rankLabels: rankLabels ?? defaultGuildRankLabels,
    createdAt: '2026-08-01T00:00:00.000Z',
  );
}

GuildListing _listing({
  String id = 'gld_1',
  String name = 'Iron League',
  String tag = 'IRN',
  String description = 'For the kingdom',
  GuildJoinPolicy joinPolicy = guildJoinOpen,
  int memberCount = 3,
}) {
  final base = _guild(name: name, tag: tag, description: description, joinPolicy: joinPolicy);
  return GuildListing(
    guild: GuildRecord(
      id: id,
      name: base.name,
      tag: base.tag,
      description: base.description,
      emblem: base.emblem,
      leaderId: base.leaderId,
      joinPolicy: base.joinPolicy,
      rankLabels: base.rankLabels,
      createdAt: base.createdAt,
    ),
    memberCount: memberCount,
  );
}

GuildMember _member({
  String userId = 'usr_2',
  String username = 'Joiner',
  GuildRole role = guildRoleMember,
  String joinedAt = '2026-08-02T00:00:00.000Z',
  num totalLevel = 42,
}) {
  return GuildMember(
    guildId: 'gld_1',
    userId: userId,
    username: username,
    role: role,
    joinedAt: joinedAt,
    appearance: _appearance,
    totalLevel: totalLevel,
  );
}

ActivityPresence _presence({
  String userId = 'usr_2',
  String? skillId = 'SKL-0001',
  num? skillLevel = 7,
  String? guildName,
  String updatedAt = '2026-08-12T21:00:00.000Z',
}) {
  return ActivityPresence(
    userId: userId,
    username: 'Rival',
    appearance: _appearance,
    locationId: 'LOC-0028',
    currentActivityId: null,
    skillId: skillId,
    skillLevel: skillLevel,
    guildName: guildName,
    outfitCosmeticId: null,
    mountCosmeticId: null,
    updatedAt: updatedAt,
    expiresAt: '2026-08-12T21:02:00.000Z',
  );
}

const num _rosterNow = 1786568400000; // 2026-08-12T21:00:00.000Z

final List<ActivityPresence> _rosterPresence = <ActivityPresence>[
  _presence(userId: 'usr_1', updatedAt: '2026-08-12T20:59:10.000Z'),
  _presence(userId: 'usr_2', updatedAt: '2026-08-12T20:00:00.000Z'),
  _presence(userId: 'usr_4', updatedAt: '2026-08-12T20:59:50.000Z'),
];

LeaderboardEntry _entry({
  MultiplayerBoardKey boardKey = boardTotalLevel,
  LeaderboardEntryKind entryKind = LeaderboardEntryKind.player,
  num rank = 1,
  String userId = 'usr_1',
  String username = 'Hero',
  num value = 1204,
  num? secondaryValue,
  String? guildName,
  GuildEmblem? emblem,
}) {
  return LeaderboardEntry(
    userId: userId,
    username: username,
    appearance: _appearance,
    guildName: guildName,
    boardKey: boardKey,
    value: value,
    rank: rank,
    secondaryValue: secondaryValue,
    entryKind: entryKind,
    emblem: emblem,
  );
}

GuildApplication _application({
  String id = 'app_1',
  String username = 'Joiner',
  String message = 'Please',
  bool guest = false,
}) {
  return GuildApplication(
    id: id,
    guildId: 'gld_1',
    userId: 'usr_2',
    username: username,
    message: message,
    createdAt: '2026-08-02T00:00:00.000Z',
    guest: guest,
  );
}

/// A guild that renamed some ranks and left others alone.
GuildRecord _renamedGuild() => _guild(
  rankLabels: <GuildRankKey, String>{
    ...defaultGuildRankLabels,
    guildRoleOfficer: 'Captain',
    guildRoleMember: 'Blade',
  }..remove(guildRoleRecruit),
);

const String _sameMoment = '2026-08-02T00:00:00.000Z';

final List<GuildMember> _roster = <GuildMember>[
  _member(
    userId: 'usr_1',
    username: 'Leader',
    role: guildRoleLeader,
    joinedAt: '2026-08-01T00:00:00.000Z',
    totalLevel: 90,
  ),
  _member(userId: 'usr_3', username: 'Late', joinedAt: '2026-08-03T00:00:00.000Z'),
  _member(userId: 'usr_2', username: 'Early', joinedAt: _sameMoment, role: guildRoleOfficer),
  _member(userId: 'usr_4', username: 'Twin', joinedAt: _sameMoment, role: guildRoleRecruit),
];

final PublicPlayerProfile _profile = PublicPlayerProfile(
  userId: 'usr_2',
  username: 'Rival',
  appearance: _appearance,
  totalLevel: 214,
  guildName: 'Iron League',
  achievementsUnlocked: 12,
  publicSkills: List<PublicSkillLine>.generate(
    10,
    (index) => PublicSkillLine(
      skillId: index == 0 ? 'SKL-0001' : 'SKL-0002',
      level: index + 1,
      xp: index * 100,
    ),
  ),
);

const Map<String, String> _skillNames = <String, String>{
  'SKL-0001': 'Combat',
  'SKL-0002': 'Woodcutting',
};

String _skillName(String? skillId) =>
    skillId == null ? 'Unknown' : (_skillNames[skillId] ?? skillId);

Map<String, Object?>? _channelJson(ChatChannel? channel) => channel?.toJson();

List<Map<String, Object?>> _rows(Iterable<Object?> rows) =>
    rows.map((row) => (row as dynamic).toJson() as Map<String, Object?>).toList();

void main() {
  group('guild view parity', () {
    for (final fixture in loadParityFixtures('social-views/guilds')) {
      test(fixture.name, () {
        switch (fixture.name) {
          case 'browse':
            final rows = <GuildListing>[
              _listing(),
              _listing(
                id: 'gld_2',
                name: 'Oak Guard',
                tag: 'OAK',
                joinPolicy: guildJoinClosed,
                description: '',
              ),
              _listing(id: 'gld_3', name: 'Full House', tag: 'FUL', memberCount: 25),
            ];
            expect(
              checkParity(fixture, <String, Object?>{
                'all': _rows(guildBrowseRows(rows)),
                'blank': guildBrowseRows(rows, '   ').map((row) => row.guildId).toList(),
                'byName': guildBrowseRows(rows, 'oak').map((row) => row.guildId).toList(),
                'byBracketedTag': guildBrowseRows(rows, '[irn]').map((row) => row.guildId).toList(),
                'byPartialName': guildBrowseRows(rows, 'LEAGUE').map((row) => row.guildId).toList(),
                'noMatch': _rows(guildBrowseRows(rows, 'zzz')),
                'applicationMessages': <String>[
                  defaultApplicationMessage('Rowan'),
                  defaultApplicationMessage(null),
                  defaultApplicationMessage(''),
                  defaultApplicationMessage('   '),
                  defaultApplicationMessage('  Rowan  '),
                ],
              }),
              isNull,
            );
          case 'create-form':
            expect(
              checkParity(fixture, <String, Object?>{
                'poor': createGuildFormView(10, 'ir').toJson(),
                'rich': createGuildFormView(1200, '').toJson(),
                'exact': createGuildFormView(25, 'iron5').toJson(),
                'million': createGuildFormView(1234567, 'a-b c!').toJson(),
                'sanitized': <String>[
                  'ir n2!',
                  'abcdefg',
                  '',
                  '1234',
                  'Ok',
                ].map(sanitizeGuildTagInput).toList(),
              }),
              isNull,
            );
          default:
            final renamed = _renamedGuild();
            expect(
              checkParity(fixture, <String, Object?>{
                'leaderHeader': guildHomeHeader(_guild(), 4, 'usr_1').toJson(),
                'memberHeader': guildHomeHeader(
                  _guild(joinPolicy: guildJoinClosed),
                  4,
                  'usr_2',
                ).toJson(),
                'anonymousHeader': guildHomeHeader(_guild(), 0, null).toJson(),
                'oldest': _rows(
                  guildRosterRows(
                    _guild(),
                    _roster,
                    GuildRosterSort.oldest,
                    'usr_1',
                    presence: _rosterPresence,
                    nowMs: _rosterNow,
                  ),
                ),
                'newest': guildRosterRows(
                  _guild(),
                  _roster,
                  GuildRosterSort.newest,
                  'usr_1',
                  presence: _rosterPresence,
                  nowMs: _rosterNow,
                ).map((row) => row.username).toList(),
                'asMember': guildRosterRows(
                  _guild(),
                  _roster,
                  GuildRosterSort.oldest,
                  'usr_2',
                  presence: _rosterPresence,
                  nowMs: _rosterNow,
                ).map((row) => row.manageable).toList(),
                'renamedRoster': guildRosterRows(
                  renamed,
                  _roster,
                  GuildRosterSort.oldest,
                  'usr_1',
                  presence: _rosterPresence,
                  nowMs: _rosterNow,
                ).map((row) => row.rankLabel).toList(),
                'rankOptions': _rows(guildRankOptions(renamed)),
                'rankFields': _rows(rankLabelFields(renamed)),
                'leavePrompt': leaveGuildPrompt(_guild()),
                'applications': _rows(
                  guildApplicationRows(<GuildApplication>[
                    _application(),
                    _application(id: 'app_2', username: 'Quiet', message: ''),
                    _application(id: 'app_3', username: 'Wanderer', message: 'Hi', guest: true),
                    _application(id: 'app_4', username: 'Silent', message: '', guest: true),
                  ]),
                ),
                'signInPrompts': <String>[signInPrompt, guildSignInPrompt],
                'symbols': guildEmblemSymbols,
                'symbolPaths': <String>[...guildEmblemSymbols, 'not-a-symbol']
                    .map(
                      (symbol) => <String, Object?>{
                        'symbol': symbol,
                        'path': guildEmblemSymbolPath(symbol),
                      },
                    )
                    .toList(),
              }),
              isNull,
            );
        }
      });
    }
  });

  group('leaderboard view parity', () {
    for (final fixture in loadParityFixtures('social-views/leaderboards')) {
      test(fixture.name, () {
        final db = databaseOf(fixture);
        expect(
          checkParity(fixture, <String, Object?>{
            'boards': _rows(boardOptions(db)),
            'rows': _rows(
              leaderboardRows(<LeaderboardEntry>[
                _entry(secondaryValue: 9500000, guildName: 'Iron League'),
                _entry(rank: 2, userId: 'usr_2', username: 'Rival', value: 12),
                _entry(
                  boardKey: boardGuildTotalLevel,
                  entryKind: LeaderboardEntryKind.guild,
                  userId: 'gld_1',
                  username: '[IRN] Iron League',
                  guildName: '4/25 members',
                  value: 1234567,
                  emblem: _emblem,
                ),
                _entry(
                  rank: 2,
                  boardKey: boardGuildTotalLevel,
                  entryKind: LeaderboardEntryKind.guild,
                  userId: 'gld_2',
                  username: '[OAK] Oak Guard',
                  value: 0,
                ),
              ]),
            ),
            'emptyMessages':
                <MultiplayerBoardKey>[
                      boardTotalLevel,
                      boardGuildTotalLevel,
                      boardPacifistTotalLevel,
                      'skill:SKL-0001',
                    ]
                    .map((key) => <String, Object?>{'key': key, 'message': emptyBoardMessage(key)})
                    .toList(),
          }),
          isNull,
        );
      });
    }
  });

  group('chat view parity', () {
    for (final fixture in loadParityFixtures('social-views/chat')) {
      test(fixture.name, () {
        const messages = <ChatMessage>[
          ChatMessage(
            id: 'msg_1',
            channelKey: 'global',
            userId: 'usr_1',
            username: 'Hero',
            body: 'Hello world',
            createdAt: '2026-08-12T21:00:00.000Z',
          ),
          ChatMessage(
            id: 'msg_2',
            channelKey: 'global',
            userId: 'usr_2',
            username: 'Rival',
            body: 'Hi back',
            createdAt: '2026-08-12T21:00:05.000Z',
          ),
        ];
        expect(
          checkParity(fixture, <String, Object?>{
            'tabIds': chatTabOrder.map((tab) => tab.wire).toList(),
            'plain': _rows(
              chatTabs(
                selected: ChatTab.global,
                citadelHub: false,
                hasGuild: false,
                hasGuest: false,
                unreadDms: 0,
              ),
            ),
            'citadelWithGuild': _rows(
              chatTabs(
                selected: ChatTab.local,
                citadelHub: true,
                hasGuild: true,
                hasGuest: false,
                unreadDms: 3,
              ),
            ),
            'manyUnread': _rows(
              chatTabs(
                selected: ChatTab.dm,
                citadelHub: false,
                hasGuild: true,
                hasGuest: true,
                unreadDms: 12,
              ),
            ),
            'badges': <num>[0, 1, 9, 10, 99].map(unreadBadgeLabel).toList(),
            'localLocationIds': <String>[
              chatLocalLocationId('LOC-0002', false),
              chatLocalLocationId('LOC-0028', true),
            ],
            'channels': chatTabOrder
                .map(
                  (tab) => <String, Object?>{
                    'tab': tab.wire,
                    'withGuild': _channelJson(
                      chatChannelForTab(
                        tab,
                        locationId: 'LOC-0002',
                        citadelHub: false,
                        guildId: 'gld_1',
                        guestGuildId: 'gld_2',
                      ),
                    ),
                    'inCitadelWithoutGuild': _channelJson(
                      chatChannelForTab(
                        tab,
                        locationId: 'LOC-0028',
                        citadelHub: true,
                        guildId: null,
                      ),
                    ),
                  },
                )
                .toList(),
            'emptyMessages': chatTabOrder.map(emptyChatMessage).toList(),
            'hints': <String>[chatDmHint, chatNoGuildNotice, chatNoGuestNotice],
            'cursorKey': dmReadCursorKey('usr_0001'),
            'lines': _rows(chatLines(messages, 'usr_1')),
            'linesAnonymous': _rows(chatLines(messages, null)),
            'prefixed': _rows(
              chatLines(const <ChatMessage>[
                ChatMessage(
                  id: 'msg_3',
                  channelKey: 'global',
                  userId: 'usr_3',
                  username: 'Mira',
                  body: 'The road is clear.',
                  createdAt: '2026-08-12T21:00:10.000Z',
                  guildTag: 'WCH',
                ),
              ], 'usr_1'),
            ),
            'filtered': _rows(
              chatLines(
                const <ChatMessage>[
                  ChatMessage(
                    id: 'msg_4',
                    channelKey: 'global',
                    userId: 'usr_4',
                    username: 'Loud',
                    body: 'what the fuck',
                    createdAt: '2026-08-12T21:00:11.000Z',
                  ),
                ],
                null,
                filterProfanityEnabled: true,
              ),
            ),
            'guildRank': _rows(
              chatLines(const <ChatMessage>[
                ChatMessage(
                  id: 'msg_5',
                  channelKey: 'guild:gld_1',
                  userId: 'usr_3',
                  username: 'Mira',
                  body: 'Hold the gate.',
                  createdAt: '2026-08-12T21:00:12.000Z',
                  rankLabel: 'Leader',
                  rankIcon: '★',
                ),
              ], 'usr_1'),
            ),
            'guestLine': _rows(
              chatLines(const <ChatMessage>[
                ChatMessage(
                  id: 'msg_6',
                  channelKey: 'guild:gld_1',
                  userId: 'usr_5',
                  username: 'Wanderer',
                  body: 'Passing through.',
                  createdAt: '2026-08-12T21:00:13.000Z',
                  guest: true,
                ),
              ], null),
            ),
          }),
          isNull,
        );
      });
    }
  });

  group('presence view parity', () {
    for (final fixture in loadParityFixtures('social-views/presence')) {
      test(fixture.name, () {
        expect(
          checkParity(fixture, <String, Object?>{
            'peers': _rows(
              peerRows(<ActivityPresence>[
                _presence(),
                _presence(userId: 'usr_3', guildName: 'Iron League'),
                _presence(userId: 'usr_4', skillLevel: null),
                _presence(userId: 'usr_5', skillId: null, skillLevel: null, guildName: 'Oak Guard'),
                _presence(userId: 'usr_6', skillId: 'SKL-9999', skillLevel: 0),
              ], _skillName),
            ),
            'citadelSubtitles': <String>[
              citadelVisitorSubtitle(_presence()),
              citadelVisitorSubtitle(_presence(guildName: 'Iron League', skillLevel: null)),
              citadelVisitorSubtitle(_presence(guildName: 'Oak Guard', skillLevel: 0)),
            ],
            'profile': publicProfileView(_profile, _skillName).toJson(),
            'hiddenProfile': publicProfileView(
              PublicPlayerProfile(
                userId: _profile.userId,
                username: _profile.username,
                appearance: _profile.appearance,
                totalLevel: _profile.totalLevel,
                guildName: null,
                achievementsUnlocked: _profile.achievementsUnlocked,
                publicSkills: const <PublicSkillLine>[],
              ),
              _skillName,
            ).toJson(),
            'modeLines': <String>[
              multiplayerModeLine(MultiplayerMode.local),
              multiplayerModeLine(MultiplayerMode.supabase),
            ],
          }),
          isNull,
        );
      });
    }
  });

  group('bazaar view parity', () {
    for (final fixture in loadParityFixtures('bazaar/views')) {
      test(fixture.name, () {
        final posts = fixture
            .inputField<List<Object?>>('posts')
            .map((value) => BazaarPost.fromJson(asJsonMap(value)))
            .toList();
        expect(
          checkParity(fixture, <String, Object?>{
            'rows': bazaarRows(posts).map((row) => row.toJson()).toList(),
            'empty': bazaarRows(const <BazaarPost>[]).map((row) => row.toJson()).toList(),
            'kinds': bazaarKindOptions().map((option) => option.toJson()).toList(),
            'blurb': bazaarBlurb,
            'placeholder': bazaarPlaceholder,
            'maxLength': bazaarBodyMaxLength,
            'signInNotice': bazaarSignInNotice,
            'emptyHeading': bazaarEmptyHeading,
            'emptyBody': bazaarEmptyBody,
            'postedNotice': bazaarPostedNotice,
          }),
          isNull,
        );
      });
    }
  });

  group('citadel hub parity', () {
    for (final fixture in loadParityFixtures('citadel/hub')) {
      test(fixture.name, () {
        final locationIds = fixture
            .inputField<List<Object?>>('locationIds')
            .map((value) => value! as String)
            .toList();
        expect(
          checkParity(fixture, <String, Object?>{
            'districts': locationIds
                .map(
                  (locationId) => <String, Object?>{
                    'locationId': locationId,
                    'tabs': citadelHubTabsFor(locationId).map((tab) => tab.name).toList(),
                    'title': citadelHubTitleFor(locationId),
                  },
                )
                .toList(),
            'labels': <String, Object?>{
              for (final entry in citadelHubTabLabels.entries) entry.key.name: entry.value,
            },
          }),
          isNull,
        );
      });
    }
  });
}
