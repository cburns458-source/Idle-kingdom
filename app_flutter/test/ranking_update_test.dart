import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/ui/social_view.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_net/testing.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  test('sign-up posts the daily ranking and then waits an hour', () async {
    final clock = TestClock();
    final net = buildMultiplayer(database, clock: clock);
    addTearDown(net.dispose);
    final save = startedCharacter(database);

    await net.signUp('hero@example.com', 'Hero', 'secret', save, adopt: (_) {});

    expect(net.board, isNotEmpty);
    expect(net.canPressUpdateRanking, isFalse);
    expect(net.lastRankingSubmitAt, testStartMs);

    await net.updateRanking(save);
    expect(net.notice, 'You can update your ranking again in 1 hour.');

    clock.advance(rankingUpdateCooldownMs);
    await net.updateRanking(save);
    expect(net.notice, rankingUpdatedNotice);
    expect(net.canPressUpdateRanking, isFalse);
  });

  test('opening the boards posts once when the UTC day is new', () async {
    final clock = TestClock();
    final net = buildMultiplayer(database, clock: clock);
    addTearDown(net.dispose);
    final save = startedCharacter(database);
    await net.signUp('hero@example.com', 'Hero', 'secret', save, adopt: (_) {});
    net.storage.removeItem(rankingUpdateStorageKey(net.session!.userId));
    expect(net.lastRankingSubmitAt, isNull);

    await net.openLeaderboards(save);
    expect(net.lastRankingSubmitAt, testStartMs);
    expect(net.board, isNotEmpty);
  });

  test('a new UTC day posts again without a button press', () async {
    final clock = TestClock();
    final net = buildMultiplayer(database, clock: clock);
    addTearDown(net.dispose);
    final save = startedCharacter(database);
    await net.signUp('hero@example.com', 'Hero', 'secret', save, adopt: (_) {});

    clock.advance(24 * 60 * 60 * 1000);
    await net.maybeAutoSubmitRanking(save);
    expect(net.lastRankingSubmitAt, testStartMs + 24 * 60 * 60 * 1000);
  });

  testWidgets('the leaderboard tab shows the update control', (tester) async {
    final clock = TestClock();
    final net = buildMultiplayer(database, clock: clock);
    addTearDown(net.dispose);
    final save = startedCharacter(database);
    await net.signUp('hero@example.com', 'Hero', 'secret', save, adopt: (_) {});

    final game = buildController(database, seed: save, clock: clock);
    addTearDown(game.dispose);
    await pumpPanel(
      tester,
      ListenableBuilder(
        listenable: net,
        builder: (context, _) => SocialView(
          controller: game,
          multiplayer: net,
          section: SocialTab.leaderboards,
        ),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('Update my ranking'), findsOne);
    expect(find.text('You can update your ranking again in 1 hour.'), findsOne);
  });

  testWidgets('a board names the signed-in character without a sync step', (tester) async {
    final clock = TestClock();
    final transport = FakeTransport();
    final net = buildRemoteMultiplayer(database, transport: transport, clock: clock);
    addTearDown(net.dispose);
    final save = startedCharacter(database).copyWith(characterName: 'Vari');
    await net.signUp('vari@example.com', 'Vari', 'secret', save, adopt: (_) {});

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

    expect(find.text('Vari'), findsWidgets);
    expect(find.text(emptyBoardMessage(net.boardKey)), findsNothing);
  });

  testWidgets('an empty board no longer asks the player to sync', (tester) async {
    final clock = TestClock();
    final net = buildMultiplayer(database, clock: clock, signedIn: false);
    addTearDown(net.dispose);
    net.setBrowseSocialUnsigned(true);

    final game = buildController(database, clock: clock);
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

    expect(find.text('No scores on this board yet.'), findsOne);
  });
}
