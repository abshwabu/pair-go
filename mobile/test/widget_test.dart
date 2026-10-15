import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/router.dart';
import 'package:mobile/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('PairApp boots to splash screen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: PairApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(RouteStubScreen), findsOneWidget);
    expect(find.text(AppRoutes.splash), findsAtLeastNWidgets(1));
  });
}
