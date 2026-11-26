import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../chat/attachments.dart';
import '../chat/voice_player.dart';
import 'task_card.dart';

/// Ornate's ticket page, as a sheet: Details, History (audit trail) and Files.
void showTaskDetails(BuildContext context, ChatItem item) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(heightFactor: 0.85, child: _Details(item: item)),
    );

final _historyProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) => ref.watch(repositoryProvider).history(id));

const _eventLabels = {
  'created': 'Sent', 'structured': 'Read by AI', 'accepted': 'Accepted', 'reassigned': 'Reassigned', 'status_changed': 'Status changed',
  'completed': 'Completed', 'verified': 'Verified', 'closed': 'Closed', 'reopened': 'Reopened', 'question': 'Question to requester',
  'answered': 'Requester answered', 'blocked': 'Blocked', 'unblocked': 'Unblocked', 'declined': 'Declined', 'reassign_asked': 'Asked to be reassigned',
  'reassign_refused': 'Kept with the assignee', 'request': 'Asked to reject or transfer', 'request_refused': 'Request refused', 'rejected': 'Rejected',
  'transferred': 'Transferred', 'escalated': 'Escalated', 'attended': 'Escalation attended', 'priority_changed': 'Priority changed',
  'cancelled': 'Cancelled', 'warned': 'Time warning', 'edited': 'Edited', 'assigned': 'Assigned',
};

class _Details extends ConsumerWidget {
  const _Details({required this.item});
  final ChatItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = item.task!;
    final theme = Theme.of(context);
    String hrs(int ms) => '${(ms / 3600000).toStringAsFixed(1)} working h';
    final facts = <(String, String)>[
      ('Ticket', t.ticketNo ?? '–'),
      ('Status', statusLabel(t.status)),
      ('Priority', t.priority),
      if (t.module != null) ('Module', t.module!),
      if (t.dueAt != null) ('Due', DateFormat('d MMM, HH:mm').format(t.dueAt!.toLocal())),
      ('Time used', hrs(t.usedMs)),
      if (t.escalationLevel != null) ('Escalated to', t.escalationLevel!.replaceAll('_', ' ')),
      if (t.resolution != null) ('Resolution', t.resolution!),
      if (t.customerInformed != null) ('Customer informed', t.customerInformed!),
    ];
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(t.subject ?? item.message.bodyText ?? 'Task', style: theme.textTheme.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        const TabBar(tabs: [Tab(text: 'Details'), Tab(text: 'History'), Tab(text: 'Files')]),
        Expanded(child: TabBarView(children: [
          ListView(padding: const EdgeInsets.all(16), children: [
            for (final (k, v) in facts)
              Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 130, child: Text(k, style: theme.textTheme.bodySmall)),
                Expanded(child: Text(v)),
              ])),
            if (t.details != null) ...[const Divider(), Text(t.details!)],
          ]),
          ref.watch(_historyProvider(t.id)).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (h) => ListView(padding: const EdgeInsets.all(16), children: [
              for (final e in (h['events'] as List).cast<Map<String, dynamic>>())
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(_eventLabels[e['type']] ?? '${e['type']}'),
                  subtitle: Text('${e['by']} · ${DateFormat('d MMM, HH:mm').format(DateTime.parse(e['at'] as String).toLocal())}'
                      '${_note(e['payload'] as Map<String, dynamic>)}'),
                ),
            ]),
          ),
          ListView(padding: const EdgeInsets.all(16), children: [
            if (item.message.kind == 'voice') VoicePlayer(audioKey: item.message.audioKey!, durationS: item.message.audioDurationS ?? 0, transcript: item.message.transcript),
            if (item.message.attachments.isNotEmpty) AttachmentStrip(attachments: item.message.attachments),
            if (item.message.kind != 'voice' && item.message.attachments.isEmpty) const Text('No files on this task.'),
          ]),
        ])),
      ]),
    );
  }

  static String _note(Map<String, dynamic> p) {
    final n = p['reason'] ?? p['remarks'] ?? p['question'] ?? p['resolution'] ?? (p['to'] is String ? p['to'] : null);
    return n == null ? '' : '\n$n';
  }
}
