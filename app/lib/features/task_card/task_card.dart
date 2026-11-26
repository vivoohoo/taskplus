import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_controller.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../chat/attachments.dart';
import '../chat/voice_player.dart';

/// Who may do what on a card (spec §10.3). Pure, so widget tests can check every role.
class CardActions {
  CardActions({required this.accept, required this.reassign, required this.next, this.cancel = false});
  final bool accept, reassign, cancel;
  final List<String> next; // InProgress / Closed

  factory CardActions.of(Task t, {required AppUser viewer, required String senderId, required bool directRecipient}) {
    final mine = t.assigneeId == viewer.id;
    final inDept = viewer.departmentId != null && viewer.departmentId == t.departmentId;
    return CardActions(
      accept: t.status == 'Open' && senderId != viewer.id && (t.departmentId == null ? directRecipient : inDept),
      reassign: t.status != 'Closed' && senderId != viewer.id && (mine || (viewer.role == 'dept_head' && (inDept || t.departmentId == null))),
      cancel: senderId == viewer.id && t.status == 'Open', // D4
      next: !mine ? const [] : switch (t.status) { 'Accepted' => const ['InProgress', 'Closed'], 'InProgress' => const ['Closed'], _ => const [] },
    );
  }
}

/// Status names as people read them.
String statusLabel(String s) => switch (s) {
      'InProgress' => 'In progress',
      'WaitingInfo' => 'Waiting for information',
      _ => s,
    };

const priorityColors = {'Critical': Color(0xFF8E0000), 'High': Color(0xFFD93025), 'Medium': Color(0xFFE37400), 'Low': Color(0xFF5F6368)};

class TaskCard extends ConsumerWidget {
  const TaskCard({super.key, required this.item, required this.directRecipient, this.onTask, this.now});
  final ChatItem item;
  /// In a direct chat, whether the viewer is the one it was sent to.
  final bool directRecipient;
  final void Function(Task)? onTask;
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = item.task!;
    final m = item.message;
    final viewer = ref.watch(authProvider).value;
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final pending = t.aiStatus == 'pending';
    final actions = viewer == null ? null : CardActions.of(t, viewer: viewer, senderId: m.senderId, directRecipient: directRecipient);
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
            if (t.status != 'Open') Text(statusLabel(t.status), style: theme.textTheme.labelMedium),
          ]),
          const SizedBox(height: 6),
          if (pending) ...[
            const _Shimmer(),
            const SizedBox(height: 6),
            Text(m.kind == 'voice' && m.transcript == null ? 'Transcribing…' : 'Structuring…', style: theme.textTheme.labelMedium),
          ] else if (t.subject != null)
            Text(t.subject!, style: theme.textTheme.titleMedium),
          field('Customer', t.customerName, 'customer_name'),
          field('Phone', t.customerPhone, 'customer_phone', onTap: t.customerPhone == null ? null : () => launchUrl(Uri(scheme: 'tel', path: t.customerPhone))),
          field('Location', t.customerLocation, 'customer_location'),
          field('Licence', t.licenseNo, 'license_no'),
          if (t.taggedUserId != null) _Tagged(t.taggedUserId!, t.departmentId),
          const SizedBox(height: 6),
          if (!pending && t.aiStatus == 'done' && t.details != null) Text(t.details!)
          else if (m.bodyText != null) Text(m.bodyText!) // raw text: while structuring, or when AI could not
          else if (m.transcript != null && m.kind == 'voice' && t.aiStatus != 'done') Text(m.transcript!),
          if (m.kind == 'voice') VoicePlayer(audioKey: m.audioKey!, durationS: m.audioDurationS ?? 0, transcript: t.aiStatus == 'done' ? m.transcript : null),
          if (m.attachments.isNotEmpty) AttachmentStrip(attachments: m.attachments),
          if (actions != null && (actions.accept || actions.reassign || actions.cancel || actions.next.isNotEmpty)) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              if (actions.accept) FilledButton(onPressed: () => _run(context, ref, (r) => r.accept(t.id)), child: const Text('Accept Task')),
              if (actions.reassign) OutlinedButton(onPressed: () => _reassign(context, ref, t), child: const Text('Reassign')),
              if (actions.cancel) OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                  onPressed: () => _confirmCancel(context, ref, t), child: const Text('Cancel task')),
              for (final s in actions.next)
                OutlinedButton(onPressed: () => _run(context, ref, (r) => r.setStatus(t.id, s)), child: Text(s == 'InProgress' ? 'Mark In Progress' : 'Close')),
            ]),
          ],
        ]),
      ),
    );
  }

  Future<void> _run(BuildContext context, WidgetRef ref, Future<Task> Function(dynamic repo) f) async {
    try {
      onTask?.call(await f(ref.read(repositoryProvider)));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref, Task t) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Cancel this task?'),
      content: const Text('Nobody has accepted it yet. It will show as Cancelled for everyone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel task')),
      ],
    ));
    if (ok == true && context.mounted) await _run(context, ref, (r) => r.cancel(t.id));
  }

  Future<void> _reassign(BuildContext context, WidgetRef ref, Task t) async {
    final deptId = t.departmentId ?? ref.read(authProvider).value?.departmentId;
    if (deptId == null) return;
    final dept = await ref.read(departmentProvider(deptId).future);
    if (!context.mounted) return;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('Reassign to')),
          for (final m in dept.members.where((m) => m.id != t.assigneeId))
            ListTile(leading: CircleAvatar(child: Text(m.name[0])), title: Text(m.name), onTap: () => Navigator.pop(context, m.id)),
        ]),
      ),
    );
    if (chosen != null && context.mounted) await _run(context, ref, (r) => r.reassign(t.id, chosen));
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
