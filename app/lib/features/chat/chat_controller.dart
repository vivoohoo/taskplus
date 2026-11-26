import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/realtime.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

class ChatState {
  const ChatState({this.items = const [], this.nextCursor, this.loading = true, this.loadingMore = false, this.error});
  /// Oldest first.
  final List<ChatItem> items;
  final String? nextCursor;
  final bool loading, loadingMore;
  final String? error;
  ChatState copy({List<ChatItem>? items, String? nextCursor, bool clearCursor = false, bool? loading, bool? loadingMore, String? error}) => ChatState(
      items: items ?? this.items, nextCursor: clearCursor ? null : nextCursor ?? this.nextCursor,
      loading: loading ?? this.loading, loadingMore: loadingMore ?? this.loadingMore, error: error);
}

/// Merge rules shared by history, live events and confirmed sends. Pure, so they are easy to test.
class ChatMerge {
  static List<ChatItem> upsert(List<ChatItem> items, ChatItem incoming) {
    final i = items.indexWhere((x) => x.message.id == incoming.message.id);
    if (i < 0) return [...items, incoming]..sort((a, b) => a.message.createdAt.compareTo(b.message.createdAt));
    final cur = items[i];
    final task = incoming.task == null ? cur.task : Task.newest(cur.task, incoming.task!);
    return [...items]..[i] = ChatItem(message: incoming.message.transcript == null ? cur.message : incoming.message, task: task);
  }

  static List<ChatItem> task(List<ChatItem> items, Task t) => [
        for (final x in items) x.message.id == t.messageId ? ChatItem(message: x.message, task: Task.newest(x.task, t)) : x,
      ];

  static List<ChatItem> transcript(List<ChatItem> items, String messageId, String text) => [
        for (final x in items) x.message.id == messageId ? ChatItem(message: x.message.copyWith(transcript: text), task: x.task) : x,
      ];
}

final chatProvider = NotifierProvider.autoDispose.family<ChatController, ChatState, String>(ChatController.new);

class ChatController extends Notifier<ChatState> {
  ChatController(this.threadId);
  final String threadId;
  StreamSubscription<RealtimeEvent>? _sub;

  @override
  ChatState build() {
    final rt = ref.watch(realtimeProvider).value;
    if (rt != null) {
      rt.join(threadId);
      _sub = rt.events.listen(_onEvent);
      ref.onDispose(() { _sub?.cancel(); rt.leave(threadId); });
    }
    ref.listen(sentItemsProvider, (_, item) { if (item != null && item.message.threadId == threadId) state = state.copy(items: ChatMerge.upsert(state.items, item)); });
    Future.microtask(_loadFirst);
    return const ChatState();
  }

  Future<void> _loadFirst() async {
    try {
      final page = await ref.read(repositoryProvider).messages(threadId);
      state = state.copy(items: page.items, nextCursor: page.nextCursor, clearCursor: page.nextCursor == null, loading: false);
    } catch (e) {
      state = state.copy(loading: false, error: '$e');
    }
  }

  Future<void> loadMore() async {
    if (state.nextCursor == null || state.loadingMore) return;
    state = state.copy(loadingMore: true);
    try {
      final page = await ref.read(repositoryProvider).messages(threadId, before: state.nextCursor);
      state = state.copy(items: [...page.items, ...state.items], nextCursor: page.nextCursor, clearCursor: page.nextCursor == null, loadingMore: false);
    } catch (e) {
      state = state.copy(loadingMore: false, error: '$e');
    }
  }

  void _onEvent(RealtimeEvent e) {
    final d = e.data;
    switch (e.name) {
      case 'message.created':
        final item = ChatItem.fromJson(d);
        if (item.message.threadId == threadId) state = state.copy(items: ChatMerge.upsert(state.items, item));
      case 'task.transcribed':
        state = state.copy(items: ChatMerge.transcript(state.items, d['messageId'] as String, d['transcript'] as String));
      case 'task.structured' || 'task.updated':
        final t = Task.fromJson(d['task'] as Map<String, dynamic>);
        if (t.threadId == threadId) state = state.copy(items: ChatMerge.task(state.items, t));
    }
  }

  /// After an accept/reassign/status call: show the answer at once (the live event will agree).
  void applyTask(Task t) => state = state.copy(items: ChatMerge.task(state.items, t));
}
