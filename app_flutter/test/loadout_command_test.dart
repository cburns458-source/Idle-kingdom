import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/hosted_save_adopt.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_net/testing.dart';
import 'package:ik_rules/ik_rules.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('rapid equips leave as one set_loadout', (tester) async {
    final project = FakeTransport(database: database.launch);
    final net = buildRemoteMultiplayer(database, transport: project);
    addTearDown(net.dispose);
    var save = startedCharacter(database);
    await net.signUp(
      testAccount.email,
      testAccount.username,
      testAccount.password,
      save,
      adopt: (adopted, {nowMs}) => save = adopted,
    );
    expect(net.isSignedIn, isTrue, reason: net.notice);
    final seeded = await seedHostedSave(net.service as RemoteMultiplayerService, project, save);
    expect(seeded.ok, isTrue, reason: seeded.reason);
    save = seeded.save!;
    net.currentSave = () => save;
    net.onHostedSave = (incoming, {command}) {
      save = mergeHostedStartSave(save, incoming, command: command);
    };

    final worn = Map<String, EquippedStack?>.from(save.equipment.slots);
    worn[weaponToolSlotId] = const EquippedStack(itemId: 'ITEM-0102', quantity: 1);
    save = save.copyWith(equipment: EquipmentLoadout(slots: worn));

    final before = project.calls.length;
    await net.submitGameCommand('equip_index', <String, Object?>{'inventoryIndex': 0});
    await net.submitGameCommand('equip_index', <String, Object?>{'inventoryIndex': 1});
    await net.submitGameCommand('unequip_slot', <String, Object?>{'slotId': weaponToolSlotId});
    await tester.pump(const Duration(milliseconds: 500));
    expect(project.calls.sublist(before), isNot(contains('game:set_loadout')));

    await tester.pump(const Duration(milliseconds: 200));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }

    final sent = project.calls.sublist(before);
    expect(sent.where((call) => call == 'game:equip_index'), isEmpty);
    expect(sent.where((call) => call == 'game:unequip_slot'), isEmpty);
    expect(sent.where((call) => call == 'game:set_loadout'), hasLength(1));
  });

  testWidgets('a following command flushes the worn gear first', (tester) async {
    final project = FakeTransport(database: database.launch);
    final net = buildRemoteMultiplayer(database, transport: project);
    addTearDown(net.dispose);
    var save = startedCharacter(database);
    await net.signUp(
      testAccount.email,
      testAccount.username,
      testAccount.password,
      save,
      adopt: (adopted, {nowMs}) => save = adopted,
    );
    final seeded = await seedHostedSave(net.service as RemoteMultiplayerService, project, save);
    expect(seeded.ok, isTrue, reason: seeded.reason);
    save = seeded.save!;
    net.currentSave = () => save;
    net.onHostedSave = (incoming, {command}) {
      save = mergeHostedStartSave(save, incoming, command: command);
    };
    net.onQuietMessage = (_) {};

    final before = project.calls.length;
    await net.submitGameCommand('equip_index', <String, Object?>{'inventoryIndex': 0});
    await net.submitGameCommand('stop_activity');
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }

    final sent = project.calls.sublist(before);
    final loadoutAt = sent.indexOf('game:set_loadout');
    final stopAt = sent.indexOf('game:stop_activity');
    expect(loadoutAt, greaterThanOrEqualTo(0));
    expect(stopAt, greaterThan(loadoutAt));
    expect(sent.where((call) => call == 'game:equip_index'), isEmpty);
  });
}
