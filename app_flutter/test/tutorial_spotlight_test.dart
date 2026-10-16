import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';
import 'package:idle_kingdoms/src/ui/dialogue_text.dart';
import 'package:idle_kingdoms/src/ui/dialogue_window.dart';
import 'package:idle_kingdoms/src/ui/tutorial_spotlight.dart';
import 'package:ik_content/ik_content.dart';
import 'package:ik_rules/ik_rules.dart';

DialogueText _emptyDialogueText() {
  return DialogueText(GameDatabase(<String, Object?>{'DialogueChoices': <Object?>[]}));
}

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

  testWidgets('the hole matches the target widget', (tester) async {
    final targetKey = GlobalKey();
    await _pumpSpotlight(
      tester,
      target: Positioned(
        left: 80,
        top: 160,
        child: TutorialAnchor(
          id: TutorialSpotlightId.fields,
          child: SizedBox(
            key: targetKey,
            width: 120,
            height: 48,
            child: const ColoredBox(color: Colors.red),
          ),
        ),
      ),
    );

    final target = tester.getRect(find.byKey(targetKey));
    final hole = _dimHole(tester);
    expect(hole, isNotNull);
    expect((hole!.center - target.center).distance, lessThan(1));
    expect(hole.width, closeTo(target.width + tutorialSpotlightPad * 2, 0.5));
    expect(hole.height, closeTo(target.height + tutorialSpotlightPad * 2, 0.5));
  });

  testWidgets('only the target receives taps', (tester) async {
    var targetTaps = 0;
    var otherTaps = 0;
    await _pumpSpotlight(
      tester,
      extras: [
        Positioned(
          left: 20,
          top: 20,
          child: GestureDetector(
            onTap: () => otherTaps++,
            child: const SizedBox(width: 80, height: 40, child: ColoredBox(color: Colors.blue)),
          ),
        ),
      ],
      target: Positioned(
        left: 140,
        top: 300,
        child: TutorialAnchor(
          id: TutorialSpotlightId.fields,
          child: GestureDetector(
            onTap: () => targetTaps++,
            child: const SizedBox(width: 100, height: 40, child: ColoredBox(color: Colors.red)),
          ),
        ),
      ),
    );

    await tester.tapAt(const Offset(60, 40));
    await tester.tapAt(const Offset(190, 320));
    expect(otherTaps, 0);
    expect(targetTaps, 1);
  });

  testWidgets('the pointer flips when the target sits near an edge', (tester) async {
    expect(
      tutorialPointerSideFor(const Rect.fromLTWH(10, 200, 40, 40), const Size(400, 800)),
      TutorialPointerSide.right,
    );
    expect(
      tutorialPointerSideFor(const Rect.fromLTWH(350, 200, 40, 40), const Size(400, 800)),
      TutorialPointerSide.left,
    );
    expect(
      tutorialPointerSideFor(const Rect.fromLTWH(10, 10, 40, 40), const Size(80, 400)),
      TutorialPointerSide.below,
    );
    expect(
      tutorialPointerSideFor(const Rect.fromLTWH(10, 350, 40, 40), const Size(80, 400)),
      TutorialPointerSide.above,
    );

    await _pumpSpotlight(
      tester,
      target: const Positioned(
        left: 340,
        top: 200,
        child: TutorialAnchor(
          id: TutorialSpotlightId.fields,
          child: SizedBox(width: 50, height: 40, child: ColoredBox(color: Colors.red)),
        ),
      ),
    );

    final pointer = tester.getRect(find.byKey(const Key('tutorial-spotlight-pointer')));
    final hole = _dimHole(tester)!;
    expect(pointer.right, lessThanOrEqualTo(400));
    expect(pointer.left, greaterThanOrEqualTo(0));
    expect(pointer.center.dx, lessThan(hole.center.dx));
    expect(find.byIcon(Icons.arrow_right), findsOneWidget);
  });

  testWidgets('a missing spotlight target paints nothing and lets taps through', (tester) async {
    var behindTaps = 0;
    await _pumpSpotlight(
      tester,
      extras: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => behindTaps++,
            child: const ColoredBox(color: Colors.white),
          ),
        ),
      ],
    );
    expect(find.byKey(const Key('tutorial-spotlight-dim')), findsNothing);
    expect(find.byKey(const Key('tutorial-spotlight-pointer')), findsNothing);
    expect(find.byIcon(Icons.touch_app), findsNothing);

    await tester.tapAt(const Offset(200, 400));
    expect(behindTaps, 1);
  });

  testWidgets('an off-screen target drops the dim and pointer', (tester) async {
    await _pumpSpotlight(
      tester,
      target: const Positioned(
        left: -400,
        top: -400,
        child: TutorialAnchor(
          id: TutorialSpotlightId.fields,
          child: SizedBox(width: 80, height: 40, child: ColoredBox(color: Colors.red)),
        ),
      ),
    );
    expect(find.byKey(const Key('tutorial-spotlight-dim')), findsNothing);
    expect(find.byKey(const Key('tutorial-spotlight-pointer')), findsNothing);
  });

  testWidgets('Fennel\'s docked panel advances on tap and shows choices', (tester) async {
    final chosen = <String>[];
    var closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: FennelDialoguePanel(
              view: const DialogueView(
                dialogueId: 'DLG-0006',
                nodeId: 'DNODE-0026',
                speakerName: 'Fennel',
                npcId: 'NPC-0014',
                line: 'Well, that settles that.',
                finished: false,
                choices: [DialogueChoiceView(choiceId: 'DCH-0036', label: 'Continue')],
              ),
              text: _emptyDialogueText(),
              onChoose: chosen.add,
              onClose: () => closed++,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('fennel-dialogue-panel')), findsOneWidget);
    expect(find.text('Well, that settles that.'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    await tester.tap(find.text('Well, that settles that.'));
    expect(chosen, ['DCH-0036']);
    expect(closed, 0);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: FennelDialoguePanel(
            view: const DialogueView(
              dialogueId: 'DLG-0006',
              nodeId: 'DNODE-0009',
              speakerName: 'Fennel',
              npcId: 'NPC-0014',
              line: 'Which way?',
              finished: false,
              choices: [
                DialogueChoiceView(choiceId: 'DCH-A', label: 'Left'),
                DialogueChoiceView(choiceId: 'DCH-B', label: 'Right'),
              ],
            ),
            text: _emptyDialogueText(),
            onChoose: chosen.add,
            onClose: () => closed++,
          ),
        ),
      ),
    );

    chosen.clear();
    await tester.tap(find.text('Which way?'));
    expect(chosen, isEmpty);
    await tester.tap(find.text('Right'));
    expect(chosen, ['DCH-B']);
  });
}

Future<void> _pumpSpotlight(
  WidgetTester tester, {
  Widget? target,
  List<Widget> extras = const [],
  Size size = const Size(400, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: TutorialAnchorsScope(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ...extras,
                ?target,
                const Positioned.fill(child: TutorialSpotlight(target: TutorialSpotlightId.fields)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Rect? _dimHole(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(find.byKey(const Key('tutorial-spotlight-dim')));
  return (paint.painter! as TutorialDimPainter).hole;
}
