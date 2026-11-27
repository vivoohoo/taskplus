// Ornate look (docs/ORNATE_UI.md): the case page and a person's chat against a fake server.
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:taskplus/core/api/api_client.dart';
import 'package:taskplus/core/auth/auth_controller.dart';
import 'package:taskplus/core/auth/token_store.dart';
import 'package:taskplus/core/realtime.dart';
import 'package:taskplus/core/theme.dart';
import 'package:taskplus/data/outbox.dart';
import 'package:taskplus/data/providers.dart';
import 'package:taskplus/features/case/case_screen.dart';
import 'package:taskplus/features/person/person_screen.dart';

import 'helpers/fake_api.dart';

Map<String, dynamic> task(String status, List<String> actions, {String sender = 'u2'}) => {
      'message': {'id': 'm1', 'threadId': 'th1', 'senderId': sender, 'clientMsgId': 'c1', 'kind': 'text', 'bodyText': 'Printing broken at Mehta Traders',
        'attachments': [], 'createdAt': '2026-11-27T05:00:00.000Z'},
      'task': {'id': 't1', 'messageId': 'm1', 'threadId': 'th1', 'ticketNo': 'ORN-SS-2627-00042', 'priority': 'High', 'status': status, 'aiStatus': 'done',
        'subject': 'Profit NX: printing broken', 'updatedAt': '2026-11-27T05:00:00.000Z', 'createdAt': '2026-11-27T05:00:00.000Z', 'actions': actions,
        'dueAt': '2099-01-01T00:00:00.000Z', 'clock': {'state': 'not started', 'usedMs': 0}},
      'party': {'key': 'u:u2', 'name': 'Riya Shah', 'sub': 'Support'}, 'overdue': false, 'requesterId': sender,
      'last': {'text': 'Riya: Printing broken', 'at': '2026-11-27T05:00:00.000Z'},
    };

Future<List<String>> pump(WidgetTester tester, Widget screen, Map<String, (int, Object)> routes) async {
  final calls = <String>[];
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final tokens = MemoryTokenStore();
  await tokens.save('a', 'r');
  final api = FakeApi((method, path, body, headers) { calls.add('$method $path'); return routes['$method $path'] ?? routes[path] ?? (404, {'error': {'code': 'NOT_FOUND', 'message': path}}); });
  await tester.pumpWidget(ProviderScope(overrides: [
    tokenStoreProvider.overrideWithValue(tokens),
    apiClientProvider.overrideWith((ref) => ApiClient(baseUrl: 'http://x', tokens: tokens, onSignedOut: () {}, adapter: api)),
    outboxDbProvider.overrideWithValue(OutboxDb(NativeDatabase.memory())),
    realtimeProvider.overrideWith((ref) async => null),
    authProvider.overrideWith(() => _SignedIn()),
  ], child: MaterialApp(theme: AppTheme.light(), home: screen)));
  await tester.pumpAndSettle();
  return calls;
}

/// The outbox's drift stream closes on a zero timer: let it run before the test ends.
Future<void> unmount(WidgetTester tester) async { await tester.pumpWidget(const SizedBox()); await tester.pump(Duration.zero); }

class _SignedIn extends AuthController {
  @override
  Future<AppUser?> build() async => AppUser(id: 'u1', name: 'Kunal Mehta', role: 'staff', departmentId: 'd1');
}

void main() {
  testWidgets('case page: status strip, tabs, action card; Accept calls the server', (tester) async {
    final calls = await pump(tester, const CaseScreen(taskId: 't1'), {
      '/cases/t1': (200, task('Open', ['accept', 'request_reject'])),
      '/tasks/t1/history': (200, {'events': [], 'files': [], 'replies': [], 'subTasks': [], 'parent': null}),
      '/departments': (200, {'departments': []}),
      '/threads/open': (200, {'thread': {'id': 'th1', 'type': 'department', 'title': 'Support'}}),
      'POST /tasks/t1/actions/accept': (200, {'task': (task('Accepted', ['complete'])['task'] as Map)}),
    });
    expect(find.text('Pending Acceptance'), findsWidgets);
    expect(find.textContaining('Accept within'), findsWidgets);
    for (final t in ['Activity', 'Details', 'Sub-Tasks', 'Files', 'Audit Trail']) { expect(find.byKey(Key('tab-$t')), findsOneWidget); }
    expect(find.text('Choose an action'), findsOneWidget);
    expect(find.text('Printing broken at Mehta Traders'), findsOneWidget);
    await tester.tap(find.byKey(const Key('action-accept')));
    await tester.pumpAndSettle();
    expect(calls, contains('POST /tasks/t1/actions/accept'));
    expect(find.text('Accepted'), findsWidgets);
    await tester.pump(const Duration(seconds: 5)); // let the snackbar finish
    await unmount(tester);
  });

  testWidgets("person's chat: summary line and Not accepted / Accepted", (tester) async {
    await pump(tester, const PersonScreen(partyKey: 'u:u2'), {
      '/timeline': (200, {'party': {'key': 'u:u2', 'name': 'Riya Shah', 'sub': 'Support'}, 'items': [task('Open', ['accept'])]}),
      '/threads/open': (200, {'thread': {'id': 'th1', 'type': 'direct', 'title': 'Riya Shah'}}),
      '/departments': (200, {'departments': []}),
    });
    expect(find.text('1 open · 1 for you · 1 not accepted'), findsOneWidget);
    expect(find.text('Not accepted (1)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('filter-Accepted')));
    await tester.pumpAndSettle();
    expect(find.text('Nothing accepted yet.'), findsOneWidget);
    expect(find.byKey(const Key('composer')), findsOneWidget);
    await unmount(tester);
  });
}
