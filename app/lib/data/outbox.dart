import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../core/api/api_client.dart';
import 'models.dart';
import 'repository.dart';

part 'outbox.g.dart';

/// Messages waiting to reach the server. Written before anything is sent, so nothing is lost offline.
class OutboxRows extends Table {
  TextColumn get clientMsgId => text()();
  TextColumn get threadId => text()();
  TextColumn get kind => text()();
  TextColumn get bodyText => text().nullable()();
  TextColumn get audioPath => text().nullable()();
  IntColumn get audioDurationS => integer().nullable()();
  TextColumn get attachmentPaths => text().withDefault(const Constant('[]'))();
  TextColumn get overrides => text().withDefault(const Constant('{}'))();
  TextColumn get taggedUserId => text().nullable()();
  /// Storage keys of files already uploaded, so a retry doesn't upload again.
  TextColumn get audioKey => text().nullable()();
  TextColumn get attachmentKeys => text().withDefault(const Constant('[]'))();
  /// queued | failed (the server refused it; shown with a retry option)
  TextColumn get status => text().withDefault(const Constant('queued'))();
  TextColumn get error => text().nullable()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {clientMsgId};
}

@DriftDatabase(tables: [OutboxRows])
class OutboxDb extends _$OutboxDb {
  OutboxDb([QueryExecutor? e]) : super(e ?? driftDatabase(name: 'taskplus_outbox'));
  @override
  int get schemaVersion => 1;
}

extension on OutboxRow {
  Draft toDraft() => Draft(
        clientMsgId: clientMsgId, threadId: threadId, kind: kind, bodyText: bodyText, audioPath: audioPath,
        audioDurationS: audioDurationS, taggedUserId: taggedUserId,
        attachmentPaths: (jsonDecode(attachmentPaths) as List).cast<String>(),
        overrides: (jsonDecode(overrides) as Map).cast<String, String>(),
      );
}

const _mimeByExt = {'ogg': 'audio/ogg', 'opus': 'audio/ogg', 'm4a': 'audio/mp4', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'pdf': 'application/pdf'};
String mimeOf(String path) => _mimeByExt[path.split('.').last.toLowerCase()] ?? 'application/octet-stream';

/// Sends outbox rows in order. Network trouble: wait (2 s, 4 s ... 60 s) and try again. Server refusal: mark failed.
class OutboxSender {
  OutboxSender(this.db, this.repo, {this.onSent, this.unitMs = 1000});
  final OutboxDb db;
  final Repository repo;
  final void Function(ChatItem item)? onSent;
  final int unitMs;
  bool _running = false;
  Timer? _retry;

  Future<void> add(Draft d) async {
    await db.into(db.outboxRows).insert(OutboxRowsCompanion.insert(
      clientMsgId: d.clientMsgId, threadId: d.threadId, kind: d.kind, bodyText: Value(d.bodyText), audioPath: Value(d.audioPath),
      audioDurationS: Value(d.audioDurationS), attachmentPaths: Value(jsonEncode(d.attachmentPaths)),
      overrides: Value(jsonEncode(d.overrides)), taggedUserId: Value(d.taggedUserId), createdAt: DateTime.now(),
    ));
    unawaited(flush());
  }

  /// What is still waiting for one thread, oldest first (shown with a clock icon).
  Stream<List<OutboxRow>> watch(String threadId) =>
      (db.select(db.outboxRows)..where((r) => r.threadId.equals(threadId))..orderBy([(r) => OrderingTerm(expression: r.createdAt)])).watch();

  Future<void> retryFailed(String clientMsgId) async {
    await (db.update(db.outboxRows)..where((r) => r.clientMsgId.equals(clientMsgId))).write(const OutboxRowsCompanion(status: Value('queued'), error: Value(null)));
    unawaited(flush());
  }

  Future<void> discard(String clientMsgId) => (db.delete(db.outboxRows)..where((r) => r.clientMsgId.equals(clientMsgId))).go();

  /// Called on start-up, after reconnecting, and after each add.
  Future<void> flush() async {
    if (_running) return;
    _running = true;
    _retry?.cancel();
    try {
      final rows = await (db.select(db.outboxRows)..where((r) => r.status.equals('queued'))..orderBy([(r) => OrderingTerm(expression: r.createdAt)])).get();
      for (final row in rows) {
        try {
          await _sendOne(row);
        } on ApiException catch (e) {
          if (e.code == 'NETWORK' || e.code == 'RATE_LIMITED' || (e.status ?? 0) >= 500) {
            final attempts = row.attempts + 1;
            await (db.update(db.outboxRows)..where((r) => r.clientMsgId.equals(row.clientMsgId))).write(OutboxRowsCompanion(attempts: Value(attempts)));
            _retry = Timer(Duration(milliseconds: min(60, 1 << attempts) * unitMs), () => unawaited(flush()));
            return; // keep order: later messages wait for this one
          }
          await (db.update(db.outboxRows)..where((r) => r.clientMsgId.equals(row.clientMsgId)))
              .write(OutboxRowsCompanion(status: const Value('failed'), error: Value(e.message)));
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _sendOne(OutboxRow row) async {
    final d = row.toDraft();
    var audioKey = row.audioKey;
    if (d.audioPath != null && audioKey == null) {
      audioKey = await repo.upload(d.threadId, File(d.audioPath!), mimeOf(d.audioPath!), 'audio');
      await (db.update(db.outboxRows)..where((r) => r.clientMsgId.equals(row.clientMsgId))).write(OutboxRowsCompanion(audioKey: Value(audioKey)));
    }
    final keys = (jsonDecode(row.attachmentKeys) as List).cast<String>();
    for (var i = keys.length; i < d.attachmentPaths.length; i++) {
      final p = d.attachmentPaths[i];
      keys.add(await repo.upload(d.threadId, File(p), mimeOf(p), 'attachment'));
      await (db.update(db.outboxRows)..where((r) => r.clientMsgId.equals(row.clientMsgId))).write(OutboxRowsCompanion(attachmentKeys: Value(jsonEncode(keys))));
    }
    final item = await repo.send(d, audioKey: audioKey, attachmentKeys: keys);
    await discard(row.clientMsgId);
    onSent?.call(item);
  }

  void dispose() => _retry?.cancel();
}
