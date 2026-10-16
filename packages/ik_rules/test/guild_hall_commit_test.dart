import 'package:ik_rules/ik_rules.dart';
import 'package:test/test.dart';

const List<String> _allTiers = <String>[
  guildHallTierBuild,
  guildHallTierBank,
  guildHallTierBoxing,
  guildHallTierGarden,
  guildHallTierArcana,
  guildHallTierCage,
];

void main() {
  test('credits only gold the hosted save actually lost', () {
    expect(goldTakenFromPlayerSaves(500, 400), 100);
    expect(goldTakenFromPlayerSaves(400, 400), 0);
    expect(goldTakenFromPlayerSaves(100, 250), 0);
  });

  test('ignores a forged gold_contributed total when the save did not pay', () {
    final committed = commitGuildHallFromPlayerSaves(
      previousGold: 500,
      nextGold: 500,
      previousInventory: const <InventoryStack>[],
      nextInventory: const <InventoryStack>[],
      hallGoldContributed: 0,
      userId: 'u1',
      proposal: const GuildHallCommitProposal(
        goldContributed: guildHallGoldCap,
        completedTiers: _allTiers,
      ),
    );
    expect(committed.goldTaken, 0);
    expect(committed.goldContributed, 0);
    expect(committed.completedTiers, isEmpty);
    expect(committed.finishedNow, isEmpty);
  });

  test('adds only the gold deducted from the save, even if the payload claims the cap', () {
    final committed = commitGuildHallFromPlayerSaves(
      previousGold: 250,
      nextGold: 200,
      previousInventory: const <InventoryStack>[],
      nextInventory: const <InventoryStack>[],
      hallGoldContributed: 50,
      userId: 'u1',
      proposal: const GuildHallCommitProposal(goldContributed: guildHallGoldCap),
    );
    expect(committed.goldTaken, 50);
    expect(committed.goldContributed, 100);
    expect(committed.goldContributedBy['u1'], 50);
  });

  test('settles Build the Hall from donated materials, not from claimed completed_tiers', () {
    final forged = commitGuildHallFromPlayerSaves(
      previousGold: 0,
      nextGold: 0,
      previousInventory: const <InventoryStack>[
        InventoryStack(itemId: 'ITEM-0015', quantity: 1000),
        InventoryStack(itemId: 'ITEM-0095', quantity: 100),
      ],
      nextInventory: const <InventoryStack>[
        InventoryStack(itemId: 'ITEM-0015', quantity: 1000),
        InventoryStack(itemId: 'ITEM-0095', quantity: 100),
      ],
      hallGoldContributed: 0,
      userId: 'u1',
      proposal: const GuildHallCommitProposal(completedTiers: _allTiers),
    );
    expect(forged.completedTiers, isEmpty);
    expect(forged.storehouse, isEmpty);

    final honest = commitGuildHallFromPlayerSaves(
      previousGold: 0,
      nextGold: 0,
      previousInventory: const <InventoryStack>[
        InventoryStack(itemId: 'ITEM-0015', quantity: 1000),
        InventoryStack(itemId: 'ITEM-0095', quantity: 100),
      ],
      nextInventory: const <InventoryStack>[],
      hallGoldContributed: 0,
      userId: 'u1',
      proposal: const GuildHallCommitProposal(completedTiers: _allTiers),
    );
    expect(honest.completedTiers, <String>[guildHallTierBuild]);
    expect(honest.finishedNow, <String>[guildHallTierBuild]);
    expect(honest.storehouse, isEmpty);
  });

  test('does not finish Counting Room until the gold total is actually chipped in', () {
    final materials = commitGuildHallFromPlayerSaves(
      previousGold: 10000,
      nextGold: 10000,
      previousInventory: const <InventoryStack>[
        InventoryStack(itemId: 'ITEM-0015', quantity: 1000),
        InventoryStack(itemId: 'ITEM-0095', quantity: 100),
        InventoryStack(itemId: 'ITEM-0017', quantity: 24000),
        InventoryStack(itemId: 'ITEM-0002', quantity: 10000),
        InventoryStack(itemId: 'ITEM-0006', quantity: 6320),
      ],
      nextInventory: const <InventoryStack>[],
      hallGoldContributed: 0,
      userId: 'u1',
      proposal: const GuildHallCommitProposal(
        goldContributed: 10000,
        completedTiers: <String>[guildHallTierBuild, guildHallTierBank],
      ),
    );
    expect(materials.goldContributed, 0);
    expect(materials.completedTiers, <String>[guildHallTierBuild]);
    expect(materials.storehouse.map((stack) => (stack.itemId, stack.quantity)), <(String, num)>[
      ('ITEM-0017', 24000),
      ('ITEM-0002', 10000),
      ('ITEM-0006', 6320),
    ]);
  });

  test('ignores extra stacks a forged storehouse tries to invent', () {
    final committed = commitGuildHallFromPlayerSaves(
      previousGold: 0,
      nextGold: 0,
      previousInventory: const <InventoryStack>[],
      nextInventory: const <InventoryStack>[],
      hallGoldContributed: 0,
      userId: 'u1',
      proposal: const GuildHallCommitProposal(
        storehouse: <InventoryStack>[InventoryStack(itemId: 'ITEM-0015', quantity: 1000)],
        completedTiers: <String>[guildHallTierBuild],
      ),
    );
    expect(committed.storehouse, isEmpty);
    expect(committed.completedTiers, isEmpty);
  });

  test('does not treat catch-up ore, food, arrows, or gold as hall credit', () {
    const hostedInventory = <InventoryStack>[
      InventoryStack(itemId: 'ITEM-0003', quantity: 10),
      InventoryStack(itemId: 'ITEM-0058', quantity: 5),
      InventoryStack(itemId: 'ITEM-ARROWS', quantity: 8),
      InventoryStack(itemId: 'ITEM-0015', quantity: 3),
    ];
    const caughtUpInventory = <InventoryStack>[
      InventoryStack(itemId: 'ITEM-0003', quantity: 7),
      InventoryStack(itemId: 'ITEM-0058', quantity: 3),
      InventoryStack(itemId: 'ITEM-ARROWS', quantity: 5),
      InventoryStack(itemId: 'ITEM-0015', quantity: 3),
    ];
    final afterInventory = <InventoryStack>[
      InventoryStack(itemId: 'ITEM-0003', quantity: 7),
      InventoryStack(itemId: 'ITEM-0058', quantity: 3),
      InventoryStack(itemId: 'ITEM-ARROWS', quantity: 5),
      InventoryStack(itemId: 'ITEM-0015', quantity: 2),
    ];

    final naive = commitGuildHallFromPlayerSaves(
      previousGold: 100,
      nextGold: 90,
      previousInventory: hostedInventory,
      nextInventory: afterInventory,
      hallGoldContributed: 0,
      userId: 'u1',
    );
    expect(naive.ok, isTrue);
    expect(naive.goldTaken, 10);
    expect(naive.storehouse.map((stack) => (stack.itemId, stack.quantity)), <(String, num)>[
      ('ITEM-0003', 3),
      ('ITEM-0058', 2),
      ('ITEM-ARROWS', 3),
      ('ITEM-0015', 1),
    ]);

    final fromCaughtUp = commitGuildHallFromPlayerSaves(
      previousGold: 130,
      nextGold: 90,
      previousInventory: caughtUpInventory,
      nextInventory: afterInventory,
      hallGoldContributed: 0,
      userId: 'u1',
    );
    expect(fromCaughtUp.ok, isTrue);
    expect(fromCaughtUp.goldTaken, 40);
    expect(fromCaughtUp.storehouse.map((stack) => (stack.itemId, stack.quantity)), <(String, num)>[
      ('ITEM-0015', 1),
    ]);
  });

  test('refuses gold past the cap instead of truncating it', () {
    final overpay = commitGuildHallFromPlayerSaves(
      previousGold: 500,
      nextGold: 200,
      previousInventory: const <InventoryStack>[],
      nextInventory: const <InventoryStack>[],
      hallGoldContributed: 999900,
      userId: 'u1',
    );
    expect(overpay.ok, isFalse);
    expect(overpay.reason, 'That would go past the gold cap.');

    final atCap = commitGuildHallFromPlayerSaves(
      previousGold: 80,
      nextGold: 70,
      previousInventory: const <InventoryStack>[],
      nextInventory: const <InventoryStack>[],
      hallGoldContributed: guildHallGoldCap,
      userId: 'u1',
    );
    expect(atCap.ok, isFalse);
    expect(atCap.reason, 'The gold total is already at its cap.');
  });

  test('refuses a bank change that does not match the save', () {
    final refused = commitGuildHallFromPlayerSaves(
      previousGold: 40,
      nextGold: 40,
      previousInventory: const <InventoryStack>[InventoryStack(itemId: 'ITEM-0015', quantity: 5)],
      nextInventory: const <InventoryStack>[InventoryStack(itemId: 'ITEM-0015', quantity: 5)],
      hallGoldContributed: 0,
      userId: 'u1',
      proposal: const GuildHallCommitProposal(
        bankItems: <InventoryStack>[InventoryStack(itemId: 'ITEM-0015', quantity: 1)],
      ),
    );
    expect(refused.ok, isFalse);
    expect(refused.reason, guildHallBankMismatchRefusal);
  });
}
