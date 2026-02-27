// Basic smoke test for VitableApp.
import 'package:flutter_test/flutter_test.dart';

import 'package:vitable_chat/main.dart';

void main() {
  testWidgets('VitableApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const VitableApp());
  });
}
