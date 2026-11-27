// The demo's shared data: two browsers (two DemoApi instances) on one store see each other's tasks.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskplus/core/api/api_client.dart';
import 'package:taskplus/core/auth/token_store.dart';
import 'package:taskplus/data/models.dart';
import 'package:taskplus/data/repository.dart';
import 'package:taskplus/demo/demo_backend.dart';

/// Stands in for Vercel's /api/state: one row with a version, as JSON (like Postgres would hold it).
class FakeStore implements DemoSync {
  int version = 0;
  String? json;
  @override
  Future<({int version, Map<String, dynamic>? data})> get() async => (version: version, data: json == null ? null : jsonDecode(json!) as Map<String, dynamic>);
  @override
  Future<({bool ok, int version, Map<String, dynamic>? data})> put(int v, Map<String, dynamic> data) async {
    if (v != version) return (ok: false, version: version, data: jsonDecode(json!) as Map<String, dynamic>);
    json = jsonEncode(data);
    version++;
    return (ok: true, version: version, data: null);
  }
  @override
  Future<void> reset() async { json = null; version = 0; }
}

Future<Repository> signIn(DemoApi api, String phone) async {
  final tokens = MemoryTokenStore();
  final client = ApiClient(baseUrl: 'https://demo.local', tokens: tokens, onSignedOut: () {}, adapter: api);
  final r = await client.dio.post('/auth/login', data: {'phone': phone, 'password': 'x'});
  await tokens.save(r.data['accessToken'] as String, r.data['refreshToken'] as String);
  return Repository(client, absolute: (s) => s);
}

void main() {
  test('a task sent in one browser shows up in another; both browsers keep working', () async {
    final store = FakeStore();
    final a = DemoApi(null, store), b = DemoApi(null, store);
    final riya = await signIn(a, '9800000002');
    final dhavalId = a.backend.users.firstWhere((u) => u['name'] == 'Dhaval Dalsania')['id'] as String;
    final th = await riya.openThread('user', dhavalId);
    final sent = await riya.send(Draft(clientMsgId: 'x1', threadId: th.id, kind: 'text', bodyText: 'Shared data check for Mehta Traders'));

    final dhaval = await signIn(b, '9800000005');
    final mine = await dhaval.cases(const CaseQuery(tab: 'my'));
    expect(mine.rows.map((r) => r.task.id), contains(sent.task!.id));
    await dhaval.accept(sent.task!.id);

    // Back in the first browser (after the 2 s refresh window): accepted by Dhaval.
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    expect((await riya.task(sent.task!.id)).task!.status, 'Accepted');
    // Both saved on top of each other, nothing lost.
    expect(store.version, greaterThanOrEqualTo(3));
  });
}
