import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/tutorial_spotlight.dart';
import 'package:ik_rules/ik_rules.dart';

void main() {
  testWidgets('the hint bar shows the next-step line and is tappable', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: TutorialHintBar(
            hint: const TutorialHudHint(label: 'Gather potatoes 3/5', locationId: 'LOC-0001'),
            onTap: () => taps++,
          ),
        ),
      ),
    );
    expect(find.text('Gather potatoes 3/5'), findsOneWidget);
    await tester.tap(find.byType(TutorialHintBar));
    expect(taps, 1);
  });

  testWidgets('a missing spotlight target paints nothing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: TutorialAnchorsScope(
          child: const Stack(
            children: [
              ColoredBox(color: Colors.white),
              TutorialSpotlight(target: TutorialSpotlightId.fields),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.touch_app), findsNothing);
  });
}
