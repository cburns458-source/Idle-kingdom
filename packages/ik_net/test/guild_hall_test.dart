import 'dart:convert';

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

  test('Member can chip in gold, recruit cannot, a 1M chip-in caps the total', () {
    final backend = LocalMultiplayerBackend(storage: MemorySaveStorage());
    final leader = backend.signUp('leader@example.com', 'Leader', 'secret').session!;
    var save = createNewSave(database, 1).copyWith(gold: 2 * guildHallGoldCap);
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
    expect(hall.goldContributed, 0);
    expect(hall.debtRemaining, guildHallGoldCap);
    expect(hall.boxingUnlocked, isFalse);

    final recruit = backend.signUp('recruit@example.com', 'Recruit', 'secret').session!;
    backend.applyToGuild(recruit, created.guild!.id, '');
    backend.setMemberRole(leader.userId, created.guild!.id, recruit.userId, guildRoleRecruit);
    final recruitSave = createNewSave(database, 1).copyWith(gold: guildHallGoldCap);
    final blocked = backend.payGuildDebt(recruit.userId, recruitSave, 100);
    expect(blocked.ok, isFalse);
    expect(blocked.reason, 'Recruits cannot chip in gold.');

    final short = backend.payGuildDebt(leader.userId, save.copyWith(gold: 50), 100);
    expect(short.ok, isFalse);
    expect(short.reason, guildHallNotEnoughGold);

    final overpay = backend.payGuildDebt(leader.userId, save, guildHallGoldCap + 1);
    expect(overpay.ok, isFalse);
    expect(overpay.reason, guildHallGoldOverpayRefusal);
    expect(overpay.save, isNull);

    final paid = backend.payGuildDebt(leader.userId, save, guildHallGoldCap);
    expect(paid.ok, isTrue);
    expect(paid.paidOffJustNow, isTrue);
    expect(paid.hall!.goldContributed, guildHallGoldCap);
    expect(paid.hall!.debtRemaining, 0);
    expect(paid.save!.gold, save.gold - guildHallGoldCap);

    final again = backend.payGuildDebt(leader.userId, paid.save!, 10);
    expect(again.ok, isFalse);
    expect(again.reason, guildHallGoldCapRefusal);
    expect(paid.save!.gold, save.gold - guildHallGoldCap);
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
    // The step took what it still needed; the extra 40 fibre stayed in the bag.
    expect(fibre.hall!.storehouse, isEmpty);
    expect(fibre.save!.inventory.single.quantity, 40);
    // The hall itself opens nothing: the bank and the ring come later.
    expect(fibre.hall!.bankUnlocked, isFalse);
    expect(fibre.hall!.boxingUnlocked, isFalse);
  });

  test('the counting room needs gold and materials; boxing waits on the next mark', () {
    final backend = LocalMultiplayerBackend(storage: MemorySaveStorage());
    final leader = backend.signUp('leader@example.com', 'Leader', 'secret').session!;
    var save = createNewSave(database, 1).copyWith(
      gold: guildCreateGoldCost + 10000,
      inventory: const [
        InventoryStack(itemId: 'ITEM-0015', quantity: 1000),
        InventoryStack(itemId: 'ITEM-0095', quantity: 100),
        InventoryStack(itemId: 'ITEM-0017', quantity: 24000),
        InventoryStack(itemId: 'ITEM-0002', quantity: 10000),
        InventoryStack(itemId: 'ITEM-0006', quantity: 6320),
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
    var hall = backend.guildHall(created.guild!.id)!;
    while (true) {
      hall = last?.hall ?? hall;
      final index = save.inventory.indexWhere(
        (stack) => guildHallDonationCap(hall.completedTiers, hall.storehouse, stack.itemId) > 0,
      );
      if (index < 0) break;
      final cap = guildHallDonationCap(
        hall.completedTiers,
        hall.storehouse,
        save.inventory[index].itemId,
      );
      last = backend.contributeHallItem(leader.userId, save, index, cap);
      expect(last.ok, isTrue, reason: last.reason);
      save = last.save!;
    }

    expect(last!.hall!.completedTiers, <String>[guildHallTierBuild]);
    expect(last.hall!.bankUnlocked, isFalse);

    final chipped = backend.payGuildDebt(leader.userId, save, 10000);
    expect(chipped.ok, isTrue, reason: chipped.reason);
    expect(chipped.hall!.completedTiers, <String>[guildHallTierBuild, guildHallTierBank]);
    expect(chipped.hall!.bankUnlocked, isTrue);
    expect(chipped.hall!.boxingUnlocked, isFalse);
    expect(chipped.goldChipped, 10000);
  });

  test('a stack the next step does not want stays in the bag', () {
    final backend = LocalMultiplayerBackend(storage: MemorySaveStorage());
    final leader = backend.signUp('leader@example.com', 'Leader', 'secret').session!;
    final save = createNewSave(database, 1).copyWith(
      gold: guildCreateGoldCost + 10,
      inventory: const [InventoryStack(itemId: 'ITEM-0031', quantity: 8)],
    );
    backend.writeCloudSave(leader.userId, save);
    backend.createGuild(
      leader,
      const CreateGuildInput(
        name: 'Oak',
        tag: 'OAK',
        description: '',
        emblem: GuildEmblem(color: '#2f6b3a', symbol: 'tree'),
      ),
      save.gold,
    );

    final refused = backend.contributeHallItem(leader.userId, save, 0, 8);
    expect(refused.ok, isFalse);
    expect(refused.reason, guildHallUnneededRefusal);
    expect(save.inventory.single.quantity, 8);
  });

  test('the guild bank takes tradeable items and Up for grabs has one taker', () {
    final backend = LocalMultiplayerBackend(storage: MemorySaveStorage());
    final leader = backend.signUp('leader@example.com', 'Leader', 'secret').session!;
    var save = _withTotalLevel(
      createNewSave(database, 1).copyWith(
        gold: guildCreateGoldCost + 10000,
        inventory: const [
          InventoryStack(itemId: 'ITEM-0015', quantity: 1000),
          InventoryStack(itemId: 'ITEM-0095', quantity: 100),
          InventoryStack(itemId: 'ITEM-0017', quantity: 24000),
          InventoryStack(itemId: 'ITEM-0002', quantity: 10000),
          InventoryStack(itemId: 'ITEM-0006', quantity: 6320),
          InventoryStack(itemId: 'ITEM-0026', quantity: 3),
        ],
      ),
      200,
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
    var hall = backend.guildHall(created.guild!.id)!;
    while (true) {
      hall = last?.hall ?? hall;
      final index = save.inventory.indexWhere(
        (stack) => guildHallDonationCap(hall.completedTiers, hall.storehouse, stack.itemId) > 0,
      );
      if (index < 0) break;
      last = backend.contributeHallItem(
        leader.userId,
        save,
        index,
        guildHallDonationCap(hall.completedTiers, hall.storehouse, save.inventory[index].itemId),
      );
      save = last.save!;
    }
    save = backend.payGuildDebt(leader.userId, save, 10000).save!;
    hall = backend.guildHall(created.guild!.id)!;
    expect(hall.bankUnlocked, isTrue);

    final ironIndex = save.inventory.indexWhere((stack) => stack.itemId == 'ITEM-0026');
    final deposited = backend.depositGuildBank(leader.userId, save, ironIndex, 3);
    expect(deposited.ok, isTrue, reason: deposited.reason);
    expect(deposited.hall!.bank.section(guildBankSectionMain).single.quantity, 3);
    save = deposited.save!;

    final moved = backend.moveHallBankToUpForGrabs(leader.userId, save, 'ITEM-0026', 3);
    expect(moved.ok, isTrue, reason: moved.reason);
    expect(moved.hall!.bank.section(guildBankSectionUpForGrabs).single.quantity, 3);

    final taken = backend.takeHallBankUpForGrabs(leader.userId, moved.save!, 'ITEM-0026', 3);
    expect(taken.ok, isTrue, reason: taken.reason);
    final again = backend.takeHallBankUpForGrabs(leader.userId, taken.save!, 'ITEM-0026', 3);
    expect(again.ok, isFalse);

    final logs = backend.guildLog(created.guild!.id);
    expect(
      logs.first.kind,
      anyOf(guildLogKindDonation, guildLogKindTierComplete, guildLogKindJoin),
    );
    expect(logs, isNotEmpty);
    expect(
      logs
          .where((row) => row.kind == guildLogKindTierComplete && row.tierId == guildHallTierBank)
          .single
          .message,
      'The counting room is open for business.',
    );
  });

  test('a member under total level 200 is refused on Up for grabs Take', () {
    final backend = LocalMultiplayerBackend(storage: MemorySaveStorage())..gameDatabase = database;
    final leader = backend.signUp('leader@example.com', 'Leader', 'secret').session!;
    var save = _withTotalLevel(
      createNewSave(database, 1).copyWith(
        gold: guildCreateGoldCost + 10000,
        inventory: const [
          InventoryStack(itemId: 'ITEM-0015', quantity: 1000),
          InventoryStack(itemId: 'ITEM-0095', quantity: 100),
          InventoryStack(itemId: 'ITEM-0017', quantity: 24000),
          InventoryStack(itemId: 'ITEM-0002', quantity: 10000),
          InventoryStack(itemId: 'ITEM-0006', quantity: 6320),
          InventoryStack(itemId: 'ITEM-0026', quantity: 1),
        ],
      ),
      200,
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
    var hall = backend.guildHall(created.guild!.id)!;
    while (true) {
      hall = last?.hall ?? hall;
      final index = save.inventory.indexWhere(
        (stack) => guildHallDonationCap(hall.completedTiers, hall.storehouse, stack.itemId) > 0,
      );
      if (index < 0) break;
      last = backend.contributeHallItem(
        leader.userId,
        save,
        index,
        guildHallDonationCap(hall.completedTiers, hall.storehouse, save.inventory[index].itemId),
      );
      save = last.save!;
    }
    save = backend.payGuildDebt(leader.userId, save, 10000).save!;
    final ironIndex = save.inventory.indexWhere((stack) => stack.itemId == 'ITEM-0026');
    final deposited = backend.depositGuildBank(leader.userId, save, ironIndex, 1);
    expect(deposited.ok, isTrue, reason: deposited.reason);
    final moved = backend.moveHallBankToUpForGrabs(leader.userId, deposited.save!, 'ITEM-0026', 1);
    expect(moved.ok, isTrue, reason: moved.reason);

    final recruit = backend.signUp('recruit@example.com', 'Recruit', 'secret').session!;
    backend.applyToGuild(recruit, created.guild!.id, '');
    final lowLevel = createNewSave(database, 1);
    final refused = backend.takeHallBankUpForGrabs(recruit.userId, lowLevel, 'ITEM-0026', 1);
    expect(refused.ok, isFalse);
    expect(refused.reason, 'Reach total level 200 to take from Up for grabs.');
    expect(refused.reason, guildBankLevelTakeRefusal);
    expect(
      backend
          .guildHall(created.guild!.id)!
          .bank
          .section(guildBankSectionUpForGrabs)
          .single
          .quantity,
      1,
    );
  });

  test('the guild bank refuses a bound or untradeable item, matching TS guild_bank_deposit', () {
    final backend = LocalMultiplayerBackend(storage: MemorySaveStorage())..gameDatabase = database;
    final leader = backend.signUp('leader@example.com', 'Leader', 'secret').session!;
    var save = _withTotalLevel(
      createNewSave(database, 1).copyWith(
        gold: guildCreateGoldCost + 10000,
        inventory: const [
          InventoryStack(itemId: 'ITEM-0015', quantity: 1000),
          InventoryStack(itemId: 'ITEM-0095', quantity: 100),
          InventoryStack(itemId: 'ITEM-0017', quantity: 24000),
          InventoryStack(itemId: 'ITEM-0002', quantity: 10000),
          InventoryStack(itemId: 'ITEM-0006', quantity: 6320),
          InventoryStack(itemId: 'ITEM-0406', quantity: 1),
        ],
      ),
      200,
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
    var hall = backend.guildHall(created.guild!.id)!;
    while (true) {
      hall = last?.hall ?? hall;
      final index = save.inventory.indexWhere(
        (stack) => guildHallDonationCap(hall.completedTiers, hall.storehouse, stack.itemId) > 0,
      );
      if (index < 0) break;
      last = backend.contributeHallItem(
        leader.userId,
        save,
        index,
        guildHallDonationCap(hall.completedTiers, hall.storehouse, save.inventory[index].itemId),
      );
      save = last.save!;
    }
    save = backend.payGuildDebt(leader.userId, save, 10000).save!;
    hall = backend.guildHall(created.guild!.id)!;
    expect(hall.bankUnlocked, isTrue);

    final macheteIndex = save.inventory.indexWhere((stack) => stack.itemId == 'ITEM-0406');
    expect(macheteIndex, greaterThanOrEqualTo(0));
    final refused = backend.depositGuildBank(leader.userId, save, macheteIndex, 1);
    expect(refused.ok, isFalse);
    expect(refused.reason, guildBankUntradeableRefusal);
    expect(backend.guildHall(created.guild!.id)!.bank.items, isEmpty);
  });

  test('a rank without permission is refused on bank withdraw and on move to Up for grabs', () {
    final backend = LocalMultiplayerBackend(storage: MemorySaveStorage());
    final opened = _openCountingRoom(backend, database);
    var save = opened.save;
    final ironIndex = save.inventory.indexWhere((stack) => stack.itemId == 'ITEM-0026');
    expect(ironIndex, greaterThanOrEqualTo(0));
    final deposited = backend.depositGuildBank(opened.leader.userId, save, ironIndex, 3);
    expect(deposited.ok, isTrue, reason: deposited.reason);
    save = deposited.save!;

    final member = backend.signUp('member@example.com', 'Member', 'secret').session!;
    backend.applyToGuild(member, opened.guildId, '');
    backend.setMemberRole(opened.leader.userId, opened.guildId, member.userId, guildRoleMember);
    final memberSave = _withTotalLevel(createNewSave(database, 1), 200);
    backend.writeCloudSave(member.userId, memberSave);

    final withdrawn = backend.withdrawGuildBank(member.userId, memberSave, 'ITEM-0026', 1);
    expect(withdrawn.ok, isFalse);
    expect(withdrawn.reason, 'You cannot withdraw from the guild bank.');

    final moved = backend.moveHallBankToUpForGrabs(member.userId, memberSave, 'ITEM-0026', 3);
    expect(moved.ok, isFalse);
    expect(moved.reason, 'You cannot move items to Up for grabs.');
  });

  test('hall donations unlock guild achievements and banner cosmetics stay server-checked', () {
    final backend = LocalMultiplayerBackend(storage: MemorySaveStorage());
    final leader = backend.signUp('leader-ach@example.com', 'Leader', 'secret').session!;
    var save = createNewSave(database, 1).copyWith(
      gold: guildCreateGoldCost + 1000,
      inventory: const [
        InventoryStack(itemId: 'ITEM-0015', quantity: 1000),
        InventoryStack(itemId: 'ITEM-0095', quantity: 100),
      ],
    );
    backend.writeCloudSave(leader.userId, save);
    final created = backend.createGuild(
      leader,
      const CreateGuildInput(
        name: 'Oak Ach',
        tag: 'ACH',
        description: '',
        emblem: GuildEmblem(color: '#2f6b3a', symbol: 'tree'),
      ),
      save.gold,
    );
    save = save.copyWith(gold: save.gold - created.goldCost!);
    final guildId = created.guild!.id;
    expect(
      backend.guildAchievementProgress(guildId).map((row) => row.id).toList(),
      contains('gach_foundations'),
    );
    expect(
      backend
          .setGuildBanner(
            leader.userId,
            guildId,
            const GuildBanner(background: 'wine', accent: 'ivory', emblem: 'emblem_foundations'),
          )
          .reason,
      guildBannerEmblemRefusal,
    );

    final donated = backend.contributeHallItem(leader.userId, save, 0, 1000);
    expect(donated.ok, isTrue);
    save = donated.save!;
    final rest = backend.contributeHallItem(leader.userId, save, 0, 100);
    expect(rest.ok, isTrue);
    expect(backend.guildHall(guildId)!.completedTiers, contains(guildHallTierBuild));
    expect(
      backend.getGuild(guildId)!.achievements.map((row) => row.achievementId),
      contains('gach_foundations'),
    );
    expect(
      backend
          .setGuildBanner(
            leader.userId,
            guildId,
            const GuildBanner(background: 'wine', accent: 'ivory', emblem: 'emblem_foundations'),
          )
          .ok,
      isTrue,
    );
    expect(backend.getGuild(guildId)!.banner.emblem, 'emblem_foundations');
    expect(
      backend
          .setGuildBanner(
            leader.userId,
            guildId,
            const GuildBanner(background: 'gold', accent: 'ivory'),
          )
          .reason,
      guildBannerColourRefusal,
    );
  });

  test('rising strength stays unlocked after a member leaves', () {
    final backend = LocalMultiplayerBackend(storage: MemorySaveStorage());
    final leader = backend.signUp('leader-rs@example.com', 'Leader', 'secret').session!;
    final leaderSave = _withTotalLevel(
      createNewSave(database, 1).copyWith(gold: guildCreateGoldCost),
      500,
    );
    backend.writeCloudSave(leader.userId, leaderSave);
    final created = backend.createGuild(
      leader,
      const CreateGuildInput(
        name: 'Oak Strength',
        tag: 'STR',
        description: '',
        emblem: GuildEmblem(color: '#2f6b3a', symbol: 'tree'),
      ),
      leaderSave.gold,
    );
    expect(created.ok, isTrue);
    final guildId = created.guild!.id;
    for (var i = 0; i < 24; i++) {
      final member = backend.signUp('rs$i@example.com', 'M$i', 'secret').session!;
      backend.writeCloudSave(member.userId, _withTotalLevel(createNewSave(database, 1), 500));
      expect(backend.applyToGuild(member, guildId, '').ok, isTrue);
    }
    expect(
      backend.getGuild(guildId)!.achievements.map((row) => row.achievementId),
      contains('gach_rising_strength'),
    );
    final leaver = backend.guildMembers(guildId).firstWhere((row) => row.userId != leader.userId);
    expect(backend.leaveGuild(leaver.userId).ok, isTrue);
    expect(backend.guildMembers(guildId), hasLength(24));
    expect(
      backend.getGuild(guildId)!.achievements.map((row) => row.achievementId),
      contains('gach_rising_strength'),
    );
    backend.writeCloudSave(leader.userId, leaderSave);
    expect(
      backend.getGuild(guildId)!.achievements.map((row) => row.achievementId),
      contains('gach_rising_strength'),
    );
    expect(
      backend
          .guildAchievementProgress(guildId)
          .singleWhere((row) => row.id == 'gach_rising_strength')
          .unlocked,
      isTrue,
    );
  });

  test(
    'a member with no save counts as 0; forging roster total_level does not unlock Rising strength',
    () {
      final storage = MemorySaveStorage();
      final backend = LocalMultiplayerBackend(storage: storage);
      final leader = backend.signUp('leader-forge@example.com', 'Leader', 'secret').session!;
      final leaderSave = createNewSave(database, 1).copyWith(gold: guildCreateGoldCost);
      backend.writeCloudSave(leader.userId, leaderSave);
      final created = backend.createGuild(
        leader,
        const CreateGuildInput(
          name: 'Oak Forge',
          tag: 'FRG',
          description: '',
          emblem: GuildEmblem(color: '#2f6b3a', symbol: 'tree'),
        ),
        leaderSave.gold,
      );
      expect(created.ok, isTrue);
      final guildId = created.guild!.id;
      for (var i = 0; i < 24; i++) {
        final member = backend.signUp('forge$i@example.com', 'F$i', 'secret').session!;
        expect(backend.applyToGuild(member, guildId, '').ok, isTrue);
      }
      expect(guildMemberSaveTotalLevel(null), 0);
      expect(
        backend.getGuild(guildId)!.achievements.map((row) => row.achievementId),
        isNot(contains('gach_rising_strength')),
      );
      expect(
        backend
            .guildAchievementProgress(guildId)
            .singleWhere((row) => row.id == 'gach_rising_strength')
            .current,
        0,
      );

      final db = LocalDb.fromJson(jsonDecode(storage.getItem(multiplayerLocalDbKey)!));
      db.members = [for (final row in db.members) row.copyWith(totalLevel: 500)];
      storage.setItem(multiplayerLocalDbKey, jsonEncode(db.toJson()));
      expect(
        backend.getGuild(guildId)!.achievements.map((row) => row.achievementId),
        isNot(contains('gach_rising_strength')),
      );
      expect(
        backend
            .guildAchievementProgress(guildId)
            .singleWhere((row) => row.id == 'gach_rising_strength')
            .unlocked,
        isFalse,
      );
    },
  );

  test('a forged hall payload that claims the gold cap is ignored unless the save paid', () {
    final backend = LocalMultiplayerBackend(storage: MemorySaveStorage());
    final leader = backend.signUp('leader@example.com', 'Leader', 'secret').session!;
    final save = createNewSave(database, 1).copyWith(gold: guildCreateGoldCost + 80);
    backend.writeCloudSave(leader.userId, save);
    backend.createGuild(
      leader,
      const CreateGuildInput(
        name: 'Oak',
        tag: 'OAK',
        description: '',
        emblem: GuildEmblem(color: '#2f6b3a', symbol: 'tree'),
      ),
      save.gold,
    );
    final paid = backend.payGuildDebt(leader.userId, save.copyWith(gold: 80), 40);
    expect(paid.ok, isTrue);
    expect(paid.goldChipped, 40);
    expect(paid.save!.gold, 40);
    expect(goldTakenFromPlayerSaves(80, paid.save!.gold), paid.goldChipped);

    final forged = commitGuildHallFromPlayerSaves(
      previousGold: 80,
      nextGold: 80,
      previousInventory: const <InventoryStack>[],
      nextInventory: const <InventoryStack>[],
      hallGoldContributed: 0,
      userId: leader.userId,
      proposal: const GuildHallCommitProposal(
        goldContributed: guildHallGoldCap,
        completedTiers: <String>[guildHallTierBuild, guildHallTierBank],
      ),
    );
    expect(forged.ok, isTrue);
    expect(forged.goldTaken, 0);
    expect(forged.goldContributed, 0);
    expect(forged.completedTiers, isEmpty);
  });
}

PlayerSave _withTotalLevel(PlayerSave save, num target) {
  final bump = target - totalLevel(save);
  if (bump <= 0) return save;
  final first = save.skills.first;
  return save.copyWith(
    skills: <SkillProgress>[
      first.copyWith(level: first.level + bump),
      ...save.skills.skip(1),
    ],
  );
}

({LocalMultiplayerBackend backend, MultiplayerSession leader, PlayerSave save, String guildId})
_openCountingRoom(LocalMultiplayerBackend backend, GameDatabase database) {
  final leader = backend.signUp('leader-bank@example.com', 'Leader', 'secret').session!;
  var save = _withTotalLevel(
    createNewSave(database, 1).copyWith(
      gold: guildCreateGoldCost + 10000,
      inventory: const [
        InventoryStack(itemId: 'ITEM-0015', quantity: 1000),
        InventoryStack(itemId: 'ITEM-0095', quantity: 100),
        InventoryStack(itemId: 'ITEM-0017', quantity: 24000),
        InventoryStack(itemId: 'ITEM-0002', quantity: 10000),
        InventoryStack(itemId: 'ITEM-0006', quantity: 6320),
        InventoryStack(itemId: 'ITEM-0026', quantity: 3),
      ],
    ),
    200,
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
  var hall = backend.guildHall(created.guild!.id)!;
  while (true) {
    hall = last?.hall ?? hall;
    final index = save.inventory.indexWhere(
      (stack) => guildHallDonationCap(hall.completedTiers, hall.storehouse, stack.itemId) > 0,
    );
    if (index < 0) break;
    last = backend.contributeHallItem(
      leader.userId,
      save,
      index,
      guildHallDonationCap(hall.completedTiers, hall.storehouse, save.inventory[index].itemId),
    );
    save = last.save!;
  }
  save = backend.payGuildDebt(leader.userId, save, 10000).save!;
  expect(backend.guildHall(created.guild!.id)!.bankUnlocked, isTrue);
  return (backend: backend, leader: leader, save: save, guildId: created.guild!.id);
}
