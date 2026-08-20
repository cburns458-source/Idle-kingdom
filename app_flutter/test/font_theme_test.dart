import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';

void main() {
  testWidgets('theme copy stays on regular 7:12 Serif', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(body: Text('Restoria')),
      ),
    );

    final paragraph = tester.renderObject<RenderParagraph>(find.text('Restoria'));
    expect(paragraph.text.style?.fontFamily, gameFontFamily);
    expect(paragraph.text.style?.fontWeight, FontWeight.w400);
  });
}
