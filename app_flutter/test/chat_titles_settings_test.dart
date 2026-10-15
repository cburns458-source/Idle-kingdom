import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/multiplayer_controller.dart';
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

  ({MultiplayerController net, LocalMultiplayerService service, TestClock clock}) wiredNet({
    SaveStorage? storage,
    bool bootstrap = true,
  }) {
    final clock = TestClock();
    var ids = 0;
    final store = storage ?? MemorySaveStorage();
    final service = LocalMultiplayerService(
      storage: store,
      ports: LocalBackendPorts(
        nowMs: clock.read,
        newId: (prefix) => '${prefix}_${(ids += 1).toString().padLeft(4, '0')}',
      ),
    );
    if (bootstrap) {
      service.ensureDemoWorld(database.launch);
      registerTestAccount(service);
    }
    restoreTestSession(service, store);
    final net = MultiplayerController(
      database: database,
      service: service,
      storage: store,
      clock: clock.read,
    );
    return (net: net, service: service, clock: clock);
  }

  void seedChat(SaveStorage storage, ChatMessage message) {
    final raw = storage.getItem(multiplayerLocalDbKey);
    final db = LocalDb.fromJson(raw == null ? null : jsonDecode(raw) as Object?);
    db.messages.add(message);
    storage.setItem(multiplayerLocalDbKey, jsonEncode(db.toJson()));
  }

  Finder rowSwitch(String title) {
    return find.descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(Row)).first,
      matching: find.byType(GameSwitch),
    );
  }

  test('show titles and timestamps start on and stay saved', () {
    final storage = MemorySaveStorage();
    final first = wiredNet(storage: storage);
    addTearDown(first.net.dispose);
    expect(first.net.showChatTitles, isTrue);
    expect(first.net.showChatTimestamps, isTrue);

    first.net.setShowChatTitles(false);
    first.net.setShowChatTimestamps(false);
    expect(storage.getItem(chatShowTitlesStorageKey), '0');
    expect(storage.getItem(chatShowTimestampsStorageKey), '0');

    final reloaded = wiredNet(storage: storage, bootstrap: false);
    addTearDown(reloaded.net.dispose);
    expect(reloaded.net.showChatTitles, isFalse);
    expect(reloaded.net.showChatTimestamps, isFalse);
  });

  testWidgets('chat puts the sender title before their name', (tester) async {
    final wired = wiredNet();
    addTearDown(wired.net.dispose);
    final save = startedCharacter(database);
    seedChat(
      wired.net.storage,
      ChatMessage(
        id: 'msg_title',
        channelKey: 'global',
        userId: 'usr_rival',
        username: 'Rowan',
        body: 'The watch is set.',
        createdAt: '2026-01-01T12:00:00.000Z',
        title: 'The Undying',
      ),
    );
    await wired.net.refresh(save);
    await wired.net.selectChatTab(ChatTab.global, save.currentLocationId);

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
    );

    expect(find.textContaining('The Undying Rowan:'), findsOne);
    expect(find.textContaining('The watch is set.', findRichText: true), findsOne);

    wired.net.setShowChatTitles(false);
    await tester.pump();
    expect(find.textContaining('The Undying Rowan:'), findsNothing);
    expect(find.textContaining('Rowan:'), findsOne);
  });

  testWidgets('chat timestamps hide when the toggle is off', (tester) async {
    final wired = wiredNet();
    addTearDown(wired.net.dispose);
    final save = startedCharacter(database);
    seedChat(
      wired.net.storage,
      ChatMessage(
        id: 'msg_stamp',
        channelKey: 'global',
        userId: 'usr_rival',
        username: 'Mira',
        body: 'Noon watch.',
        createdAt: '2026-01-01T12:00:00.000Z',
      ),
    );
    await wired.net.refresh(save);
    await wired.net.selectChatTab(ChatTab.global, save.currentLocationId);

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
    );

    final stamp = formatChatTimestamp('2026-01-01T12:00:00.000Z');
    expect(stamp, isNotEmpty);
    expect(find.text(stamp), findsOne);

    wired.net.setShowChatTimestamps(false);
    await tester.pump();
    expect(find.text(stamp), findsNothing);
    expect(find.textContaining('Noon watch.', findRichText: true), findsOne);
  });

  testWidgets('Settings Chat groups channel toggles in one panel', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    final net = buildMultiplayer(database);
    addTearDown(controller.dispose);
    addTearDown(net.dispose);
    await pumpShell(tester, controller, multiplayer: net, size: const Size(900, 2400));

    await openChinScreen(tester, 'Settings');
    await tester.tap(find.text('Chat'));
    await tester.pump();

    expect(find.text('Show titles'), findsOne);
    expect(find.text('Timestamps'), findsOne);
    expect(find.text('Chat notifications'), findsNothing);
    expect(
      find.text('Show a bubble on the chat icon and on the channel tab when a new line arrives.'),
      findsNothing,
    );

    final channelPanel = find.ancestor(of: find.text('Global'), matching: find.byType(GamePanel));
    expect(find.descendant(of: channelPanel, matching: find.text('Local')), findsOne);
    expect(find.descendant(of: channelPanel, matching: find.text('Guild')), findsOne);
    expect(find.descendant(of: channelPanel, matching: find.text('Guest')), findsOne);
    expect(find.descendant(of: channelPanel, matching: find.text('Private')), findsOne);
    expect(find.descendant(of: channelPanel, matching: find.byType(GameSwitch)), findsNWidgets(5));

    expect(net.chatNotifyEnabled(ChatTab.local), isTrue);
    await tapVisible(tester, rowSwitch('Local'));
    expect(net.chatNotifyEnabled(ChatTab.local), isFalse);
    expect(net.chatNotifyEnabled(ChatTab.global), isTrue);

    await tapVisible(tester, rowSwitch('Show titles'));
    expect(net.showChatTitles, isFalse);
    await tapVisible(tester, rowSwitch('Timestamps'));
    expect(net.showChatTimestamps, isFalse);
  });
}
