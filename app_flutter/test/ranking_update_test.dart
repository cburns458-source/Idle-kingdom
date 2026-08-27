import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/session/multiplayer_controller.dart';
import 'package:idle_kingdoms/src/ui/social_view.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';
import 'package:ik_net/testing.dart';
import 'package:ik_rules/ik_rules.dart';
import 'package:ik_runtime/ik_runtime.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  test('sign-up publishes the ranking immediately', () async {
    final clock = TestClock();
    final net = buildMultiplayer(database, clock: clock);
    addTearDown(net.dispose);
    final save = startedCharacter(database);

    await net.signUp('hero@example.com', 'Hero', 'secret', save, adopt: (save, {nowMs}) {});

    expect(net.board, isNotEmpty);
    expect(net.lastRankingSubmitAt, testStartMs);
  });

  test('opening the app publishes again after a short session', () async {
    final clock = TestClock();
    final net = buildMultiplayer(database, clock: clock);
    addTearDown(net.dispose);
    final save = startedCharacter(database);
    await net.signUp('hero@example.com', 'Hero', 'secret', save, adopt: (save, {nowMs}) {});

    clock.advance(60 * 1000);
    await net.onForeground(save);
    expect(net.lastRankingSubmitAt, testStartMs + 60 * 1000);
  });

  test('a second publish in the same couple of seconds is ignored', () async {
    final clock = TestClock();
    final net = buildMultiplayer(database, clock: clock);
    addTearDown(net.dispose);
    final save = startedCharacter(database);
    await net.signUp('hero@example.com', 'Hero', 'secret', save, adopt: (save, {nowMs}) {});

    clock.advance(1000);
    await net.onForeground(save);
    expect(net.lastRankingSubmitAt, testStartMs);
  });

  test('the next UTC hour publishes without a button', () async {
    final clock = TestClock();
    final net = buildMultiplayer(database, clock: clock);
    addTearDown(net.dispose);
    final save = startedCharacter(database);
    await net.signUp('hero@example.com', 'Hero', 'secret', save, adopt: (save, {nowMs}) {});

    clock.advance(60 * 60 * 1000);
    await net.publishForUtcHour(save);
    expect(net.lastRankingSubmitAt, testStartMs + 60 * 60 * 1000);
  });

  test('a failed session refresh asks to sign in again without signing out', () async {
    final clock = TestClock();
    final transport = FakeTransport();
    final net = buildRemoteMultiplayer(database, transport: transport, clock: clock);
    addTearDown(net.dispose);
    final save = startedCharacter(database);
    await net.signUp('vari@example.com', 'Vari', 'secret', save, adopt: (save, {nowMs}) {});
    expect(net.isSignedIn, isTrue);

    transport.failNextWith = 'JWT expired';
    await net.onForeground(save);
    expect(net.isSignedIn, isTrue);
    expect(net.notice, remoteSignInAgain);
  });

  testWidgets('the leaderboard tab has no manual update control', (tester) async {
    final clock = TestClock();
    final net = buildMultiplayer(database, clock: clock);
    addTearDown(net.dispose);
    final save = startedCharacter(database);
    await net.signUp('hero@example.com', 'Hero', 'secret', save, adopt: (save, {nowMs}) {});

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

    expect(find.bySemanticsLabel('Update my ranking'), findsNothing);
    expect(find.text('You can update your ranking again in 1 hour.'), findsNothing);
  });

  testWidgets('a board names the signed-in character without a sync step', (tester) async {
    final clock = TestClock();
    final transport = FakeTransport();
    final net = buildRemoteMultiplayer(database, transport: transport, clock: clock);
    addTearDown(net.dispose);
    final save = startedCharacter(database).copyWith(characterName: 'Vari');
    await net.signUp('vari@example.com', 'Vari', 'secret', save, adopt: (save, {nowMs}) {});

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

  testWidgets('the total level board writes the experience under the level', (tester) async {
    final clock = TestClock();
    final net = buildMultiplayer(database, clock: clock);
    addTearDown(net.dispose);
    final save = startedCharacter(database).copyWith(characterName: 'Vari');
    await net.signUp('vari@example.com', 'Vari', 'secret', save, adopt: (save, {nowMs}) {});

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

    expect(net.boardKey, boardTotalLevel);
    expect(find.text(boardLabel(database.launch, boardTotalLevel)), findsWidgets);
    expect(find.text('${totalLevel(save)}'), findsWidgets);
    expect(find.text('${totalSkillXp(save)} xp'), findsOne);
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

  PlayerSave boosted(PlayerSave save, num level) {
    return save.copyWith(
      skills: [for (final skill in save.skills) skill.copyWith(level: level, xp: 0)],
    );
  }

  void seedRivals(
    LocalMultiplayerService service,
    PlayerSave template, {
    required int count,
    required num level,
  }) {
    for (var i = 0; i < count; i++) {
      final created = service.backend.signUp('rival$i@example.com', 'Rival$i', 'secret');
      expect(created.ok, isTrue, reason: created.reason);
      service.backend.submitLeaderboardSnapshot(
        database.launch,
        created.session!.userId,
        boosted(template, level),
      );
    }
  }

  testWidgets('the own row pins at the bottom when it is off-screen below', (tester) async {
    final clock = TestClock();
    final net = buildMultiplayer(database, clock: clock);
    addTearDown(net.dispose);
    final save = startedCharacter(database).copyWith(characterName: 'Vari');
    await net.signUp('vari@example.com', 'Vari', 'secret', save, adopt: (save, {nowMs}) {});
    seedRivals(net.service as LocalMultiplayerService, save, count: 20, level: 40);
    await net.openLeaderboards(save);

    final game = buildController(database, seed: save, clock: clock);
    addTearDown(game.dispose);
    await pumpPanel(
      tester,
      ListenableBuilder(
        listenable: net,
        builder: (context, _) =>
            SocialView(controller: game, multiplayer: net, section: SocialTab.leaderboards),
      ),
      size: const Size(420, 360),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('own-pin-bottom')), findsOne);
    expect(find.byKey(const ValueKey('own-pin-top')), findsNothing);
  });

  testWidgets('the own row pins at the top when it is off-screen above', (tester) async {
    final clock = TestClock();
    final net = buildMultiplayer(database, clock: clock);
    addTearDown(net.dispose);
    final save = boosted(startedCharacter(database).copyWith(characterName: 'Vari'), 80);
    await net.signUp('vari@example.com', 'Vari', 'secret', save, adopt: (save, {nowMs}) {});
    seedRivals(net.service as LocalMultiplayerService, save, count: 20, level: 2);
    await net.openLeaderboards(save);

    final game = buildController(database, seed: save, clock: clock);
    addTearDown(game.dispose);
    await pumpPanel(
      tester,
      ListenableBuilder(
        listenable: net,
        builder: (context, _) =>
            SocialView(controller: game, multiplayer: net, section: SocialTab.leaderboards),
      ),
      size: const Size(420, 360),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('own-pin-top')), findsNothing);
    expect(find.byKey(const ValueKey('own-pin-bottom')), findsNothing);

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -2400));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('own-pin-top')), findsOne);
    expect(find.byKey(const ValueKey('own-pin-bottom')), findsNothing);
  });

  test('a draft name color waits for the scheduled ranking submit', () async {
    final clock = TestClock();
    final net = buildMultiplayer(database, clock: clock);
    addTearDown(net.dispose);
    final save = startedCharacter(database);
    await net.signUp('hero@example.com', 'Hero', 'secret', save, adopt: (save, {nowMs}) {});

    net.setNameColorDraft('#fa3');
    expect(net.nameColorDraft, '#fa3');
    expect(net.publishedNameColor(net.session!.userId), isNull);
    expect((await net.service.profile(net.session!.userId))?.nameColor, isNull);

    clock.advance(60 * 1000);
    await net.onForeground(save);
    expect(net.publishedNameColor(net.session!.userId), '#FFAA33');
    expect((await net.service.profile(net.session!.userId))?.nameColor, '#FFAA33');
  });

  test('a new device seeds the draft from the published color', () async {
    final clock = TestClock();
    final first = buildMultiplayer(database, clock: clock);
    addTearDown(first.dispose);
    final save = startedCharacter(database);
    await first.signUp('hero@example.com', 'Hero', 'secret', save, adopt: (save, {nowMs}) {});
    first.setNameColorDraft('#FA3');
    await first.publishRanking(save, ignoreDebounce: true);

    final service = first.service as LocalMultiplayerService;
    final storage = MemorySaveStorage();
    restoreTestSession(
      service,
      storage,
      account: const TestAccount(email: 'hero@example.com', username: 'Hero', password: 'secret'),
    );
    final second = MultiplayerController(
      database: database,
      service: service,
      storage: storage,
      clock: clock.read,
    );
    addTearDown(second.dispose);
    await second.refresh(save);
    expect(second.nameColorDraft, '#FFAA33');
    expect(second.publishedNameColor(second.session!.userId), '#FFAA33');
  });
}
