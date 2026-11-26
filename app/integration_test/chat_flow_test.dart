// On a device against the real API (docker compose up): flutter test integration_test/chat_flow_test.dart
// Riya sends Dhaval a task through the API; Dhaval signs in on the phone, opens the chat from search,
// sees it as a task card, and replies from the composer.
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:taskplus/core/auth/auth_controller.dart';
import 'package:taskplus/core/auth/token_store.dart';
import 'package:taskplus/core/config.dart';
import 'package:taskplus/data/outbox.dart';
import 'package:taskplus/data/providers.dart';
import 'package:taskplus/main.dart';
import 'package:uuid/uuid.dart';

Future<void> waitFor(WidgetTester tester, Finder f, {int seconds = 15}) async {
  for (var i = 0; i < seconds * 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    if (f.evaluate().isNotEmpty) return;
  }
  expect(f, findsWidgets);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('open a chat from search, see the task card, reply', (tester) async {
    // Riya sends Dhaval a task through the API.
    final api = Dio(BaseOptions(baseUrl: '${AppConfig.apiBaseUrl}/v1'));
    final riya = (await api.post('/auth/otp/verify', data: {'phone': '9800000002', 'code': '123456'})).data;
    final auth = Options(headers: {'authorization': 'Bearer ${riya['accessToken']}'});
    final search = (await api.get('/search', queryParameters: {'q': 'Dhaval'}, options: auth)).data['results'] as List;
    final thread = (await api.post('/threads/open', data: {'targetType': 'user', 'targetId': search.first['id']}, options: auth)).data['thread'];
    final words = 'Printer at Kaveri Steel jams on every invoice ${DateTime.now().millisecondsSinceEpoch}';
    await api.post('/threads/${thread['id']}/messages', data: {'clientMsgId': const Uuid().v4(), 'kind': 'text', 'bodyText': words}, options: auth);

    // Dhaval on the phone.
    await tester.pumpWidget(ProviderScope(overrides: [
      tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
      outboxDbProvider.overrideWithValue(OutboxDb(NativeDatabase.memory())),
    ], child: const TaskPlusApp()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('phone')), '9800000005');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.enterText(find.byKey(const Key('code')), '123456');
    await tester.tap(find.text('Sign in'));
    await waitFor(tester, find.byKey(const Key('search')));

    await tester.tap(find.byKey(const Key('search')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search-input')), 'Riya');
    await waitFor(tester, find.text('Riya Shah'));
    await tester.tap(find.text('Riya Shah').first);

    // Her message arrives as a task card (no AI keys in dev: "Needs review" with the raw text).
    await waitFor(tester, find.text(words));
    expect(find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('task-')), findsWidgets);

    // Reply from the composer: shows at once, then is confirmed by the server.
    await tester.enterText(find.byKey(const Key('composer')), 'On my way to check it');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send')));
    await waitFor(tester, find.text('On my way to check it'));
    await waitFor(tester, find.textContaining('· Open'));
  });
}
