import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/realtime.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/outbox.dart';
import '../../data/providers.dart';
import '../composer/composer.dart';
import '../ornate/bubble.dart';
import '../ornate/widgets.dart';
import '../task_card/task_card.dart';

/// Key: `party` or `party|tab` (opened from a tab: that tab's open tasks, as the row counted them).
final timelineProvider = FutureProvider.autoDispose.family((ref, String key) {
  final [party, ...tab] = key.split('|');
  return ref.watch(repositoryProvider).timeline(party, tab: tab.firstOrNull);
});
final _threadProvider = FutureProvider.autoDispose.family((ref, String party) => ref.watch(repositoryProvider).threadFor(party));

/// One person's chat (Ornate + Task Plus): every task between you as a timeline of cards, the summary line,
/// All / Not accepted / Accepted, and the chat box to send them a new task.
class PersonScreen extends ConsumerStatefulWidget {
  const PersonScreen({super.key, required this.partyKey, this.party, this.tab});
  final String partyKey;
  final String? tab;
  final Party? party;
  @override
  ConsumerState<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends ConsumerState<PersonScreen> {
  String _filter = 'All';
  String get _key => widget.tab == null ? widget.partyKey : '${widget.partyKey}|${widget.tab}';
  StreamSubscription? _events;

  @override
  void initState() {
    super.initState();
    ref.listenManual(realtimeProvider, (_, next) {
      _events?.cancel();
      _events = next.value?.events.listen((_) => ref.invalidate(timelineProvider(_key)));
    }, fireImmediately: true);
    ref.listenManual(sentItemsProvider, (_, _) => ref.invalidate(timelineProvider(_key)));
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = context.o;
    final me = ref.watch(authProvider).value?.id ?? '';
    final tl = ref.watch(timelineProvider(_key));
    final thread = ref.watch(_threadProvider(widget.partyKey)).value;
    final outbox = ref.watch(outboxProvider);
    final names = {for (final p in ref.watch(peopleProvider).value ?? const <Member>[]) p.id: p.name};
    final party = tl.value?.party ?? widget.party ?? Party(key: widget.partyKey, name: widget.partyKey == 'self' ? 'Private notes' : 'Chat');
    final items = tl.value?.items ?? const <ChatItem>[];
    final tasks = {for (final i in items) if (i.task != null) i.task!.id: i.task!};
    final senders = {for (final i in items) if (i.task != null) i.task!.id: i.message.senderId};
    final open = tasks.values.where((t) => !const ['Closed', 'Rejected', 'Cancelled', 'Transferred'].contains(t.status)).toList();
    final waiting = open.where((t) => t.status == 'Open').length;
    bool keep(Task t) => _filter == 'All' || (_filter == 'Not accepted') == (t.status == 'Open');
    bool show(ChatItem i) { final t = i.task ?? tasks[i.message.replyToTaskId]; return t == null || keep(t); }
    final shown = items.where(show).toList();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          OAvatar(party.name, size: 40, lock: party.isSelf),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: party.name, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600)),
              if (party.sub.isNotEmpty) TextSpan(text: ' · ${party.sub}', style: TextStyle(fontSize: 14, color: o.muted, fontWeight: FontWeight.w400)),
            ]), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (open.isNotEmpty) Text(summaryOfTasks(open, me, senders), key: const Key('summary'), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: open.any((t) => t.isOverdue(DateTime.now())) ? o.danger : o.muted)),
          ])),
        ]),
      ),
      body: Column(children: [
        if (!party.isSelf && tasks.isNotEmpty)
          Container(
            color: o.bg,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(children: [
              for (final (k, n) in [('All', open.length), ('Not accepted', waiting), ('Accepted', open.length - waiting)]) ...[
                OChip('$k ($n)', key: Key('filter-$k'), on: _filter == k, onTap: () => setState(() => _filter = k), small: true),
                const SizedBox(width: 8),
              ],
            ]),
          ),
        Expanded(
          child: Wall(
            child: tl.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (_) => StreamBuilder<List<OutboxRow>>(
                stream: thread == null ? const Stream.empty() : outbox.watch(thread.id),
                builder: (context, snap) {
                  final known = items.map((i) => i.message.clientMsgId).toSet();
                  final pending = (snap.data ?? const []).where((r) => !known.contains(r.clientMsgId.toLowerCase())).toList();
                  final entries = <Widget>[];
                  for (var i = 0; i < shown.length; i++) {
                    final it = shown[i];
                    if (i == 0 || !sameDay(shown[i - 1].message.createdAt, it.message.createdAt)) entries.add(DateChip(it.message.createdAt));
                    entries.add(_entry(it, me, names, tasks));
                  }
                  if (_filter != 'All' && shown.isEmpty) {
                    entries.add(Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(_filter == 'Not accepted' ? 'Everything has been accepted.' : 'Nothing accepted yet.', style: TextStyle(color: o.muted)))));
                  }
                  for (final r in pending) { entries.add(PendingBubble(row: r, outbox: outbox)); }
                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    itemCount: entries.length,
                    itemBuilder: (_, i) => entries[entries.length - 1 - i],
                  );
                },
              ),
            ),
          ),
        ),
        if (thread != null)
          Composer(threadId: thread.id, departmentId: thread.isDepartment ? thread.departmentId : null, onSend: (d) => outbox.add(d),
              hint: party.isSelf ? 'Private note, only you see it' : null)
        else
          const LinearProgressIndicator(),
      ]),
    );
  }

  Widget _entry(ChatItem i, String me, Map<String, String> names, Map<String, Task> tasks) {
    final out = i.message.senderId == me;
    final about = i.message.replyToTaskId == null ? null : (tasks[i.message.replyToTaskId]?.ticketNo ?? 'a task');
    final bubble = OBubble(message: i.message, out: out, name: names[i.message.senderId], about: about);
    if (i.task == null) {
      return GestureDetector(onTap: () => context.push('/case/${i.message.replyToTaskId}'), child: bubble);
    }
    return Column(crossAxisAlignment: out ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
      bubble,
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: TaskCard(item: i, directRecipient: !out, onTask: (_) => ref.invalidate(timelineProvider(_key))),
      ),
    ]);
  }
}
