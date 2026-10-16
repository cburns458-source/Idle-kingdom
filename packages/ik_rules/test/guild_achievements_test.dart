import 'dart:io';

import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

const String _now = '2026-10-16T12:00:00.000Z';

void main() {
  test('keeps placeholder names in one catalog Quest can edit', () {
    expect(guildAchievements.map((row) => row.id).toList(), <String>[
      'gach_foundations',
      'gach_hall_2',
      'gach_hall_3',
      'gach_hall_4',
      'gach_hall_arcana',
      'gach_hall_5',
      'gach_gold_100k',
      'gach_gold_500k',
      'gach_materials',
      'gach_donors_10',
      'gach_donors_25',
      'gach_rising_strength',
    ]);
    expect(guildAchievements.map((row) => row.name).toList(), <String>[
      'Foundations laid',
      'Raised walls',
      'Under one roof',
      'Banners high',
      'Arcane corner',
      'A hall fit for kings',
      'Deep pockets',
      'Deeper pockets',
      'Stocked vault',
      'Many hands',
      'More hands',
      'Rising strength',
    ]);
    expect(
      guildAchievements.any(
        (row) => '${row.name} ${row.description}'.toLowerCase().contains('coffer'),
      ),
      isFalse,
    );
  });

  test('unlocks each hall step once, including arcana and the 1M cage', () {
    final first = evaluateGuildAchievements(
      const GuildAchievementSnapshot(
        completedTiers: <String>[guildHallTierBuild],
        goldContributed: 0,
      ),
      _now,
    );
    expect(first.newlyUnlocked, <String>['gach_foundations']);
    final again = evaluateGuildAchievements(
      GuildAchievementSnapshot(
        completedTiers: const <String>[guildHallTierBuild],
        goldContributed: 0,
        unlocked: first.unlocked,
      ),
      '2026-10-16T13:00:00.000Z',
    );
    expect(again.newlyUnlocked, isEmpty);
    expect(again.unlocked['gach_foundations'], _now);

    final done = evaluateGuildAchievements(
      GuildAchievementSnapshot(
        completedTiers: guildHallTiers.map((tier) => tier.id).toList(),
        goldContributed: 1000000,
      ),
      _now,
    );
    expect(
      done.newlyUnlocked,
      containsAll(<String>[
        'gach_foundations',
        'gach_hall_2',
        'gach_hall_3',
        'gach_hall_4',
        'gach_hall_arcana',
        'gach_hall_5',
        'gach_gold_100k',
        'gach_gold_500k',
      ]),
    );
    expect(done.progress.where((row) => row.id == 'gach_hall_5').single.unlocked, isTrue);
  });

  test('counts gold, hall-build materials, and distinct donors; bank deposits do not count', () {
    expect(
      guildAchievementCurrent(
        guildAchievements.firstWhere((row) => row.id == 'gach_gold_100k'),
        const GuildAchievementSnapshot(completedTiers: <String>[], goldContributed: 99999),
      ),
      99999,
    );
    final gold = evaluateGuildAchievements(
      const GuildAchievementSnapshot(
        completedTiers: <String>[],
        goldContributed: guildAchievementGold100k,
      ),
      _now,
    );
    expect(gold.newlyUnlocked, contains('gach_gold_100k'));
    expect(gold.newlyUnlocked, isNot(contains('gach_gold_500k')));

    const afterGarden = <String>[
      guildHallTierBuild,
      guildHallTierBank,
      guildHallTierBoxing,
      guildHallTierGarden,
    ];
    expect(guildHallMaterialsSpent(afterGarden), greaterThanOrEqualTo(guildAchievementMaterials));
    final vault = evaluateGuildAchievements(
      const GuildAchievementSnapshot(completedTiers: afterGarden, goldContributed: 0),
      _now,
    );
    expect(vault.newlyUnlocked, contains('gach_materials'));
    expect(guildHallMaterialsSpent(const <String>[guildHallTierBuild]), 1100);

    final donors = <String, num>{for (var i = 0; i < 10; i++) 'u$i': 1};
    final many = evaluateGuildAchievements(
      GuildAchievementSnapshot(
        completedTiers: const <String>[],
        goldContributed: 0,
        goldContributedBy: donors,
      ),
      _now,
    );
    expect(many.newlyUnlocked, contains('gach_donors_10'));
    expect(many.newlyUnlocked, isNot(contains('gach_donors_25')));
    expect(
      guildDonorIds(
        goldContributedBy: const <String, num>{'a': 5},
        donatedBy: const <String, bool>{'a': true, 'b': true},
      ),
      hasLength(2),
    );
  });

  test('unlocks rising strength at 25 members of total level 500', () {
    final short = evaluateGuildAchievements(
      const GuildAchievementSnapshot(
        completedTiers: <String>[],
        goldContributed: 0,
        membersAtLevel500: 24,
      ),
      _now,
    );
    expect(short.newlyUnlocked, isNot(contains('gach_rising_strength')));
    final reached = evaluateGuildAchievements(
      const GuildAchievementSnapshot(
        completedTiers: <String>[],
        goldContributed: 0,
        membersAtLevel500: 25,
      ),
      _now,
    );
    expect(reached.newlyUnlocked, <String>['gach_rising_strength']);
    final row = reached.progress.singleWhere((entry) => entry.id == 'gach_rising_strength');
    expect(row.current, 25);
    expect(row.target, 25);
    expect(row.unlocked, isTrue);
  });

  test('counts a member with no save as total level 0 for Rising strength', () {
    expect(guildMemberSaveTotalLevel(null), 0);
    expect(
      evaluateGuildAchievements(
        GuildAchievementSnapshot(
          completedTiers: const <String>[],
          goldContributed: 0,
          membersAtLevel500: guildMemberSaveTotalLevel(null),
        ),
        _now,
      ).newlyUnlocked,
      isNot(contains('gach_rising_strength')),
    );
  });

  test('skips the Rising strength member count once it is unlocked', () {
    expect(shouldCountRisingStrengthMembers(const <String, String>{}), isTrue);
    final reached = evaluateGuildAchievements(
      const GuildAchievementSnapshot(
        completedTiers: <String>[],
        goldContributed: 0,
        membersAtLevel500: 25,
      ),
      _now,
    );
    expect(shouldCountRisingStrengthMembers(reached.unlocked), isFalse);
    final skipped = evaluateGuildAchievements(
      GuildAchievementSnapshot(
        completedTiers: const <String>[],
        goldContributed: 0,
        membersAtLevel500: 0,
        unlocked: reached.unlocked,
      ),
      '2026-10-16T13:00:00.000Z',
    );
    expect(skipped.newlyUnlocked, isEmpty);
    expect(skipped.unlocked['gach_rising_strength'], _now);
    final sql = File(
      '${parityRepoRoot().path}/supabase/migrations/20261016190000_guild_achievements_skip_rising_count.sql',
    ).readAsStringSync();
    expect(
      sql.indexOf("a.achievement_id = 'gach_rising_strength'"),
      lessThan(sql.indexOf('bazaar_user_total_level')),
    );
    expect(sql, contains('v_new_level < 500 or v_old_level >= 500'));
  });

  test('keeps rising strength unlocked after a member leaves', () {
    // Vari: Rising strength stays unlocked after members leave.
    final reached = evaluateGuildAchievements(
      const GuildAchievementSnapshot(
        completedTiers: <String>[],
        goldContributed: 0,
        membersAtLevel500: 25,
      ),
      _now,
    );
    expect(reached.newlyUnlocked, <String>['gach_rising_strength']);
    final afterLeave = evaluateGuildAchievements(
      GuildAchievementSnapshot(
        completedTiers: const <String>[],
        goldContributed: 0,
        membersAtLevel500: 24,
        unlocked: reached.unlocked,
      ),
      '2026-10-16T13:00:00.000Z',
    );
    expect(afterLeave.newlyUnlocked, isEmpty);
    expect(afterLeave.unlocked['gach_rising_strength'], _now);
    expect(
      afterLeave.progress.singleWhere((entry) => entry.id == 'gach_rising_strength').unlocked,
      isTrue,
    );
  });

  test('SQL hall tier material costs match guildHallTierMaterialCount (202700 all six)', () {
    final sql = File(
      '${parityRepoRoot().path}/supabase/migrations/20261016170000_guild_achievements_and_banner.sql',
    ).readAsStringSync();
    final costs = <String, int>{
      for (final match in RegExp(r"when '([^']+)' then (\d+)").allMatches(sql))
        match.group(1)!: int.parse(match.group(2)!),
    };
    var sqlTotal = 0;
    var dartTotal = 0;
    for (final tier in guildHallTiers) {
      expect(costs[tier.id], guildHallTierMaterialCount(tier), reason: tier.id);
      sqlTotal += costs[tier.id] ?? 0;
      dartTotal += guildHallTierMaterialCount(tier).toInt();
    }
    expect(dartTotal, 202700);
    expect(sqlTotal, 202700);
    expect(guildHallMaterialsSpent(guildHallTiers.map((tier) => tier.id).toList()), 202700);
  });

  test('validates banner colours and requires unlocked emblem and border', () {
    expect(guildBannerPalette, isNot(contains('green')));
    expect(guildBannerPalette, isNot(contains('gold')));
    expect(guildMaySetBanner('leader'), isTrue);
    expect(guildMaySetBanner('officer'), isTrue);
    expect(guildMaySetBanner('veteran'), isFalse);
    expect(normalizeGuildBanner(null).ok, isTrue);
    expect(
      normalizeGuildBanner(<String, Object?>{'background': 'moss', 'accent': 'ivory'}).reason,
      guildBannerColourRefusal,
    );
    expect(
      normalizeGuildBanner(<String, Object?>{
        'background': 'slate',
        'accent': 'ivory',
        'emblem': 'emblem_foundations',
      }).reason,
      guildBannerEmblemRefusal,
    );
    final unlocked = normalizeGuildBanner(
      <String, Object?>{
        'background': 'wine',
        'accent': 'ivory',
        'emblem': 'emblem_foundations',
        'border': 'border_vault',
      },
      const <String>['gach_foundations', 'gach_materials'],
    );
    expect(unlocked.ok, isTrue);
    expect(unlocked.banner!.toJson(), <String, Object?>{
      'background': 'wine',
      'accent': 'ivory',
      'emblem': 'emblem_foundations',
      'border': 'border_vault',
    });
    expect(
      normalizeGuildBanner(
        <String, Object?>{'background': 'slate', 'accent': 'ivory', 'border': 'border_vault'},
        const <String>['gach_foundations'],
      ).reason,
      guildBannerBorderRefusal,
    );
  });
}
