import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/game_popup.dart';

void main() {
  Future<Completer<MassBossChoice>> openChoice(WidgetTester tester) async {
    final completer = Completer<MassBossChoice>();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return GameButton(
                label: 'Fight dragon',
                onPressed: () {
                  completer.complete(showMassBossChoice(context: context, bossName: 'dragon'));
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Fight dragon'));
    await tester.pump();
    return completer;
  }

  testWidgets('mass boss prompt offers Solo, Mass, and Cancel', (tester) async {
    await openChoice(tester);
    expect(find.text('Fight together?'), findsOne);
    expect(find.textContaining('wait up to 60 seconds for other players'), findsOne);
    expect(find.textContaining('Take on dragon alone'), findsOne);
    expect(find.text('Solo'), findsOne);
    expect(find.text('Mass'), findsOne);
    expect(find.text('Cancel'), findsOne);
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
