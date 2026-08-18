import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_parity/ik_parity.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';
import 'package:test/test.dart';

void main() {
  late GameDatabase database;

  setUpAll(() {
    database = assertGameDatabaseShape(contentDatabaseJson());
  });

  test('Member can pay hall debt, recruit cannot, payoff says the debt is gone', () {
    final backend = LocalMultiplayerBackend(storage: MemorySaveStorage());
    final leader = backend.signUp('leader@example.com', 'Leader', 'secret').session!;
    var save = createNewSave(database, 1).copyWith(gold: 2 * guildHallDebtGold);
    backend.writeCloudSave(leader.userId, save);
    final created = backend.createGuild(
      leader,
      const CreateGuildInput(
        name: 'Oak',
        tag: 'OAK',
        description: '',
        emblem: GuildEmblem(color: '#2f6b3a', symbol: 'tree'),
      ),
      save.gold,
    );
    expect(created.ok, isTrue);
    save = save.copyWith(gold: save.gold - created.goldCost!);

    final hall = backend.guildHall(created.guild!.id)!;
    expect(hall.debtRemaining, guildHallDebtGold);
    expect(hall.boxingUnlocked, isFalse);

    final recruit = backend.signUp('recruit@example.com', 'Recruit', 'secret').session!;
    backend.applyToGuild(recruit, created.guild!.id, '');
    backend.setMemberRole(leader.userId, created.guild!.id, recruit.userId, guildRoleRecruit);
    final recruitSave = createNewSave(database, 1).copyWith(gold: guildHallDebtGold);
    final blocked = backend.payGuildDebt(recruit.userId, recruitSave, 100);
    expect(blocked.ok, isFalse);
    expect(blocked.reason, 'Recruits cannot pay the hall debt.');

    final paid = backend.payGuildDebt(leader.userId, save, guildHallDebtGold);
    expect(paid.ok, isTrue);
    expect(paid.paidOffJustNow, isTrue);
    expect(paid.hall!.debtPaidOff, isTrue);
    expect(paid.hall!.debtRemaining, 0);
    expect(paid.save!.gold, save.gold - guildHallDebtGold);
  });

  test('a donation fills the store house and stays there until a tier is met', () {
    final backend = LocalMultiplayerBackend(storage: MemorySaveStorage());
    final leader = backend.signUp('leader@example.com', 'Leader', 'secret').session!;
    var save = createNewSave(database, 1).copyWith(
      gold: guildCreateGoldCost + 10,
      inventory: const [InventoryStack(itemId: 'ITEM-0015', quantity: 60)],
    );
    backend.writeCloudSave(leader.userId, save);
    final created = backend.createGuild(
      leader,
      const CreateGuildInput(
        name: 'Oak',
        tag: 'OAK',
        description: '',
        emblem: GuildEmblem(color: '#2f6b3a', symbol: 'tree'),
      ),
      save.gold,
    );
    save = save.copyWith(gold: save.gold - created.goldCost!);

    final deposited = backend.contributeHallItem(leader.userId, save, 0, 50);
    expect(deposited.ok, isTrue);
    expect(deposited.tiersFinishedNow, isEmpty);
    expect(deposited.hall!.completedTiers, isEmpty);
    expect(deposited.hall!.storehouse.single.quantity, 50);
    expect(deposited.save!.inventory.single.quantity, 10);
  });

  test('a donation that covers the first tier builds the hall and spends it', () {
    final backend = LocalMultiplayerBackend(storage: MemorySaveStorage());
    final leader = backend.signUp('leader@example.com', 'Leader', 'secret').session!;
    var save = createNewSave(database, 1).copyWith(
      gold: guildCreateGoldCost + 10,
      inventory: const [
        InventoryStack(itemId: 'ITEM-0015', quantity: 1000),
        InventoryStack(itemId: 'ITEM-0095', quantity: 140),
      ],
    );
    backend.writeCloudSave(leader.userId, save);
    final created = backend.createGuild(
      leader,
      const CreateGuildInput(
        name: 'Oak',
        tag: 'OAK',
        description: '',
        emblem: GuildEmblem(color: '#2f6b3a', symbol: 'tree'),
      ),
      save.gold,
    );
    save = save.copyWith(gold: save.gold - created.goldCost!);

    final logs = backend.contributeHallItem(leader.userId, save, 0, 1000);
    expect(logs.ok, isTrue);
    expect(logs.tiersFinishedNow, isEmpty);
    save = logs.save!;

    final fibre = backend.contributeHallItem(leader.userId, save, 0, 140);
    expect(fibre.ok, isTrue);
    expect(fibre.tiersFinishedNow, <String>[guildHallTierBuild]);
    // The build spent what it asked for; the 40 spare fibre is still in there.
    expect(fibre.hall!.storehouse.map((stack) => (stack.itemId, stack.quantity)), <(String, num)>[
      ('ITEM-0095', 40),
    ]);
    // The hall itself opens nothing: the bank and the ring come later.
    expect(fibre.hall!.bankUnlocked, isFalse);
    expect(fibre.hall!.boxingUnlocked, isFalse);
  });

  test('the bank opens on the second tier and the ring on the third', () {
    final backend = LocalMultiplayerBackend(storage: MemorySaveStorage());
    final leader = backend.signUp('leader@example.com', 'Leader', 'secret').session!;
    var save = createNewSave(database, 1).copyWith(
      gold: guildCreateGoldCost + 10,
      inventory: const [
        InventoryStack(itemId: 'ITEM-0015', quantity: 1000),
        InventoryStack(itemId: 'ITEM-0095', quantity: 400),
        InventoryStack(itemId: 'ITEM-0017', quantity: 1300),
        InventoryStack(itemId: 'ITEM-0002', quantity: 500),
        InventoryStack(itemId: 'ITEM-0006', quantity: 100),
      ],
    );
    backend.writeCloudSave(leader.userId, save);
    final created = backend.createGuild(
      leader,
      const CreateGuildInput(
        name: 'Oak',
        tag: 'OAK',
        description: '',
        emblem: GuildEmblem(color: '#2f6b3a', symbol: 'tree'),
      ),
      save.gold,
    );
    save = save.copyWith(gold: save.gold - created.goldCost!);

    GuildHallActionResult? last;
    // Always the first stack: each donation empties one and shortens the bag.
    while (save.inventory.isNotEmpty) {
      final stack = save.inventory.first;
      last = backend.contributeHallItem(leader.userId, save, 0, stack.quantity);
      expect(last.ok, isTrue);
      save = last.save!;
    }

    expect(last!.hall!.completedTiers, <String>[
      guildHallTierBuild,
      guildHallTierBank,
      guildHallTierBoxing,
    ]);
    expect(last.hall!.bankUnlocked, isTrue);
    expect(last.hall!.boxingUnlocked, isTrue);
    expect(last.hall!.storehouse, isEmpty);
  });
}
