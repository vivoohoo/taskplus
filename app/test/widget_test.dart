import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:taskplus/core/api/api_client.dart';
import 'package:taskplus/core/auth/auth_controller.dart';
import 'package:taskplus/core/auth/token_store.dart';
import 'package:drift/native.dart';
import 'package:taskplus/core/realtime.dart';
import 'package:taskplus/data/outbox.dart';
import 'package:taskplus/data/providers.dart';
import 'package:taskplus/main.dart';

import 'helpers/fake_api.dart';

void main() {
  testWidgets('phone, then code, then signed in', (tester) async {
    final tokens = MemoryTokenStore();
    final api = FakeApi((method, path, body, headers) => switch (path) {
          '/auth/login' => body!['password'] == 'Taskplus@2026'
              ? (200, {'accessToken': 'a', 'refreshToken': 'r', 'user': {'id': 'u1', 'name': 'Riya Shah', 'role': 'staff', 'departmentId': 'd1'}})
              : (401, {'error': {'code': 'UNAUTHORIZED', 'message': 'Wrong number or password.'}}),
          '/threads' => (200, {'threads': []}),
          '/tasks/counts' => (200, {'myPending': 3, 'overdue': 1}),
          _ => (404, {'error': {'code': 'NOT_FOUND', 'message': 'Not found.'}}),
        });
    await tester.pumpWidget(ProviderScope(overrides: [
      tokenStoreProvider.overrideWithValue(tokens),
      apiClientProvider.overrideWith((ref) => ApiClient(baseUrl: 'http://x', tokens: tokens, onSignedOut: () {}, adapter: api)),
      outboxDbProvider.overrideWithValue(OutboxDb(NativeDatabase.memory())),
      realtimeProvider.overrideWith((ref) async => null),
    ], child: const TaskPlusApp()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('phone')), '9800000002');
    await tester.enterText(find.byKey(const Key('password')), 'wrong123');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Wrong number or password.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('password')), 'Taskplus@2026');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search')), findsOneWidget); // home: search, filters, chats
    expect(find.byKey(const Key('filter-overdue')), findsOneWidget);
    expect((await tokens.read())!.access, 'a');
  });
}
