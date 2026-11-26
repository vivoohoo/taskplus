import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../chat/attachments.dart';
import '../chat/voice_player.dart';
import 'task_actions.dart';
import 'task_details.dart';

/// Status names as people read them.
String statusLabel(String s) => switch (s) {
      'InProgress' => 'In progress',
      'WaitingInfo' => 'Waiting for information',
      'Blocked' => 'Blocked',
      'Completed' => 'Completed – to verify',
      _ => s,
    };

const priorityColors = {'Critical': Color(0xFF8E0000), 'High': Color(0xFFD93025), 'Medium': Color(0xFFE37400), 'Low': Color(0xFF5F6368)};

class TaskCard extends ConsumerWidget {
  const TaskCard({super.key, required this.item, this.directRecipient = false, this.onTask, this.onAnswer, this.now});
  final ChatItem item;
  /// The requester answers a question: the chat puts the composer into reply mode for this task.
  final void Function(Task)? onAnswer;
  /// In a direct chat, whether the viewer is the one it was sent to.
  final bool directRecipient;
  final void Function(Task)? onTask;
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = item.task!;
    final m = item.message;
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final pending = t.aiStatus == 'pending';
    final primary = t.actions.where((a) => actionSpecs[a]?.primary ?? false).toList();
    final more = t.actions.where((a) => !(actionSpecs[a]?.primary ?? false)).toList();
    // Show at most three buttons on the card; the rest open from More (as decided for Ornate).
    final shown = [...primary, ...more].take(primary.isEmpty ? 2 : primary.length.clamp(1, 3)).toList();
    final rest = t.actions.where((a) => !shown.contains(a)).toList();
    final canAnswer = t.status == 'WaitingInfo' && onAnswer != null && !t.actions.contains('ask_requester') && t.assigneeId != null;
    final overdue = t.isOverdue(now ?? DateTime.now());

    Widget field(String label, String? value, String warnKey, {VoidCallback? onTap}) => value == null || value.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 2),
            child: InkWell(
              onTap: onTap,
              child: Row(children: [
                SizedBox(width: 72, child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant))),
                Expanded(child: Text(value, style: onTap == null ? null : TextStyle(color: c.primary))),
                if (t.hasWarning(warnKey)) Tooltip(message: 'Check this value', child: Icon(Icons.warning_amber, size: 16, color: c.error)),
              ]),
            ),
          );

    return Card(
      key: Key('task-${t.id}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: c.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _Badge(t.priority, priorityColors[t.priority] ?? c.outline),
            if (t.module != null) Text(t.module!, style: theme.textTheme.labelMedium?.copyWith(color: c.onSurfaceVariant)),
            if (t.aiStatus == 'needs_review') _Badge('Needs review', const Color(0xFFE37400)),
            if (overdue) _Badge('Overdue', c.error),
            if (t.escalationLevel != null) _Badge('Escalated', c.error),
            if (t.reassignRequestedBy != null) _Badge('Reassignment requested', const Color(0xFFE37400)),
            if (t.requestKind != null) _Badge(t.requestKind == 'reject' ? 'Asked to reject' : 'Asked to transfer', const Color(0xFFE37400)),
            if (t.status != 'Open') Text(statusLabel(t.status), style: theme.textTheme.labelMedium),
          ]),
          const SizedBox(height: 6),
          if (pending) ...[
            const _Shimmer(),
            const SizedBox(height: 6),
            Text(m.kind == 'voice' && m.transcript == null ? 'Transcribing…' : 'Structuring…', style: theme.textTheme.labelMedium),
          ] else if (t.subject != null)
            InkWell(
              key: Key('open-details-${t.id}'),
              onTap: () => showTaskDetails(context, item),
              child: Text(t.subject!, style: theme.textTheme.titleMedium),
            ),
          if (t.ticketNo != null) Text(t.ticketNo!, style: theme.textTheme.labelSmall?.copyWith(color: c.onSurfaceVariant)),
          field('Customer', t.customerName, 'customer_name'),
          field('Phone', t.customerPhone, 'customer_phone', onTap: t.customerPhone == null ? null : () => launchUrl(Uri(scheme: 'tel', path: t.customerPhone))),
          field('Location', t.customerLocation, 'customer_location'),
          field('Licence', t.licenseNo, 'license_no'),
          if (t.resolution != null) field('Resolution', t.resolution, '_'),
          if (t.taggedUserId != null) _Tagged(t.taggedUserId!, t.departmentId),
          const SizedBox(height: 6),
          if (!pending && t.aiStatus == 'done' && t.details != null) Text(t.details!)
          else if (m.bodyText != null) Text(m.bodyText!) // raw text: while structuring, or when AI could not
          else if (m.transcript != null && m.kind == 'voice' && t.aiStatus != 'done') Text(m.transcript!),
          if (m.kind == 'voice') VoicePlayer(audioKey: m.audioKey!, durationS: m.audioDurationS ?? 0, transcript: t.aiStatus == 'done' ? m.transcript : null),
          if (m.attachments.isNotEmpty) AttachmentStrip(attachments: m.attachments),
          if (shown.isNotEmpty || canAnswer) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              if (canAnswer) FilledButton(key: const Key('answer'), onPressed: () => onAnswer!(t), child: const Text('Answer')),
              for (final a in shown) _button(context, ref, t, a),
              if (rest.isNotEmpty) TextButton.icon(
                key: const Key('more-actions'),
                icon: const Icon(Icons.more_horiz),
                label: const Text('More'),
                onPressed: () async {
                  final a = await showModalBottomSheet<String>(context: context, builder: (sheet) => SafeArea(child: ListView(shrinkWrap: true, children: [
                    for (final a in rest) ListTile(
                      title: Text(actionSpecs[a]?.label ?? a, style: TextStyle(color: (actionSpecs[a]?.danger ?? false) ? Theme.of(sheet).colorScheme.error : null)),
                      onTap: () => Navigator.pop(sheet, a)),
                  ])));
                  if (a != null && context.mounted) await _act(context, ref, t, a);
                },
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _button(BuildContext context, WidgetRef ref, Task t, String a) {
    final spec = actionSpecs[a];
    final label = Text(spec?.label ?? a);
    void go() => _act(context, ref, t, a);
    if (spec?.danger ?? false) return OutlinedButton(style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error), onPressed: go, child: label);
    return a == 'accept' || a == 'complete' || a == 'verify' || a == 'close' || a == 'approve_request'
        ? FilledButton(key: Key('action-$a'), onPressed: go, child: label)
        : OutlinedButton(key: Key('action-$a'), onPressed: go, child: label);
  }

  Future<void> _act(BuildContext context, WidgetRef ref, Task t, String a) async {
    try {
      final updated = await runAction(context, ref, t, a);
      if (updated == null) return;
      onTask?.call(updated);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(doneText(a))));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

class _Tagged extends ConsumerWidget {
  const _Tagged(this.userId, this.deptId);
  final String userId;
  final String? deptId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = deptId == null ? null : ref.watch(departmentProvider(deptId!)).value?.members.where((m) => m.id == userId).firstOrNull?.name;
    return Padding(padding: const EdgeInsets.only(top: 2), child: Text('Tagged: @${name ?? '…'}', style: Theme.of(context).textTheme.bodySmall));
  }
}

class _Shimmer extends StatelessWidget {
  const _Shimmer();
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08);
    Widget bar(double w) => Container(height: 12, width: w, margin: const EdgeInsets.only(bottom: 6), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [bar(180), bar(240), bar(120)]);
  }
}
