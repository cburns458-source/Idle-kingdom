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

  test('chat item link is distinct from body text and gold names', () {
    expect(Palette.chatItemLink, isNot(Palette.parchmentText));
    expect(Palette.chatItemLink, isNot(Palette.gold));
    expect(Palette.chatItemLink, isNot(Palette.muted));
  });

  test('chat item link keeps contrast on wood and stone boards', () {
    expect(contrastRatio(Palette.chatItemLink, UiChrome.wood.board), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.chatItemLink, UiChrome.stone.board), greaterThanOrEqualTo(4.5));
  });

  testWidgets('linked items render sky blue on both chrome packs', (tester) async {
    Future<void> pumpWith(UiChromePack pack) async {
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
      final save = startedCharacter(database);
      final sent = service.backend.sendChat(
        service.session!,
        ChatChannel.local(save.currentLocationId),
        '@[ITEM-0003]',
      );
      expect(sent.ok, isTrue, reason: sent.reason);
      final net = MultiplayerController(
        database: database,
        service: service,
        storage: storage,
        clock: clock.read,
      );
      addTearDown(net.dispose);
      await net.refresh(save);
      await net.selectChatTab(ChatTab.local, save.currentLocationId);
      final controller = buildController(database, seed: save);
      addTearDown(controller.dispose);

      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: UiChromeScope(
            chrome: UiChrome.forPack(pack),
            child: Scaffold(
              body: ChatSheet(
                controller: controller,
                multiplayer: net,
                locationId: save.currentLocationId,
                citadelHub: false,
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpWith(UiChromePack.wood);
    final woodLink = tester.widget<Text>(find.text('Copper Ore'));
    expect(woodLink.style?.color, Palette.chatItemLink);

    await pumpWith(UiChromePack.stone);
    final stoneLink = tester.widget<Text>(find.text('Copper Ore'));
    expect(stoneLink.style?.color, Palette.chatItemLink);
  });
}
