// On a device or emulator against the real API (docker compose up; default http://10.0.2.2:8080):
//   flutter test integration_test/login_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:taskplus/core/auth/auth_controller.dart';
import 'package:taskplus/core/auth/token_store.dart';
import 'package:taskplus/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('signs in against the real API with the dev OTP', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [tokenStoreProvider.overrideWithValue(MemoryTokenStore())],
      child: const TaskPlusApp(),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('phone')), '9800000002');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.enterText(find.byKey(const Key('code')), '123456');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('Signed in as Riya Shah'), findsOneWidget);
  });
}
