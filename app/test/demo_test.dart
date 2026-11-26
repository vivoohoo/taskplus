import 'package:flutter_test/flutter_test.dart';
import 'package:taskplus/core/api/api_client.dart';
import 'package:taskplus/core/auth/token_store.dart';
import 'package:taskplus/data/models.dart';
import 'package:taskplus/data/repository.dart';
import 'package:taskplus/demo/demo_backend.dart';

void main() {
  test('demo backend answers every screen for every person', () async {
    final api = DemoApi();
    for (final p in api.backend.users) {
      final tokens = MemoryTokenStore();
      final client = ApiClient(baseUrl: 'https://demo.local', tokens: tokens, onSignedOut: () {}, adapter: api);
      final r = await client.dio.post('/auth/login', data: {'phone': p['phone'], 'password': 'x'});
      await tokens.save(r.data['accessToken'] as String, r.data['refreshToken'] as String);
      final repo = Repository(client, absolute: (s) => s);
      final threads = await repo.threads();
      for (final t in threads) {
        for (final i in (await repo.messages(t.id)).items) {
          if (i.task != null) { await repo.history(i.task!.id); await repo.task(i.task!.id); }
        }
      }
      await repo.counts();
      for (final f in ['my_pending', 'overdue', 'sent_by_me', 'closed']) { await repo.tasks(f); }
      await repo.profile();
      await repo.search('a');
      await repo.searchTasks('profit');
      for (final d in await repo.departments()) { await repo.department(d.id); }
      await repo.notificationSettings(); await repo.holidays(); await repo.suggestions(); await repo.customers();
      if (p['role'] != 'staff') await repo.team();
    }
  });

  test('send, accept, complete, verify, close', () async {
    final api = DemoApi();
    final b = api.backend;
    Future<Repository> as(String phone) async {
      final tokens = MemoryTokenStore();
      final client = ApiClient(baseUrl: 'https://demo.local', tokens: tokens, onSignedOut: () {}, adapter: api);
      final r = await client.dio.post('/auth/login', data: {'phone': phone, 'password': 'x'});
      await tokens.save(r.data['accessToken'] as String, r.data['refreshToken'] as String);
      return Repository(client, absolute: (s) => s);
    }
    final riya = await as('9800000002'), kunal = await as('9800000011');
    final dev = b.depts.firstWhere((d) => d['name'] == 'Development')['id'] as String;
    final th = await riya.openThread('department', dev);
    final sent = await riya.send(Draft(clientMsgId: 'c1', threadId: th.id, kind: 'text', bodyText: 'Urgent: Profit NX printing stuck at Om Logistics, Surat 9825012345'));
    expect(sent.task!.priority, 'High');
    expect(sent.task!.module, 'Profit NX');
    expect(sent.task!.customerName, 'Om Logistics');
    expect(sent.task!.actions, contains('cancel'));
    final id = sent.task!.id;
    expect((await kunal.accept(id)).status, 'Accepted');
    expect(() => kunal.action(id, 'complete'), throwsA(isA<ApiException>()));
    expect((await kunal.action(id, 'complete', {'remarks': 'Fixed'})).status, 'Completed');
    expect((await riya.action(id, 'verify')).status, 'Verified');
    expect((await riya.action(id, 'close', {'resolution': 'Done', 'customerInformed': 'yes'})).status, 'Closed');
  });
}
