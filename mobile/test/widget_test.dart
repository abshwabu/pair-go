import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart';
import 'package:mobile/router.dart';

void main() {
  testWidgets('Blank home screen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: PairApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BlankHomeScreen), findsOneWidget);
  });
}
