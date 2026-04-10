import 'package:flutter_test/flutter_test.dart';
import 'package:xi_shua_shua/app.dart';

void main() {
  testWidgets('App should build', (WidgetTester tester) async {
    await tester.pumpWidget(const XiShuaShuaApp());
  });
}
