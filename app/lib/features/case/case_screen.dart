import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/realtime.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../chat/attachments.dart';
import '../composer/composer.dart';
import '../ornate/bubble.dart';
import '../ornate/widgets.dart';
import '../task_card/task_actions.dart';

final _caseProvider = FutureProvider.autoDispose.family((ref, String id) => ref.watch(repositoryProvider).caseOf(id));
final _historyProvider = FutureProvider.autoDispose.family((ref, String id) => ref.watch(repositoryProvider).history(id));

/// Ornate's case page: status strip, then Activity, Details, Sub-Tasks, Files and Audit trail; the action card; the chat box.
class CaseScreen extends ConsumerStatefulWidget {
  const CaseScreen({super.key, required this.taskId});
  final String taskId;
  @override
  ConsumerState<CaseScreen> createState() => _CaseScreenState();
}

const _tabs = ['Activity', 'Details', 'Sub-Tasks', 'Files', 'Audit Trail'];

class _CaseScreenState extends ConsumerState<CaseScreen> {
  String _show = 'All';
  StreamSubscription? _events;

  void _reload() { ref.invalidate(_caseProvider(widget.taskId)); ref.invalidate(_historyProvider(widget.taskId)); }

  @override
  void initState() {
    super.initState();
    ref.listenManual(realtimeProvider, (_, next) {
      _events?.cancel();
      _events = next.value?.events.listen((_) => _reload());
    }, fireImmediately: true);
    ref.listenManual(sentItemsProvider, (_, _) => _reload());
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = context.o;
    final c = ref.watch(_caseProvider(widget.taskId));
    final h = ref.watch(_historyProvider(widget.taskId)).value;
    final me = ref.watch(authProvider).value?.id ?? '';
    final outbox = ref.watch(outboxProvider);
    return c.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(appBar: AppBar(), body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('$e', textAlign: TextAlign.center)))),
      data: (row) {
        final t = row.task;
        final subs = (h?['subTasks'] as List? ?? const []).cast<Map<String, dynamic>>();
        return DefaultTabController(
          length: _tabs.length,
          child: Scaffold(
            appBar: AppBar(
              titleSpacing: 0,
              title: Row(children: [
                OAvatar(row.party.name, size: 40, lock: row.party.isSelf),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: row.party.name, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600)),
                    TextSpan(text: ' · ${row.party.sub}', style: TextStyle(fontSize: 14, color: o.muted, fontWeight: FontWeight.w400)),
                  ]), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${t.ticketNo ?? ''} · ${t.subject ?? 'Reading the message…'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: o.muted)),
                ])),
              ]),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(96),
                child: Column(children: [
                  _Strip(row: row),
                  TabBar(isScrollable: true, tabAlignment: TabAlignment.start, labelColor: o.accentInk, unselectedLabelColor: o.muted, indicatorColor: o.accent,
                      tabs: [for (final x in _tabs) Tab(key: Key('tab-$x'), text: x == 'Sub-Tasks' && subs.isNotEmpty ? '$x (${subs.length})' : x)]),
                ]),
              ),
            ),
            body: Column(children: [
              Expanded(child: TabBarView(children: [
                Wall(child: _activity(row, h, me)),
                _Details(row: row),
                _SubTasks(history: h),
                _Files(history: h, item: row.item),
                _Audit(history: h),
              ])),
              if (!const ['Rejected', 'Cancelled', 'Transferred'].contains(t.status))
                Composer(
                  threadId: t.threadId, onSend: (d) => outbox.add(d), replyTo: t, replyOnly: true,
                  hint: t.isNote ? 'Add to your note' : t.actions.contains('hand_off') ? 'Message, / for sub-task' : 'Message about this task',
                  subtaskOf: t.actions.contains('hand_off') ? t : null,
                  onSubtask: (d, name) async {
                    try {
                      await ref.read(repositoryProvider).send(d);
                      _reload();
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sub-task sent to $name')));
                    } catch (e) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                    }
                  },
                ),
            ]),
          ),
        );
      },
    );
  }

  Widget _activity(CaseRow row, Map<String, dynamic>? h, String me) {
    final o = context.o;
    final names = {for (final p in ref.watch(peopleProvider).value ?? const <Member>[]) p.id: p.name};
    final replies = [for (final r in (h?['replies'] as List? ?? const [])) ChatItem.fromJson(r as Map<String, dynamic>)];
    final events = (h?['events'] as List? ?? const []).cast<Map<String, dynamic>>().where((e) => !const ['created', 'structured'].contains(e['type'])).toList();
    // Messages and update cards in one stream, by time (Ornate's Activity).
    final entries = <(DateTime, Widget, String)>[
      (row.item.message.createdAt, OBubble(message: row.item.message, out: row.item.message.senderId == me, name: names[row.item.message.senderId]), 'm'),
      for (final r in replies) (r.message.createdAt, OBubble(message: r.message, out: r.message.senderId == me, name: names[r.message.senderId]), r.message.attachments.isEmpty ? 'm' : 'f'),
      for (final e in events) (DateTime.parse(e['at'] as String), EventCard(e: e), 'u'),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final kept = entries.where((x) => _show == 'All' || (_show == 'Messages' && x.$3 != 'u') || (_show == 'Updates' && x.$3 == 'u') || (_show == 'Files' && x.$3 == 'f')).toList();
    final t = row.task;
    final list = <Widget>[
      Center(child: Wrap(spacing: 6, children: [
        for (final s in const ['All', 'Messages', 'Updates', 'Files']) OChip(s, key: Key('show-$s'), small: true, on: _show == s, onTap: () => setState(() => _show = s)),
      ])),
      for (var i = 0; i < kept.length; i++) ...[
        if (i == 0 || !sameDay(kept[i - 1].$1, kept[i].$1)) DateChip(kept[i].$1),
        kept[i].$2,
      ],
      if (t.status == 'Open' && !t.isNote) _card(context, Icons.hourglass_empty, o.orangeBg, o.orange, 'Waiting for someone to accept',
          rows: [if (t.dueAt != null) (t.dueAt!.isBefore(DateTime.now()) ? 'Accept overdue by' : 'Accept within', duration(t.dueAt!.difference(DateTime.now())))]),
      if (t.actions.isNotEmpty) _ActionCard(task: t, onDone: _reload),
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(12, 10, 12, 16), children: list);
  }
}

Widget _card(BuildContext context, IconData icon, Color bg, Color fg, String title, {String? by, String? text, List<(String, String)> rows = const []}) {
  final o = context.o;
  return Center(child: Container(
    margin: const EdgeInsets.symmetric(vertical: 6),
    constraints: const BoxConstraints(maxWidth: 520),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(color: o.inBubble, borderRadius: BorderRadius.circular(10), boxShadow: const [BoxShadow(color: Color(0x210B141A), blurRadius: 0.5, offset: Offset(0, 1))]),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 36, height: 36, decoration: BoxDecoration(color: bg, shape: BoxShape.circle), child: Icon(icon, size: 18, color: fg)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        if (by != null) Text(by, style: TextStyle(fontSize: 12.5, color: o.muted)),
        if (text != null && text.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(text)),
        for (final (k, v) in rows) Padding(padding: const EdgeInsets.only(top: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(k, style: TextStyle(fontSize: 13.5, color: o.muted))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 13.5))),
        ])),
      ])),
    ]),
  ));
}

/// One update in the Activity (Ornate's cards).
class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.e});
  final Map<String, dynamic> e;
  @override
  Widget build(BuildContext context) {
    final o = context.o;
    final p = (e['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
    final (title, icon, tone) = switch (e['type'] as String) {
      'accepted' => ('Accepted', Icons.check, 'green'), 'completed' => ('Completed', Icons.done_all, 'green'), 'verified' => ('Verified', Icons.verified, 'green'),
      'closed' => ('Closed', Icons.lock_outline, 'green'), 'reopened' => ('Reopened', Icons.replay, 'orange'), 'question' => ('Question for requester', Icons.help_outline, 'orange'),
      'answered' => ('Answered', Icons.reply, 'green'), 'blocked' => ('Blocked', Icons.block, 'red'), 'unblocked' => ('Unblocked', Icons.play_arrow, 'green'),
      'escalated' => ('Escalated', Icons.trending_up, 'red'), 'attended' => ('Escalation attended', Icons.how_to_reg, 'green'),
      'reassigned' => ('Reassigned', Icons.swap_horiz, 'neutral'), 'reassign_asked' => ('Reassignment requested', Icons.swap_horiz, 'orange'),
      'reassign_refused' => ('Stays with the owner', Icons.person, 'neutral'), 'declined' => ('Declined', Icons.close, 'orange'),
      'request' => (p['kind'] == 'reject' ? 'Rejection requested' : 'Transfer requested', Icons.outbox, 'orange'), 'request_refused' => ('Request refused', Icons.close, 'neutral'),
      'rejected' => ('Rejected', Icons.cancel_outlined, 'red'), 'transferred' => ('Transferred to ${p['toName'] ?? 'another department'}', Icons.east, 'neutral'),
      'cancelled' => ('Cancelled', Icons.cancel_outlined, 'red'), 'priority_changed' => ('Priority ${p['from']} → ${p['to']}', Icons.flag_outlined, 'neutral'),
      'edited' => ('Edited', Icons.edit_outlined, 'neutral'), 'warned' => ('Time warning', Icons.timer_outlined, 'orange'),
      'handed_off' => ('Handed off', Icons.call_split, 'orange'), 'subtask_done' => ('Sub-task finished', Icons.done, 'green'),
      'subs_cancelled' => ('Completed, open sub-tasks cancelled', Icons.done_all, 'green'), 'status_changed' => (statusLabel('${p['to']}'), Icons.play_arrow, 'green'),
      final x => (x, Icons.info_outline, 'neutral'),
    };
    final (bg, fg) = switch (tone) { 'green' => (o.greenBg, o.green), 'orange' => (o.orangeBg, o.orange), 'red' => (o.redBg, o.red), _ => (o.neutralBg, o.neutral) };
    final note = p['reason'] ?? p['remarks'] ?? p['question'] ?? p['resolution'] ?? p['subject'] ?? (p['to'] is String && e['type'] == 'edited' ? p['to'] : null);
    return _card(context, icon, bg, fg, title, by: 'by ${e['by']} · ${DateFormat.Hm().format(DateTime.parse(e['at'] as String).toLocal())}', text: note?.toString());
  }
}

class _Strip extends StatelessWidget {
  const _Strip({required this.row});
  final CaseRow row;
  @override
  Widget build(BuildContext context) {
    final o = context.o;
    final t = row.task, now = DateTime.now();
    final left = t.dueAt?.difference(now);
    final over = left != null && left.isNegative;
    final clock = t.isNote ? 'Private note · no time limit'
        : t.status == 'Open' ? (left == null ? '' : over ? 'Accept overdue by ${duration(left)}' : 'Accept within ${duration(left)}')
        : t.clockState == 'running' ? (over ? 'Clock running · overdue by ${duration(left)}' : left == null ? 'Clock running' : 'Clock running · ${duration(left)} left')
        : t.clockState == 'paused' ? 'Clock paused' : t.clockState == 'stopped' ? (t.status == 'Blocked' ? 'Clock stopped (blocked)' : 'Clock stopped') : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(color: o.bg, border: Border(bottom: BorderSide(color: o.line))),
      child: Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        StatusPill(t.status),
        if (clock.isNotEmpty) Text(clock, style: TextStyle(fontSize: 13, color: over ? o.danger : o.muted)),
        if (t.escalationLevel != null) Pill('Escalated to ${t.escalationLevel!.replaceAll('_', ' ')}', bg: o.redBg, fg: o.red),
        if (t.reassignRequestedBy != null) Pill('Reassignment requested', bg: o.orangeBg, fg: o.orange),
        if (t.requestKind != null) Pill('${t.requestKind == 'reject' ? 'Rejection' : 'Transfer'} awaiting lead', bg: o.orangeBg, fg: o.orange),
      ]),
    );
  }
}

/// "Choose an action": the main buttons stacked like WhatsApp reply buttons, the rest behind More.
class _ActionCard extends ConsumerWidget {
  const _ActionCard({required this.task, required this.onDone});
  final Task task;
  final VoidCallback onDone;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = context.o;
    final t = task;
    final primary = t.actions.where((a) => actionSpecs[a]?.primary ?? false).toList();
    final more = t.actions.where((a) => !primary.contains(a)).toList();
    Future<void> go(String a) async {
      if (a == 'hand_off') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Type /subtask in the chat box and pick a department.')));
        return;
      }
      try {
        final r = await runAction(context, ref, t, a);
        if (r == null) return;
        onDone();
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(doneText(a))));
      } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    Widget button(String label, VoidCallback on, {bool danger = false, Key? key}) => InkWell(
          key: key,
          onTap: on,
          child: Container(
            height: 44, alignment: Alignment.center,
            decoration: BoxDecoration(border: Border(top: BorderSide(color: o.muted.withValues(alpha: 0.3)))),
            child: Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: danger ? o.danger : o.brand)),
          ),
        );
    return Center(child: Container(
      key: const Key('action-card'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      constraints: const BoxConstraints(maxWidth: 520),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: o.inBubble, borderRadius: BorderRadius.circular(10), boxShadow: const [BoxShadow(color: Color(0x210B141A), blurRadius: 0.5, offset: Offset(0, 1))]),
      child: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: o.greenBg, shape: BoxShape.circle), child: Icon(Icons.bolt, size: 18, color: o.green)),
          const SizedBox(width: 12),
          const Text('Choose an action', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ])),
        for (final a in primary) button(actionSpecs[a]?.label ?? a, () => go(a), danger: actionSpecs[a]?.danger ?? false, key: Key('action-$a')),
        if (more.isNotEmpty) button(primary.isEmpty ? 'Actions' : 'More', key: const Key('more-actions'), () async {
          final a = await showModalBottomSheet<String>(context: context, builder: (s) => SafeArea(child: ListView(shrinkWrap: true, children: [
            ListTile(title: Text(primary.isEmpty ? 'Actions' : 'More actions', style: Theme.of(s).textTheme.titleMedium)),
            for (final a in more) ListTile(title: Text(actionSpecs[a]?.label ?? a, style: TextStyle(color: (actionSpecs[a]?.danger ?? false) ? o.danger : null)), onTap: () => Navigator.pop(s, a)),
          ])));
          if (a != null) await go(a);
        }),
      ]),
    ));
  }
}

class _Details extends ConsumerWidget {
  const _Details({required this.row});
  final CaseRow row;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = context.o;
    final t = row.task;
    final names = {for (final p in ref.watch(peopleProvider).value ?? const <Member>[]) p.id: p.name};
    final rows = <(String, String)>[
      ('Ticket', t.ticketNo ?? '–'), ('Type', t.isNote ? 'Private note' : 'Internal'), ('Status', statusLabel(t.status)),
      ('From', names[row.requesterId] ?? '–'),
      if (!t.isNote) ('To', row.party.sub),
      if (t.module != null) ('Module', t.module!),
      if (t.customerName != null) ('Customer', t.customerName!),
      if (t.customerPhone != null) ('Phone', t.customerPhone!),
      if (t.customerLocation != null) ('Location', t.customerLocation!),
      if (t.licenseNo != null) ('Licence', t.licenseNo!),
      if (!t.isNote) ('Priority', t.priority),
      if (!t.isNote) ('Owner', t.assigneeId == null ? 'Not accepted yet' : names[t.assigneeId] ?? '–'),
      if (t.createdAt != null) (t.closedAt != null ? 'Was open for' : 'Open for', duration((t.closedAt ?? DateTime.now()).difference(t.createdAt!))),
      if (t.resolution != null) ('Resolution', t.resolution!),
      if (t.customerInformed != null) ('Customer informed', t.customerInformed!),
      if (t.createdAt != null) ('Created', DateFormat('d MMM yyyy, HH:mm').format(t.createdAt!.toLocal())),
    ];
    return ListView(padding: const EdgeInsets.all(16), children: [
      for (final (k, v) in rows) Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 130, child: Text(k, style: TextStyle(fontSize: 13.5, color: o.muted))),
        Expanded(child: Text(v, style: const TextStyle(fontSize: 13.5))),
      ])),
      const SizedBox(height: 12),
      Text('DETAILS & REQUIRED ACTION', style: TextStyle(fontSize: 14, color: o.muted, letterSpacing: 0.5)),
      const SizedBox(height: 6),
      Text(t.details ?? row.item.message.bodyText ?? 'No details. The subject line is the request.'),
    ]);
  }
}

class _SubTasks extends StatelessWidget {
  const _SubTasks({required this.history});
  final Map<String, dynamic>? history;
  @override
  Widget build(BuildContext context) {
    final o = context.o;
    final parent = history?['parent'] as Map<String, dynamic>?;
    final subs = (history?['subTasks'] as List? ?? const []).cast<Map<String, dynamic>>();
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (parent != null) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.subdirectory_arrow_left),
          title: Text('Sub-task of ${parent['ticketNo']}'), subtitle: Text('${parent['subject'] ?? ''}'), onTap: () => context.push('/case/${parent['id']}')),
      if (parent == null && subs.isEmpty) Text('No sub-tasks. Type /subtask in the chat box to ask another department for part of the work.', style: TextStyle(color: o.muted)),
      for (final s in subs) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.call_split),
          title: Text('${s['ticketNo']} · ${s['department']}'), subtitle: Text('${s['subject'] ?? ''}'), trailing: StatusPill(s['status'] as String),
          onTap: () => context.push('/case/${s['id']}')),
    ]);
  }
}

class _Files extends StatelessWidget {
  const _Files({required this.history, required this.item});
  final Map<String, dynamic>? history;
  final ChatItem item;
  @override
  Widget build(BuildContext context) {
    final files = [for (final f in (history?['files'] as List? ?? const [])) Attachment.fromJson({...(f as Map<String, dynamic>), 'sizeBytes': f['sizeBytes']})];
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (files.isEmpty && item.message.kind != 'voice') Text('No files yet. Use the paperclip to attach one.', style: TextStyle(color: context.o.muted)),
      if (files.isNotEmpty) AttachmentStrip(attachments: files),
    ]);
  }
}

class _Audit extends StatelessWidget {
  const _Audit({required this.history});
  final Map<String, dynamic>? history;
  @override
  Widget build(BuildContext context) {
    final o = context.o;
    final events = (history?['events'] as List? ?? const []).cast<Map<String, dynamic>>();
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: events.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: o.line),
      itemBuilder: (_, i) {
        final e = events[i];
        final p = (e['payload'] as Map?)?.cast<String, dynamic>() ?? const {};
        final note = p['reason'] ?? p['remarks'] ?? p['question'] ?? p['resolution'];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 110, child: Text(DateFormat('d MMM, HH:mm').format(DateTime.parse(e['at'] as String).toLocal()), style: const TextStyle(fontSize: 13.5))),
            SizedBox(width: 100, child: Text('${e['by']}', style: const TextStyle(fontSize: 13.5))),
            Expanded(child: Text('${(e['type'] as String).replaceAll('_', ' ')}${note != null ? '\n$note' : ''}', style: const TextStyle(fontSize: 13.5))),
          ]),
        );
      },
    );
  }
}
