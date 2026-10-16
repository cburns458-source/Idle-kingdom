import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

LocationRow _loc(String id) => LocationRow({'Location ID': id});

void main() {
  test('recruits cannot chip in gold; member and above can', () {
    expect(canPayGuildDebt('recruit'), isFalse);
    expect(canChipInGuildGold(''), isFalse);
    expect(canChipInGuildGold('member'), isTrue);
    expect(canChipInGuildGold('veteran'), isTrue);
    expect(canChipInGuildGold('officer'), isTrue);
    expect(canChipInGuildGold('leader'), isTrue);
  });

  test('a hall is built in six steps, in order', () {
    expect(guildHallTiers.map((tier) => tier.id), <String>[
      guildHallTierBuild,
      guildHallTierBank,
      guildHallTierBoxing,
      guildHallTierGarden,
      guildHallTierArcana,
      guildHallTierCage,
    ]);

    expect(nextGuildHallTier(const <String>[])?.id, guildHallTierBuild);
    expect(nextGuildHallTier(const <String>[guildHallTierBuild])?.id, guildHallTierBank);
    expect(
      nextGuildHallTier(const <String>[
        guildHallTierBuild,
        guildHallTierBank,
        guildHallTierBoxing,
        guildHallTierGarden,
        guildHallTierArcana,
        guildHallTierCage,
      ]),
      isNull,
    );
  });

  test('the first step asks for cedar logs and thread, and opens nothing', () {
    final build = guildHallTiers.first;
    expect(build.unlock, isNull);
    expect(build.goldThreshold, 0);
    expect(build.cost.map((cost) => (cost.itemId, cost.quantity)), <(String, num)>[
      ('ITEM-0015', 1000),
      ('ITEM-0095', 100),
    ]);
  });

  test('room tiers use the listed materials, gold marks, and display costs', () {
    expect(guildHallGoldMarks, <num>[10000, 40000, 130000, 400000, 1000000]);
    expect(guildHallTiers.skip(1).map((tier) => tier.goldThreshold), guildHallGoldMarks);
    expect(guildHallTiers.skip(1).map((tier) => tier.goldCost), <num>[
      10000,
      30000,
      90000,
      270000,
      600000,
    ]);
    expect(guildHallTiers[1].cost.map((cost) => (cost.itemId, cost.quantity)), <(String, num)>[
      ('ITEM-0017', 24000),
      ('ITEM-0002', 10000),
      ('ITEM-0006', 6320),
    ]);
  });

  test('the bank comes with Counting Room and later rooms with their own tiers', () {
    expect(guildHallBankUnlocked(const <String>[]), isFalse);
    expect(guildHallBankUnlocked(const <String>[guildHallTierBuild]), isFalse);
    expect(guildHallBankUnlocked(const <String>[guildHallTierBank]), isTrue);
    expect(guildHallBoxingUnlocked(const <String>[guildHallTierBoxing]), isTrue);
    expect(guildHallGardenUnlocked(const <String>[guildHallTierGarden]), isTrue);
    expect(guildHallArcanaUnlocked(const <String>[guildHallTierArcana]), isTrue);
    expect(guildHallCageUnlocked(const <String>[guildHallTierCage]), isTrue);
  });

  test('a step reads its progress out of the store house', () {
    final build = guildHallTiers.first;
    final needs = guildHallTierNeeds(build, const <InventoryStack>[
      InventoryStack(itemId: 'ITEM-0015', quantity: 400),
      InventoryStack(itemId: 'ITEM-0015', quantity: 200),
      InventoryStack(itemId: 'ITEM-0031', quantity: 900),
    ]);

    expect(needs.first.have, 600);
    expect(needs.first.met, isFalse);
    expect(needs.last.have, 0);
    expect(guildHallTierMet(build, const <InventoryStack>[]), isFalse);
  });

  test('progress never reads past what the step asked for', () {
    final build = guildHallTiers.first;
    final needs = guildHallTierNeeds(build, const <InventoryStack>[
      InventoryStack(itemId: 'ITEM-0015', quantity: 5000),
    ]);
    expect(needs.first.have, 5000);
    expect(needs.first.counted, 1000);
  });

  test('finishing a step spends its materials and leaves the rest', () {
    final build = guildHallTiers.first;
    final store = <InventoryStack>[
      const InventoryStack(itemId: 'ITEM-0015', quantity: 1200),
      const InventoryStack(itemId: 'ITEM-0095', quantity: 100),
      const InventoryStack(itemId: 'ITEM-0031', quantity: 3),
    ];
    expect(guildHallTierMet(build, store), isTrue);

    final settled = settleGuildHallTiers(store, const <String>[]);
    expect(settled.finishedNow.map((tier) => tier.id), <String>[guildHallTierBuild]);
    expect(settled.completedTiers, <String>[guildHallTierBuild]);
    expect(settled.storehouse.map((stack) => (stack.itemId, stack.quantity)), <(String, num)>[
      ('ITEM-0015', 200),
      ('ITEM-0031', 3),
    ]);
  });

  test('a room tier needs gold as well as materials', () {
    final settled = settleGuildHallTiers(const <InventoryStack>[
      InventoryStack(itemId: 'ITEM-0015', quantity: 1000),
      InventoryStack(itemId: 'ITEM-0095', quantity: 100),
      InventoryStack(itemId: 'ITEM-0017', quantity: 24000),
      InventoryStack(itemId: 'ITEM-0002', quantity: 10000),
      InventoryStack(itemId: 'ITEM-0006', quantity: 6320),
    ], const <String>[]);

    expect(settled.finishedNow.map((tier) => tier.id), <String>[guildHallTierBuild]);
    expect(guildHallBankUnlocked(settled.completedTiers), isFalse);

    final withGold = settleGuildHallTiers(settled.storehouse, settled.completedTiers, 10000);
    expect(withGold.finishedNow.map((tier) => tier.id), <String>[guildHallTierBank]);
    expect(guildHallBankUnlocked(withGold.completedTiers), isTrue);
  });

  test('a step already finished is not paid for twice', () {
    final settled = settleGuildHallTiers(
      const <InventoryStack>[
        InventoryStack(itemId: 'ITEM-0015', quantity: 1000),
        InventoryStack(itemId: 'ITEM-0095', quantity: 100),
      ],
      const <String>[guildHallTierBuild],
    );

    expect(settled.finishedNow, isEmpty);
    expect(settled.storehouse, hasLength(2));
  });

  test('chip-ins cap at 1M and migrate old paid debt into the running total', () {
    expect(guildHallGoldChipInCap(0), guildHallGoldCap);
    expect(guildHallGoldChipInCap(400000), 600000);
    expect(goldContributedFromDebtRemaining(600000), 400000);
    expect(goldContributedFromDebtRemaining(0), guildHallGoldCap);
  });

  test('the next step names how much of an item it will still take', () {
    const store = <InventoryStack>[InventoryStack(itemId: 'ITEM-0015', quantity: 400)];
    expect(guildHallDonationCap(const <String>[], store, 'ITEM-0015'), 600);
    expect(guildHallDonationCap(const <String>[], store, 'ITEM-0095'), 100);
    expect(guildHallDonationCap(const <String>[], store, 'ITEM-0031'), 0);
  });

  test('finish lines match the listed copy and never say coffer', () {
    expect(guildHallTierFinishLines, {
      guildHallTierBank: 'The counting room is open for business.',
      guildHallTierBoxing: 'The ring is roped off. Settle your differences in there.',
      guildHallTierGarden: "Soil's in, and the hall smells of earth now.",
      guildHallTierArcana: 'The Arcana station hums to life in the corner.',
      guildHallTierCage: 'Something big is rattling the cage. Mind your fingers.',
    });
    expect(guildHallTierFinishLine(guildHallTierBank), 'The counting room is open for business.');
    expect(
      guildHallTierFinishLine(guildHallTierBoxing),
      'The ring is roped off. Settle your differences in there.',
    );
    expect(
      guildHallTierFinishLine(guildHallTierGarden),
      "Soil's in, and the hall smells of earth now.",
    );
    expect(
      guildHallTierFinishLine(guildHallTierArcana),
      'The Arcana station hums to life in the corner.',
    );
    expect(
      guildHallTierFinishLine(guildHallTierCage),
      'Something big is rattling the cage. Mind your fingers.',
    );
    expect(guildHallTierFinishLine(guildHallTierBuild), isNull);
    expect(guildHallTierFinishLines.values.join(' ').toLowerCase(), isNot(contains('coffer')));
  });

  test('guild_may defaults: leader always, officers withdraw and move', () {
    final table = defaultGuildPermissionTable();
    expect(guildMay('leader', guildPermissionWithdraw, table), isTrue);
    expect(guildMay('officer', guildPermissionWithdraw, table), isTrue);
    expect(guildMay('member', guildPermissionWithdraw, table), isFalse);
    expect(guildMay('officer', guildPermissionMoveUpForGrabs, table), isTrue);
    expect(guildMay('recruit', guildPermissionDeposit, table), isTrue);
    expect(guildBankTotalLevelRequired, 200);
  });

  test('merges consecutive donation batches from one player', () {
    const first = GuildLogEntry(
      id: '1',
      guildId: 'g',
      kind: guildLogKindDonation,
      createdAt: 't',
      actorUserId: 'u1',
      actorUsername: 'Ada',
      message: '',
      gold: 50,
      items: <GuildLogDonationItem>[GuildLogDonationItem(itemId: 'ITEM-0002', quantity: 10)],
    );
    final merged = mergeGuildLogDonation(
      first,
      first.copyWith(
        gold: 25,
        items: const <GuildLogDonationItem>[GuildLogDonationItem(itemId: 'ITEM-0002', quantity: 5)],
      ),
    );
    expect(merged.merged, isTrue);
    expect(merged.entry!.gold, 75);
    expect(merged.entry!.items.single.quantity, 15);
  });

  test('applies a flat 5% company XP bonus', () {
    expect(applyGuildHallCompanyXp(1000, false), 1000);
    expect(applyGuildHallCompanyXp(1000, true), 1050);
  });

  test('only the guild hall location offers hall services', () {
    expect(locationHasGuildHall(_loc(guildHallLocationId)), isTrue);
    expect(locationHasGuildHall(_loc(citadelPlazaId)), isFalse);
    expect(locationHasGuildHall(null), isFalse);
  });
}
