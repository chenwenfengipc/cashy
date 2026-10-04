import 'package:flutter_test/flutter_test.dart';

import 'package:cashy/main.dart';
import 'package:cashy/providers/settings_provider.dart';
import 'package:cashy/providers/transaction_provider.dart';

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(CashyApp(
      settingsProvider: SettingsProvider(),
      txProvider: TransactionProvider(),
    ));
    expect(find.byType(CashyApp), findsOneWidget);
  });
}
