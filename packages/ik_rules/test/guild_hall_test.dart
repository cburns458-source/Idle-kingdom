import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

LocationRow _loc(String id) => LocationRow({'Location ID': id});

void main() {
  test('recruits cannot pay the hall debt; member and above can', () {
    expect(canPayGuildDebt('recruit'), isFalse);
    expect(canPayGuildDebt('member'), isTrue);
    expect(canPayGuildDebt('veteran'), isTrue);
    expect(canPayGuildDebt('officer'), isTrue);
    expect(canPayGuildDebt('leader'), isTrue);
  });

  test('a hall is built in three steps, in order', () {
    expect(guildHallTiers.map((tier) => tier.id), <String>[
      guildHallTierBuild,
      guildHallTierBank,
      guildHallTierBoxing,
    ]);

    expect(nextGuildHallTier(const <String>[])?.id, guildHallTierBuild);
    expect(nextGuildHallTier(const <String>[guildHallTierBuild])?.id, guildHallTierBank);
    expect(
      nextGuildHallTier(const <String>[guildHallTierBuild, guildHallTierBank])?.id,
      guildHallTierBoxing,
    );
    expect(
      nextGuildHallTier(const <String>[guildHallTierBuild, guildHallTierBank, guildHallTierBoxing]),
      isNull,
    );
  });

  test('the first step asks for cedar logs and plant fibre, and opens nothing', () {
    final build = guildHallTiers.first;
    expect(build.unlock, isNull);
    expect(build.cost.map((cost) => (cost.itemId, cost.quantity)), <(String, num)>[
      ('ITEM-0015', 1000),
      ('ITEM-0095', 100),
    ]);
  });

  test('the bank comes with the second step and the ring with the third', () {
    expect(guildHallBankUnlocked(const <String>[]), isFalse);
    expect(guildHallBankUnlocked(const <String>[guildHallTierBuild]), isFalse);
    expect(guildHallBankUnlocked(const <String>[guildHallTierBank]), isTrue);

    expect(guildHallBoxingUnlocked(const <String>[guildHallTierBank]), isFalse);
    expect(guildHallBoxingUnlocked(const <String>[guildHallTierBoxing]), isTrue);
  });

  test('a step reads its progress out of the store house', () {
    final build = guildHallTiers.first;
    final needs = guildHallTierNeeds(build, const <InventoryStack>[
      InventoryStack(itemId: 'ITEM-0015', quantity: 400),
      InventoryStack(itemId: 'ITEM-0015', quantity: 200),
      InventoryStack(itemId: 'ITEM-0031', quantity: 900),
    ]);

    // Stacks of the same item add up; an item the step does not want is ignored.
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
    expect(
      settled.storehouse.map((stack) => (stack.itemId, stack.quantity)),
      // The 200 cedar logs over the asking price stay, the fibre is all spent.
      <(String, num)>[('ITEM-0015', 200), ('ITEM-0031', 3)],
    );
  });

  test('one large donation can finish more than one step', () {
    final settled = settleGuildHallTiers(const <InventoryStack>[
      InventoryStack(itemId: 'ITEM-0015', quantity: 1000),
      InventoryStack(itemId: 'ITEM-0095', quantity: 400),
      InventoryStack(itemId: 'ITEM-0017', quantity: 1300),
      InventoryStack(itemId: 'ITEM-0002', quantity: 500),
      InventoryStack(itemId: 'ITEM-0006', quantity: 100),
    ], const <String>[]);

    expect(settled.finishedNow.map((tier) => tier.id), <String>[
      guildHallTierBuild,
      guildHallTierBank,
      guildHallTierBoxing,
    ]);
    expect(guildHallBankUnlocked(settled.completedTiers), isTrue);
    expect(guildHallBoxingUnlocked(settled.completedTiers), isTrue);
    expect(settled.storehouse, isEmpty);
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

  test('the next step names how much of an item it will still take', () {
    const store = <InventoryStack>[InventoryStack(itemId: 'ITEM-0015', quantity: 400)];
    expect(guildHallDonationCap(const <String>[], store, 'ITEM-0015'), 600);
    expect(guildHallDonationCap(const <String>[], store, 'ITEM-0095'), 100);
    expect(guildHallDonationCap(const <String>[], store, 'ITEM-0031'), 0);
    expect(
      guildHallDonationCap(
        const <String>[guildHallTierBuild, guildHallTierBank, guildHallTierBoxing],
        const <InventoryStack>[],
        'ITEM-0015',
      ),
      0,
    );
  });

  test('only the guild hall location offers hall services', () {
    expect(locationHasGuildHall(_loc(guildHallLocationId)), isTrue);
    expect(locationHasGuildHall(_loc(citadelPlazaId)), isFalse);
    expect(locationHasGuildHall(null), isFalse);
  });
}
