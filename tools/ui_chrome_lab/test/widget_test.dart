import 'package:flutter_test/flutter_test.dart';
import 'package:ui_chrome_lab/main.dart';

void main() {
  testWidgets('lab boots', (tester) async {
    await tester.pumpWidget(const UiChromeLabApp());
    expect(find.textContaining('UI CHROME LAB'), findsOneWidget);
  });
}
