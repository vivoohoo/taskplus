import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:taskplus/core/api/api_client.dart';
import 'package:taskplus/core/auth/auth_controller.dart';
import 'package:taskplus/core/auth/token_store.dart';
import 'package:taskplus/main.dart';

import 'helpers/fake_api.dart';

void main() {
  testWidgets('phone, then code, then signed in', (tester) async {
    final tokens = MemoryTokenStore();
    final api = FakeApi((method, path, body, headers) => switch (path) {
          '/auth/otp/request' => (200, {'sent': true}),
          '/auth/otp/verify' => body!['code'] == '123456'
              ? (200, {'accessToken': 'a', 'refreshToken': 'r', 'user': {'id': 'u1', 'name': 'Riya Shah', 'role': 'staff', 'departmentId': 'd1'}})
              : (401, {'error': {'code': 'UNAUTHORIZED', 'message': 'Wrong number or code.'}}),
          _ => (404, {'error': {'code': 'NOT_FOUND', 'message': 'Not found.'}}),
        });
    await tester.pumpWidget(ProviderScope(overrides: [
      tokenStoreProvider.overrideWithValue(tokens),
      apiClientProvider.overrideWith((ref) => ApiClient(baseUrl: 'http://x', tokens: tokens, onSignedOut: () {}, adapter: api)),
    ], child: const TaskPlusApp()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('phone')), '9800000002');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('code')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('code')), '000000');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Wrong number or code.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('code')), '123456');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Signed in as Riya Shah'), findsOneWidget);
    expect((await tokens.read())!.access, 'a');
  });
}
