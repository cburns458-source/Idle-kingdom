import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/chat_sheet.dart';
import 'package:idle_kingdoms/src/ui/social_view.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  testWidgets('chat uses the published name color for everyone including self', (tester) async {
    final clock = TestClock();
    final net = buildMultiplayer(database, clock: clock);
    addTearDown(net.dispose);
    final save = startedCharacter(database).copyWith(characterName: 'Vari');
    await net.signUp('vari@example.com', 'Vari', 'secret', save, adopt: (save, {nowMs}) {});
    net.setNameColorDraft('#FA3');
    await net.publishRanking(save, ignoreDebounce: true);
    await net.selectChatTab(ChatTab.global, save.currentLocationId);
    await net.sendChat('Hello from Vari', save.currentLocationId);

    final game = buildController(database, seed: save, clock: clock);
    addTearDown(game.dispose);
    await pumpPanel(
      tester,
      ChatSheet(
        controller: game,
        multiplayer: net,
        locationId: save.currentLocationId,
        citadelHub: false,
        onClose: () {},
      ),
    );
    await tester.pumpAndSettle();

    final name = tester.widget<Text>(find.text('Vari: '));
    expect(name.style?.color, const Color(0xFFFFAA33));
  });

  testWidgets('leaderboard names stay on the theme color', (tester) async {
    final clock = TestClock();
    final net = buildMultiplayer(database, clock: clock);
    addTearDown(net.dispose);
    final save = startedCharacter(database).copyWith(characterName: 'Vari');
    await net.signUp('vari@example.com', 'Vari', 'secret', save, adopt: (save, {nowMs}) {});
    net.setNameColorDraft('#00FF00');
    await net.publishRanking(save, ignoreDebounce: true);

    final game = buildController(database, seed: save, clock: clock);
    addTearDown(game.dispose);
    await pumpPanel(
      tester,
      ListenableBuilder(
        listenable: net,
        builder: (context, _) =>
            SocialView(controller: game, multiplayer: net, section: SocialTab.leaderboards),
      ),
    );
    await tester.pump();
    await tester.pump();

    final name = tester.widget<Text>(find.text('Vari').first);
    expect(name.style?.color, isNot(const Color(0xFF00FF00)));
  });

  test('colorFromHexRgb reads a canonical code', () {
    expect(colorFromHexRgb('#FFAA33'), const Color(0xFFFFAA33));
    expect(colorFromHexRgb('#fa3'), isNull);
    expect(colorFromHexRgb(null), isNull);
  });
}
