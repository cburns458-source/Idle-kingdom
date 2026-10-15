import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/multiplayer_controller.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/chat_sheet.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_rules/ik_rules.dart';
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

  Future<void> openChat(
    WidgetTester tester,
    MultiplayerController net,
    PlayerSave save, {
    TestClock? clock,
  }) async {
    await net.refresh(save);
    await net.selectChatTab(ChatTab.global, save.currentLocationId);
    final controller = buildController(database, seed: save, clock: clock);
    addTearDown(controller.dispose);
    await pumpPanel(
      tester,
      ChatSheet(
        controller: controller,
        multiplayer: net,
        locationId: save.currentLocationId,
        citadelHub: false,
        onClose: () {},
      ),
    );
  }

  test('show titles and timestamps start on and persist across reload', () {
    final storage = MemorySaveStorage();
    final first = wiredNet(storage: storage);
    addTearDown(first.net.dispose);
    expect(storage.getItem(chatShowTitlesStorageKey), isNull);
    expect(storage.getItem(chatShowTimestampsStorageKey), isNull);
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

  testWidgets('chat shows the title before the name, and just the name when none', (tester) async {
    final wired = wiredNet();
    addTearDown(wired.net.dispose);
    final save = startedCharacter(database);
    seedChat(
      wired.net.storage,
      const ChatMessage(
        id: 'msg_title',
        channelKey: 'global',
        userId: 'usr_rival',
        username: 'Rowan',
        body: 'The watch is set.',
        createdAt: '2026-01-01T12:00:00.000Z',
        title: 'The Undying',
      ),
    );
    seedChat(
      wired.net.storage,
      const ChatMessage(
        id: 'msg_plain',
        channelKey: 'global',
        userId: 'usr_nara',
        username: 'Nara',
        body: 'Noon watch.',
        createdAt: '2026-01-01T12:00:01.000Z',
      ),
    );
    await openChat(tester, wired.net, save, clock: wired.clock);

    expect(find.textContaining('The Undying Rowan:'), findsOne);
    expect(find.textContaining('Nara:'), findsOne);
    expect(find.textContaining('The Undying Nara:'), findsNothing);
    expect(wired.net.messages.where((row) => row.id == 'msg_title').single.title, 'The Undying');
    expect(wired.net.messages.where((row) => row.id == 'msg_plain').single.title, isNull);
  });

  testWidgets(
    'turning Show titles off hides titles only in this view; messages still carry title',
    (tester) async {
      final storage = MemorySaveStorage();
      final wired = wiredNet(storage: storage);
      addTearDown(wired.net.dispose);
      final save = startedCharacter(database);
      seedChat(
        wired.net.storage,
        const ChatMessage(
          id: 'msg_title',
          channelKey: 'global',
          userId: 'usr_rival',
          username: 'Rowan',
          body: 'The watch is set.',
          createdAt: '2026-01-01T12:00:00.000Z',
          title: 'The Undying',
        ),
      );
      await openChat(tester, wired.net, save, clock: wired.clock);
      expect(find.textContaining('The Undying Rowan:'), findsOne);

      wired.net.setShowChatTitles(false);
      await tester.pump();
      expect(find.textContaining('The Undying Rowan:'), findsNothing);
      expect(find.textContaining('Rowan:'), findsOne);
      expect(wired.net.messages.where((row) => row.id == 'msg_title').single.title, 'The Undying');
      expect(wired.net.showChatTitles, isFalse);

      final otherView = wiredNet(storage: MemorySaveStorage());
      addTearDown(otherView.net.dispose);
      expect(otherView.net.showChatTitles, isTrue);
    },
  );

  testWidgets('timestamps show only when that toggle is on, and the choice survives reload', (
    tester,
  ) async {
    final storage = MemorySaveStorage();
    final wired = wiredNet(storage: storage);
    addTearDown(wired.net.dispose);
    final save = startedCharacter(database);
    const createdAt = '2026-01-01T12:00:00.000Z';
    seedChat(
      wired.net.storage,
      const ChatMessage(
        id: 'msg_stamp',
        channelKey: 'global',
        userId: 'usr_rival',
        username: 'Mira',
        body: 'Noon watch.',
        createdAt: createdAt,
      ),
    );
    await openChat(tester, wired.net, save, clock: wired.clock);

    final stamp = formatChatTimestamp(createdAt);
    expect(stamp, isNotEmpty);
    expect(find.text(stamp), findsOne);

    wired.net.setShowChatTimestamps(false);
    await tester.pump();
    expect(find.text(stamp), findsNothing);
    expect(find.textContaining('Noon watch.', findRichText: true), findsOne);

    final reloaded = wiredNet(storage: storage, bootstrap: false);
    addTearDown(reloaded.net.dispose);
    expect(reloaded.net.showChatTimestamps, isFalse);
    await openChat(tester, reloaded.net, save, clock: reloaded.clock);
    expect(find.text(stamp), findsNothing);
    expect(find.textContaining('Noon watch.', findRichText: true), findsOne);
  });

  testWidgets('Settings Chat keeps Global, Local, Guild, Guest and Private in one panel', (
    tester,
  ) async {
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

    final channelPanel = find.ancestor(of: find.text('Global'), matching: find.byType(GamePanel));
    expect(find.descendant(of: channelPanel, matching: find.text('Local')), findsOne);
    expect(find.descendant(of: channelPanel, matching: find.text('Guild')), findsOne);
    expect(find.descendant(of: channelPanel, matching: find.text('Guest')), findsOne);
    expect(find.descendant(of: channelPanel, matching: find.text('Private')), findsOne);
    expect(find.descendant(of: channelPanel, matching: find.byType(GameSwitch)), findsNWidgets(5));

    await tapVisible(tester, rowSwitch('Show titles'));
    expect(net.showChatTitles, isFalse);
    await tapVisible(tester, rowSwitch('Timestamps'));
    expect(net.showChatTimestamps, isFalse);
  });

  test('each channel toggle still filters unread for that tab only', () async {
    final wired = wiredNet();
    addTearDown(wired.net.dispose);
    final save = startedCharacter(database);

    final created = wired.service.backend.createGuild(
      wired.service.session!,
      const CreateGuildInput(
        name: 'Iron League',
        tag: 'IRN',
        emblem: GuildEmblem(color: '#3d5a80', symbol: 'shield'),
      ),
      guildCreateGoldCost,
    );
    expect(created.ok, isTrue, reason: created.reason);
    final guested = wired.service.backend.joinAsGuest(wired.service.session!, demoGuildId, '');
    expect(guested.ok, isTrue, reason: guested.reason);
    await wired.net.refresh(save);
    expect(wired.net.guildId, created.guild!.id);
    expect(wired.net.guestGuildId, demoGuildId);
    expect(wired.net.unreadTotal, 0);

    wired.clock.advance(1000);
    final mate = wired.service.backend.signUp('mate@example.com', 'Mate', 'secret');
    expect(mate.ok, isTrue, reason: mate.reason);
    expect(wired.service.backend.applyToGuild(mate.session!, created.guild!.id, '').ok, isTrue);
    final watchMate = wired.service.backend.signUp('watchmate@example.com', 'WatchMate', 'secret');
    expect(watchMate.ok, isTrue, reason: watchMate.reason);
    expect(wired.service.backend.applyToGuild(watchMate.session!, demoGuildId, '').ok, isTrue);

    expect(
      wired.service.backend.sendChat(mate.session!, const ChatChannel.global(), 'Global hail').ok,
      isTrue,
    );
    expect(
      wired.service.backend
          .sendChat(mate.session!, ChatChannel.local(save.currentLocationId), 'Local hail')
          .ok,
      isTrue,
    );
    expect(
      wired.service.backend
          .sendChat(mate.session!, ChatChannel.guild(created.guild!.id), 'Guild hail')
          .ok,
      isTrue,
    );
    expect(
      wired.service.backend
          .sendChat(watchMate.session!, ChatChannel.guild(demoGuildId), 'Guest hail')
          .ok,
      isTrue,
    );
    expect(
      wired.service.backend
          .sendChat(
            mate.session!,
            ChatChannel.dm(dmPairKey(mate.session!.userId, wired.net.session!.userId)),
            'Private hail',
          )
          .ok,
      isTrue,
    );

    await wired.net.refresh(save);
    expect(wired.net.unreadFor(ChatTab.global), 1);
    expect(wired.net.unreadFor(ChatTab.local), 1);
    expect(wired.net.unreadFor(ChatTab.guild), 1);
    expect(wired.net.unreadFor(ChatTab.guest), 1);
    expect(wired.net.unreadFor(ChatTab.dm), 1);

    const labels = <(ChatTab, String)>[
      (ChatTab.global, 'Global'),
      (ChatTab.local, 'Local'),
      (ChatTab.guild, 'Guild'),
      (ChatTab.guest, 'Guest'),
      (ChatTab.dm, 'Private'),
    ];
    for (final entry in labels) {
      final tab = entry.$1;
      wired.net.setChatNotifyEnabled(tab, false);
      expect(wired.net.unreadFor(tab), 0, reason: '${entry.$2} should stop notifying');
      for (final other in labels) {
        if (other.$1 == tab) continue;
        expect(wired.net.unreadFor(other.$1), 1, reason: '${other.$2} should keep notifying');
      }
      wired.net.setChatNotifyEnabled(tab, true);
      await wired.net.refresh(save);
      expect(wired.net.unreadFor(tab), 1, reason: '${entry.$2} should notify again');
    }
  });
}
