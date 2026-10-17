import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/game_popup.dart';

void main() {
  Future<Completer<MassBossChoice>> openChoice(
    WidgetTester tester, {
    String bossName = 'Dragon',
  }) async {
    final completer = Completer<MassBossChoice>();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return GameButton(
                label: 'Fight $bossName',
                onPressed: () {
                  completer.complete(showMassBossChoice(context: context, bossName: bossName));
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Fight $bossName'));
    await tester.pump();
    return completer;
  }

  testWidgets('mass boss prompt offers Solo, Mass, and Cancel without helper copy', (tester) async {
    await openChoice(tester);
    expect(find.text('Dragon'), findsWidgets);
    expect(find.text('Solo'), findsOne);
    expect(find.text('Mass'), findsOne);
    expect(find.text('Cancel'), findsOne);
    expect(find.text('Fight together?'), findsNothing);
    expect(find.textContaining('wait up to 60 seconds'), findsNothing);
    expect(find.textContaining('Take on'), findsNothing);
  });

  testWidgets('Mother Squid uses the same Solo / Mass choice', (tester) async {
    await openChoice(tester, bossName: 'Mother Squid');
    expect(find.text('Mother Squid'), findsWidgets);
    expect(find.text('Solo'), findsOne);
    expect(find.text('Mass'), findsOne);
  });

  testWidgets('Mass returns mass, Solo returns solo, Cancel returns cancel', (tester) async {
    var pending = await openChoice(tester);
    await tester.tap(find.text('Mass'));
    await tester.pumpAndSettle();
    expect(await pending.future, MassBossChoice.mass);

    pending = await openChoice(tester);
    await tester.tap(find.text('Solo'));
    await tester.pumpAndSettle();
    expect(await pending.future, MassBossChoice.solo);

    pending = await openChoice(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await pending.future, MassBossChoice.cancel);
  });
}
