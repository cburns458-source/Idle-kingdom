import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/multiplayer_controller.dart';
import 'package:idle_kingdoms/src/session/tester_access.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/chat_sheet.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_runtime/ik_runtime.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  ({MultiplayerController net, LocalMultiplayerService service, TestClock clock}) wiredNet() {
    final clock = TestClock();
    var ids = 0;
    final storage = MemorySaveStorage();
    final service = LocalMultiplayerService(
      storage: storage,
      ports: LocalBackendPorts(
        nowMs: clock.read,
        newId: (prefix) => '${prefix}_${(ids += 1).toString().padLeft(4, '0')}',
      ),
    );
    service.ensureDemoWorld(database.launch);
    registerTestAccount(service);
    restoreTestSession(service, storage);
    final net = MultiplayerController(
      database: database,
      service: service,
      storage: storage,
      clock: clock.read,
    );
    net.unlockTesterAccess(testerPasskey);
    return (net: net, service: service, clock: clock);
  }

  Future<void> otherPlayerChats(
    LocalMultiplayerService service,
    TestClock clock,
    ChatChannel channel,
    String body,
  ) async {
    final rival = service.backend.signUp('rival@example.com', 'Rival', 'secret');
    expect(rival.ok, isTrue, reason: rival.reason);
    clock.advance(1000);
    final sent = service.backend.sendChat(rival.session!, channel, body);
    expect(sent.ok, isTrue, reason: sent.reason);
  }

  test('unread bubbles count other players lines after the cursor', () async {
    final wired = wiredNet();
    addTearDown(wired.net.dispose);
    final save = startedCharacter(database);
    await wired.net.refresh(save);
    expect(wired.net.unreadTotal, 0);

    await otherPlayerChats(
      wired.service,
      wired.clock,
      ChatChannel.local(save.currentLocationId),
      'Anyone at the meadow?',
    );
    await wired.net.refresh(save);
    expect(wired.net.unreadFor(ChatTab.local), 1);
    expect(wired.net.unreadFor(ChatTab.global), 0);
    expect(wired.net.unreadTotal, 1);

    wired.net.setChatNotifyEnabled(ChatTab.local, false);
    expect(wired.net.unreadFor(ChatTab.local), 0);
    expect(wired.net.unreadTotal, 0);

    wired.net.setChatNotifyEnabled(ChatTab.local, true);
    await wired.net.refresh(save);
    expect(wired.net.unreadFor(ChatTab.local), 1);

    await wired.net.selectChatTab(ChatTab.local, save.currentLocationId);
    expect(wired.net.unreadFor(ChatTab.local), 0);
    expect(wired.net.unreadTotal, 0);
  });

  test('a new empty local room does not inherit a bubble', () async {
    final wired = wiredNet();
    addTearDown(wired.net.dispose);
    final save = startedCharacter(database);
    await wired.net.refresh(save);
    expect(wired.net.unreadFor(ChatTab.local), 0);

    await otherPlayerChats(
      wired.service,
      wired.clock,
      ChatChannel.local(save.currentLocationId),
      'Anyone at the meadow?',
    );
    await wired.net.refresh(save);
    expect(wired.net.unreadFor(ChatTab.local), 1);

    const elsewhere = 'LOC-0009';
    wired.net.syncChatSurface(open: false, locationId: elsewhere, citadelHub: false);
    expect(wired.net.unreadFor(ChatTab.local), 0);

    await wired.net.refresh(save.copyWith(currentLocationId: elsewhere));
    expect(wired.net.unreadFor(ChatTab.local), 0);
    expect(wired.net.unreadTotal, 0);
  });

  testWidgets('a new local line badges the chat icon and the Local tab', (tester) async {
    final wired = wiredNet();
    addTearDown(wired.net.dispose);
    final save = startedCharacter(database);
    await wired.net.refresh(save);
    await otherPlayerChats(
      wired.service,
      wired.clock,
      ChatChannel.local(save.currentLocationId),
      'Anyone at the meadow?',
    );
    await wired.net.refresh(save);

    final controller = buildController(database, seed: save, clock: wired.clock);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, multiplayer: wired.net);
    expect(find.byTooltip('Open chat, 1 unread'), findsOne);

    await pumpPanel(
      tester,
      ChatSheet(
        controller: controller,
        multiplayer: wired.net,
        locationId: save.currentLocationId,
        citadelHub: false,
        onClose: () {},
      ),
    );
    final localTab = find.widgetWithText(GameButton, 'Local');
    expect(localTab, findsOne);
    final tabStack = find.ancestor(of: localTab, matching: find.byType(Stack)).first;
    expect(find.descendant(of: tabStack, matching: find.text('1')), findsOne);
  });

  testWidgets('opening chat shows the latest line', (tester) async {
    final wired = wiredNet();
    addTearDown(wired.net.dispose);
    final save = startedCharacter(database);
    for (var i = 0; i < 16; i++) {
      final speaker = wired.service.backend.signUp('rival$i@example.com', 'Rival$i', 'secret');
      expect(speaker.ok, isTrue, reason: speaker.reason);
      final sent = wired.service.backend.sendChat(
        speaker.session!,
        const ChatChannel.global(),
        'Line $i of the watch',
      );
      expect(sent.ok, isTrue, reason: sent.reason);
    }
    await wired.net.refresh(save);
    await wired.net.selectChatTab(ChatTab.global, save.currentLocationId);
    expect(wired.net.messages.length, greaterThanOrEqualTo(16));

    final controller = buildController(database, seed: save, clock: wired.clock);
    addTearDown(controller.dispose);
    await pumpPanel(
      tester,
      ChatSheet(
        controller: controller,
        multiplayer: wired.net,
        locationId: save.currentLocationId,
        citadelHub: false,
        onClose: () {},
      ),
      size: const Size(420, 360),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Line 15 of the watch', findRichText: true), findsOne);
    expect(
      find.textContaining('Line 0 of the watch', findRichText: true).hitTestable(),
      findsNothing,
    );
  });
}
