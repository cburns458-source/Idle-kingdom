import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/feedback_sheet.dart';
import 'package:idle_kingdoms/src/ui/menu_view.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  Future<void> pumpForm(
    WidgetTester tester, {
    Future<FeedbackSubmitResult> Function(FeedbackRequest request)? onSubmit,
    VoidCallback? onSent,
  }) async {
    await pumpPanel(
      tester,
      Material(
        child: FeedbackForm(
          onSubmit: onSubmit ?? (request) async => FeedbackSubmitResult.ok('fb_1'),
          onClose: () {},
          onSent: onSent ?? () {},
          gameArea: 'LOC-0001',
          buildId: 'testbuild',
          platform: 'web',
        ),
      ),
    );
  }

  testWidgets('empty send shows inline errors and does not submit', (tester) async {
    var calls = 0;
    await pumpForm(
      tester,
      onSubmit: (request) async {
        calls += 1;
        return FeedbackSubmitResult.ok('fb_1');
      },
    );
    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(find.text('Summary is too short.'), findsOneWidget);
    expect(find.text('Details are too short.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('valid send disables immediately and does not double submit', (tester) async {
    var calls = 0;
    final completer = Completer<FeedbackSubmitResult>();
    await pumpForm(
      tester,
      onSubmit: (request) {
        calls += 1;
        return completer.future;
      },
    );
    await tester.enterText(find.byKey(const Key('feedback-title')), 'Combat stun lock');
    await tester.enterText(
      find.byKey(const Key('feedback-body')),
      'The goblin stun never ends after the second hit.',
    );
    await tester.pump();
    await tester.tap(find.byType(GameButton));
    await tester.pump();
    expect(calls, 1);
    await tester.tap(find.byType(GameButton));
    await tester.pump();
    expect(calls, 1);
    completer.complete(FeedbackSubmitResult.ok('fb_1'));
    await tester.pump();
  });

  testWidgets('cooldown response changes the Send label', (tester) async {
    await pumpForm(
      tester,
      onSubmit: (request) async {
        return const FeedbackSubmitResult.failed(
          feedbackCooldownMessage,
          retryAfterSeconds: 45,
          code: feedbackCodeCooldown,
        );
      },
    );
    await tester.enterText(find.byKey(const Key('feedback-title')), 'Combat stun lock');
    await tester.enterText(
      find.byKey(const Key('feedback-body')),
      'The goblin stun never ends after the second hit.',
    );
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(find.text('Send in 45s'), findsOneWidget);
  });

  testWidgets('player option asks for a name', (tester) async {
    await pumpForm(tester);
    await tester.tap(find.text('Player'));
    await tester.pump();
    expect(find.byKey(const Key('feedback-player')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('feedback-title')), 'Spam in global chat');
    await tester.enterText(
      find.byKey(const Key('feedback-body')),
      'This player is advertising gold sales.',
    );
    await tester.tap(find.text('Send'));
    await tester.pump();
    expect(find.text(feedbackPlayerMissing), findsOneWidget);
  });

  testWidgets('selected kind chip uses board-readable green', (tester) async {
    await pumpForm(tester);
    expect(tester.widget<Text>(find.text('Bug')).style?.color, Palette.skillXp);
    expect(contrastRatio(Palette.skillXp, UiChrome.wood.board), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(Palette.skillXp, UiChrome.stone.board), greaterThanOrEqualTo(4.5));

    await tester.tap(find.text('Suggestion'));
    await tester.pump();
    expect(tester.widget<Text>(find.text('Suggestion')).style?.color, Palette.skillXp);
    expect(tester.widget<Text>(find.text('Bug')).style?.color, Palette.parchmentText);
  });

  testWidgets('signed-in settings shows the report button; signed-out does not', (tester) async {
    final signedOut = buildMultiplayer(database, signedIn: false);
    final game = buildController(database);
    addTearDown(game.dispose);
    addTearDown(signedOut.dispose);
    await pumpPanel(tester, MenuView(controller: game, multiplayer: signedOut));
    expect(find.text('Feedback'), findsNothing);
    expect(find.text('Report / Suggestion'), findsNothing);

    final signedIn = buildMultiplayer(database, signedIn: true);
    addTearDown(signedIn.dispose);
    await pumpPanel(tester, MenuView(controller: game, multiplayer: signedIn));
    expect(find.text('Feedback'), findsOneWidget);
    expect(find.text('Report / Suggestion'), findsOneWidget);
  });
}
