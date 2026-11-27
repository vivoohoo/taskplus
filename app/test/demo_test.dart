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
      // Ornate lists, chats, case pages and the bell.
      for (final tab in ['my', 'queue', 'all']) {
        for (final chip in ['All', 'Active', 'To Verify', 'Sent by me', 'Overdue/Escalated', 'Verified / Closed']) {
          final l = await repo.cases(CaseQuery(tab: tab, chip: chip));
          for (final r in l.rows) { await repo.caseOf(r.task.id); await repo.timeline(r.party.key); }
        }
      }
      await repo.caseCounts();
      await repo.notifications();
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

  test('private notes, /subtask and the bell', () async {
    final api = DemoApi();
    final b = api.backend;
    Future<Repository> as(String phone) async {
      final tokens = MemoryTokenStore();
      final client = ApiClient(baseUrl: 'https://demo.local', tokens: tokens, onSignedOut: () {}, adapter: api);
      final r = await client.dio.post('/auth/login', data: {'phone': phone, 'password': 'x'});
      await tokens.save(r.data['accessToken'] as String, r.data['refreshToken'] as String);
      return Repository(client, absolute: (s) => s);
    }
    final riya = await as('9800000002'), kunal = await as('9800000011'), karan = await as('9800000003');
    final notes = await riya.threadFor('self');
    final n = await riya.send(Draft(clientMsgId: 'n1', threadId: notes.id, kind: 'text', bodyText: 'Remember the renewal'));
    expect(n.task!.isNote, true);
    // Demo voice note: the words heard stand in for the audio.
    final v = await riya.send(Draft(clientMsgId: 'v1', threadId: notes.id, kind: 'voice', bodyText: 'Call Mehta Traders at 4 pm', audioDurationS: 3));
    expect(v.message.kind, 'voice');
    expect(v.message.transcript, 'Call Mehta Traders at 4 pm');
    expect(v.message.audioKey, 'demo:speech');
    expect((await riya.caseOf(n.task!.id)).party.key, 'self');

    final dev = b.depts.firstWhere((d) => d['name'] == 'Development')['id'] as String;
    final sup = b.depts.firstWhere((d) => d['name'] == 'Support')['id'] as String;
    final p = await riya.send(Draft(clientMsgId: 'p1', threadId: (await riya.openThread('department', dev)).id, kind: 'text', bodyText: 'New server for Ornate'));
    expect((await kunal.notifications()).unread, greaterThan(0));
    await kunal.accept(p.task!.id);
    expect((await kunal.task(p.task!.id)).task!.actions, contains('hand_off'));
    final sub = await kunal.send(Draft(clientMsgId: 's1', threadId: (await kunal.openThread('department', sup)).id, kind: 'text', bodyText: 'Install SQL Server', parentTaskId: p.task!.id));
    expect(sub.task!.ticketNo, '${p.task!.ticketNo}/T2');
    expect((await kunal.task(p.task!.id)).task!.status, 'WaitingDept');
    await karan.accept(sub.task!.id);
    await karan.action(sub.task!.id, 'complete', {'remarks': 'Installed'});
    expect((await kunal.task(p.task!.id)).task!.status, 'InProgress');
    expect((await riya.cases(const CaseQuery(tab: 'my'))).rows.any((r) => r.party.key == 'u:${b.users.firstWhere((u) => u['name'] == 'Kunal Mehta')['id']}'), true);
  });
}
