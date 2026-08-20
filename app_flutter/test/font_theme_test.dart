import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';

void main() {
  testWidgets('bold copy stays on 7:12 Serif instead of falling back', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: Text('Restoria', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    );

    final paragraph = tester.renderObject<RenderParagraph>(find.text('Restoria'));
    expect(paragraph.text.style?.fontFamily, gameFontFamily);
  });
}
