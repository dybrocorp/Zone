import 'package:flutter_test/flutter_test.dart';
import 'package:zone/main.dart';

void main() {
  testWidgets('ZoneApp renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const ZoneApp());
    await tester.pump();
  });
}
