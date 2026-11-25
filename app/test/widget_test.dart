import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mailcontrol_app/main.dart';

void main() {
  testWidgets('MailControlApp renders smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MailControlApp()));
    expect(find.byType(MailControlApp), findsOneWidget);
  });
}
