import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_net/ik_net.dart';

import 'support/harness.dart';

void main() {
  late LoadedDatabase database;

  setUpAll(() {
    database = loadDatabaseFromRepo();
  });

  test('chat filter starts on and can be turned off', () {
    final net = buildMultiplayer(database);
    addTearDown(net.dispose);
    expect(net.filterChatProfanity, isTrue);
    net.setFilterChatProfanity(false);
    expect(net.filterChatProfanity, isFalse);
  });

  test('guild milestone lines start shown and can be hidden', () {
    final net = buildMultiplayer(database);
    addTearDown(net.dispose);
    expect(net.showGuildMilestones, isTrue);
    net.setShowGuildMilestones(false);
    expect(net.showGuildMilestones, isFalse);
  });

  test('developer slash lines parse without posting', () {
    expect(parseDevCommandLine('hello'), isNull);
    final give = parseDevCommandLine('/give potato 5');
    expect(give?.command, 'give');
    expect(give?.tokens, <String>['potato', '5']);
  });

  testWidgets('Settings no longer shows Testing tools', (tester) async {
    final controller = buildController(database, seed: startedCharacter(database));
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(900, 2400));

    await openChinScreen(tester, 'Settings');
    expect(find.text('Testing tools'), findsNothing);
    expect(find.text('Testing'), findsNothing);
    expect(find.text('Appearance'), findsOne);
    await tester.tap(find.text('Appearance'));
    await tester.pump();
    expect(find.text('Player sprite'), findsOne);
  });
}
