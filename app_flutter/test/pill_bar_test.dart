import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:idle_kingdoms/src/theme.dart';

void main() {
  testWidgets('a half-full pill still spans the whole track', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 200, child: PillBar(value: 0.5, gradient: Meters.hudHp, height: 8)),
        ),
      ),
    );

    expect(tester.getSize(find.byType(PillBar)).width, 200);
  });

  testWidgets('an empty pill is still as wide as a full one', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(width: 180, child: PillBar(value: 0, gradient: Meters.hudHp, height: 8)),
              SizedBox(width: 180, child: PillBar(value: 1, gradient: Meters.hudHp, height: 8)),
            ],
          ),
        ),
      ),
    );

    final sizes = tester.getSize(find.byType(PillBar).first);
    final full = tester.getSize(find.byType(PillBar).last);
    expect(sizes.width, full.width);
    expect(sizes.width, 180);
  });
}
