import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../data/models.dart';
import '../../data/outbox.dart';
import '../../data/providers.dart';
import '../composer/composer.dart';
import '../ornate/widgets.dart' show SenderStatement;
import '../task_card/task_card.dart';
import 'attachments.dart';
import 'chat_controller.dart';
import 'voice_player.dart';

/// One timeline: what I sent on the right (only my own words), what I received on the left as task cards.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.threadId, this.thread});
  final String threadId;
  final ThreadSummary? thread;
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scroll = ScrollController();
  Task? _replyTo;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      // reverse list: the end of the scroll is the top, i.e. older messages
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) ref.read(chatProvider(widget.threadId).notifier).loadMore();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authProvider).value;
    final chat = ref.watch(chatProvider(widget.threadId));
    final outbox = ref.watch(outboxProvider);
    // Opened from a notification: no summary was passed in, so take it from the chat list.
    final thread = widget.thread ?? ref.watch(threadsProvider).value?.where((t) => t.id == widget.threadId).firstOrNull;
    // In a department chat I started, I'm the sender; for everyone else in it, the department is.
    final deptForComposer = thread != null && thread.isDepartment ? thread.departmentId : null;

    return Scaffold(
      appBar: AppBar(title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(thread?.title ?? 'Chat', overflow: TextOverflow.ellipsis),
        if (thread?.subtitle != null) Text(thread!.subtitle!, style: Theme.of(context).textTheme.bodySmall),
      ])),
      body: Column(children: [
        Expanded(
          child: StreamBuilder<List<OutboxRow>>(
            stream: outbox.watch(widget.threadId),
            builder: (context, snap) {
              final known = chat.items.map((i) => i.message.clientMsgId).toSet();
              final pending = (snap.data ?? const []).where((r) => !known.contains(r.clientMsgId.toLowerCase())).toList();
              if (chat.loading) return const Center(child: CircularProgressIndicator());
              final entries = <Widget>[
                for (final i in chat.items) _entry(i, me),
                for (final r in pending) _PendingBubble(row: r, outbox: outbox),
              ];
              return ListView.builder(
                controller: _scroll,
                reverse: true,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                itemCount: entries.length + (chat.loadingMore ? 1 : 0),
                itemBuilder: (_, i) => i == entries.length ? const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator())) : entries[entries.length - 1 - i],
              );
            },
          ),
        ),
        if (chat.error != null) Padding(padding: const EdgeInsets.all(8), child: Text(chat.error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        Composer(threadId: widget.threadId, departmentId: deptForComposer, onSend: (d) => outbox.add(d),
            replyTo: _replyTo, onCancelReply: () => setState(() => _replyTo = null)),
      ]),
    );
  }

  Widget _entry(ChatItem i, AppUser? me) {
    // D5: my own message, with the card the AI made from it underneath.
    final replyTo = i.message.replyToTaskId == null ? null
        : ref.read(chatProvider(widget.threadId)).items.where((x) => x.task?.id == i.message.replyToTaskId).firstOrNull?.task?.subject ?? 'a task';
    if (me != null && i.message.senderId == me.id) {
      return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        SentBubble(item: i, replyTo: replyTo),
        if (i.task != null && !i.task!.isNote) SenderStatement(task: i.task!, onTap: () => setState(() => _replyTo = i.task), onChanged: ref.read(chatProvider(widget.threadId).notifier).applyTask),
        if (i.task != null && i.task!.isNote) Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: TaskCard(item: i, onTask: ref.read(chatProvider(widget.threadId).notifier).applyTask),
          ),
        ),
      ]);
    }
    if (i.task == null) return SentBubble(item: i, received: true, replyTo: replyTo);
    final thread = widget.thread ?? ref.read(threadsProvider).value?.where((t) => t.id == widget.threadId).firstOrNull;
    final directRecipient = thread?.isDepartment != true;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: TaskCard(item: i, directRecipient: directRecipient, onTask: ref.read(chatProvider(widget.threadId).notifier).applyTask),
      ),
    );
  }
}

/// My own message: right-aligned, primary colour, with a small status label.
class SentBubble extends StatelessWidget {
  const SentBubble({super.key, required this.item, this.received = false, this.replyTo});
  final ChatItem item;
  final bool received;
  /// Subject of the task this message answers.
  final String? replyTo;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final m = item.message;
    final status = m.replyToTaskId != null ? 'Reply' : statusLabel(item.task?.status ?? 'Open');
    return Align(
      alignment: received ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: Container(
          key: Key('sent-${m.clientMsgId}'),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(color: received ? c.surfaceContainerHigh : c.primaryContainer, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (replyTo != null) Align(alignment: Alignment.centerLeft, child: Text('↪ Re: $replyTo', style: Theme.of(context).textTheme.labelSmall)),
            if (m.bodyText != null) Align(alignment: Alignment.centerLeft, child: Text(m.bodyText!)),
            if (m.kind == 'voice') VoicePlayer(audioKey: m.audioKey!, durationS: m.audioDurationS ?? 0, transcript: m.transcript),
            if (m.attachments.isNotEmpty) AttachmentStrip(attachments: m.attachments),
            const SizedBox(height: 2),
            Text('${DateFormat.Hm().format(m.createdAt.toLocal())} · $status', style: Theme.of(context).textTheme.labelSmall),
          ]),
        ),
      ),
    );
  }
}

/// Still in the outbox: shown at once with a clock (or a retry button if the server refused it).
class _PendingBubble extends StatelessWidget {
  const _PendingBubble({required this.row, required this.outbox});
  final OutboxRow row;
  final OutboxSender outbox;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final failed = row.status == 'failed';
    final files = (jsonDecode(row.attachmentPaths) as List).length;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        key: Key('pending-${row.clientMsgId}'),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        decoration: BoxDecoration(color: c.primaryContainer.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (row.bodyText != null) Align(alignment: Alignment.centerLeft, child: Text(row.bodyText!)),
          if (row.audioPath != null) VoicePlayer(audioKey: '', durationS: row.audioDurationS ?? 0, localPath: row.audioPath),
          if (files > 0) Text('$files file${files > 1 ? 's' : ''}'),
          if (failed) ...[
            Text(row.error ?? 'Not sent', style: TextStyle(color: c.error)),
            Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton(onPressed: () => outbox.discard(row.clientMsgId), child: const Text('Delete')),
              TextButton(onPressed: () => outbox.retryFailed(row.clientMsgId), child: const Text('Retry')),
            ]),
          ] else
            const Icon(Icons.schedule, size: 14, semanticLabel: 'Sending'),
        ]),
      ),
    );
  }
}
