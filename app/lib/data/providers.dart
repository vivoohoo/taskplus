import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_controller.dart';
import 'models.dart';
import 'outbox.dart';
import 'repository.dart';

final repositoryProvider = Provider<Repository>((ref) => Repository(ref.watch(apiClientProvider)));

final outboxDbProvider = Provider<OutboxDb>((ref) {
  final db = OutboxDb();
  ref.onDispose(db.close);
  return db;
});

/// Confirmed sends, so open chats can swap the pending bubble for the server's version.
final sentItemsProvider = NotifierProvider<SentItems, ChatItem?>(SentItems.new);
class SentItems extends Notifier<ChatItem?> {
  @override
  ChatItem? build() => null;
  void add(ChatItem i) => state = i;
}

final outboxProvider = Provider<OutboxSender>((ref) {
  final s = OutboxSender(ref.watch(outboxDbProvider), ref.watch(repositoryProvider), onSent: (i) => ref.read(sentItemsProvider.notifier).add(i));
  s.flush();
  ref.onDispose(s.dispose);
  return s;
});

final threadsProvider = FutureProvider<List<ThreadSummary>>((ref) => ref.watch(repositoryProvider).threads());
final countsProvider = FutureProvider<({int myPending, int overdue})>((ref) => ref.watch(repositoryProvider).counts());

final departmentProvider = FutureProvider.family<DepartmentInfo, String>((ref, id) => ref.watch(repositoryProvider).department(id));
