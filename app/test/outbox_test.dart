import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskplus/core/api/api_client.dart';
import 'package:taskplus/core/auth/token_store.dart';
import 'package:taskplus/data/models.dart';
import 'package:taskplus/data/outbox.dart';
import 'package:taskplus/data/repository.dart';

import 'helpers/fixtures.dart';

/// Answers send() from a script: throw an ApiException, or return the server's copy.
class ScriptedRepo extends Repository {
  ScriptedRepo() : super(ApiClient(baseUrl: 'http://x', tokens: MemoryTokenStore(), onSignedOut: () {}));
  final script = <Object>[];
  final sent = <String>[];
  @override
  Future<ChatItem> send(Draft d, {String? audioKey, List<String> attachmentKeys = const []}) async {
    final next = script.isEmpty ? 'ok' : script.removeAt(0);
    if (next is ApiException) throw next;
    sent.add(d.clientMsgId);
    return ChatItem(message: message(), task: task(ai: 'pending'));
  }
}

void main() {
  late OutboxDb db;
  late ScriptedRepo repo;
  setUp(() { db = OutboxDb(NativeDatabase.memory()); repo = ScriptedRepo(); });
  tearDown(() => db.close());

  Draft draft(String id) => Draft(clientMsgId: id, threadId: 'T1', kind: 'text', bodyText: 'hello $id');

  test('offline: keeps the message, retries, and sends it exactly once', () async {
    repo.script.addAll([ApiException(null, 'NETWORK', 'offline'), ApiException(null, 'NETWORK', 'offline')]);
    final confirmed = <ChatItem>[];
    final o = OutboxSender(db, repo, onSent: confirmed.add, unitMs: 1);
    await o.add(draft('a'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    for (var i = 0; i < 20 && repo.sent.isEmpty; i++) { await Future<void>.delayed(const Duration(milliseconds: 20)); }
    expect(repo.sent, ['a']);
    expect(confirmed, hasLength(1));
    expect(await db.select(db.outboxRows).get(), isEmpty);
    await o.flush();
    expect(repo.sent, ['a']); // not sent again
    o.dispose();
  });

  test('keeps order: a later message waits for the earlier one', () async {
    repo.script.add(ApiException(null, 'NETWORK', 'offline'));
    final o = OutboxSender(db, repo, unitMs: 1);
    await o.add(draft('first'));
    await o.add(draft('second'));
    for (var i = 0; i < 30 && repo.sent.length < 2; i++) { await Future<void>.delayed(const Duration(milliseconds: 20)); }
    expect(repo.sent, ['first', 'second']);
    o.dispose();
  });

  test('a refused message is marked failed and can be retried', () async {
    repo.script.add(ApiException(400, 'BAD_REQUEST', 'Type a message.'));
    final o = OutboxSender(db, repo, unitMs: 1);
    await o.add(draft('bad'));
    var row = (await db.select(db.outboxRows).get()).single;
    for (var i = 0; i < 20 && row.status != 'failed'; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      row = (await db.select(db.outboxRows).get()).single;
    }
    expect(row.status, 'failed');
    expect(row.error, 'Type a message.');
    await o.retryFailed('bad');
    for (var i = 0; i < 20 && repo.sent.isEmpty; i++) { await Future<void>.delayed(const Duration(milliseconds: 20)); }
    expect(repo.sent, ['bad']);
    o.dispose();
  });
}
