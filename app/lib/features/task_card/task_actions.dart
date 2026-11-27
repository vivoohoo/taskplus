import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../data/providers.dart';

/// What each workflow action needs from the person, and how its button reads. The server decides which ones they get.
enum Need { none, reason, remarks, question, close, department, escalate, priority, confirm, member, edit, handOff }

class ActionSpec {
  const ActionSpec(this.label, this.need, {this.danger = false, this.primary = false, this.prompt});
  final String label;
  final Need need;
  final bool danger, primary;
  final String? prompt;
}

const actionSpecs = <String, ActionSpec>{
  'accept': ActionSpec('Accept Task', Need.none, primary: true),
  'decline': ActionSpec('Decline', Need.reason, prompt: 'Why are you declining?'),
  'in_progress': ActionSpec('Mark In Progress', Need.none, primary: true),
  'ask_reassign': ActionSpec('Ask lead to reassign', Need.reason, prompt: 'Why should it go to someone else?'),
  'keep': ActionSpec('Keep it with me', Need.confirm, primary: true),
  'reassign': ActionSpec('Reassign', Need.member, primary: true),
  'complete': ActionSpec('Complete', Need.remarks, primary: true),
  'verify': ActionSpec('Verify', Need.none, primary: true),
  'close': ActionSpec('Close', Need.close, primary: true),
  'reopen': ActionSpec('Reopen', Need.reason, prompt: 'What is still wrong?'),
  'ask_requester': ActionSpec('Ask requester', Need.question),
  'block': ActionSpec('Block', Need.reason, prompt: 'What is stopping the work?'),
  'unblock': ActionSpec('Unblock', Need.none, primary: true),
  'request_reject': ActionSpec('Ask to reject', Need.reason, danger: true, prompt: 'Why should it be rejected?'),
  'request_transfer': ActionSpec('Ask to transfer', Need.department, prompt: 'Why should it move?'),
  'approve_request': ActionSpec('Approve request', Need.none, primary: true),
  'refuse_request': ActionSpec('Refuse request', Need.none, primary: true),
  'reject': ActionSpec('Reject task', Need.reason, danger: true, prompt: 'Reason for rejecting'),
  'transfer': ActionSpec('Transfer to another department', Need.department, prompt: 'Reason for transfer'),
  'escalate': ActionSpec('Escalate', Need.escalate),
  'attend': ActionSpec('Attend escalation', Need.none, primary: true),
  'change_priority': ActionSpec('Change priority', Need.priority),
  'cancel': ActionSpec('Cancel task', Need.confirm, danger: true),
  'edit': ActionSpec('Edit', Need.edit),
  'hand_off': ActionSpec('Hand Off', Need.handOff, primary: true),
  'complete_cancel_subs': ActionSpec('Complete – cancel open sub-tasks', Need.remarks),
};

/// Short past-tense message after an action (plain, as decided for Ornate).
String doneText(String a) => const {
      'accept': 'Accepted', 'decline': 'Declined', 'in_progress': 'In progress', 'ask_reassign': 'Reassignment requested', 'keep': 'Request turned down',
      'reassign': 'Reassigned', 'complete': 'Marked complete', 'verify': 'Verified', 'close': 'Closed', 'reopen': 'Reopened', 'ask_requester': 'Question sent',
      'block': 'Blocked', 'unblock': 'Unblocked', 'request_reject': 'Rejection requested', 'request_transfer': 'Transfer requested',
      'approve_request': 'Request approved', 'refuse_request': 'Request refused', 'reject': 'Rejected', 'transfer': 'Transferred', 'escalate': 'Escalated',
      'attend': 'Marked as attending', 'change_priority': 'Priority changed', 'cancel': 'Cancelled', 'edit': 'Changes saved',
      'complete_cancel_subs': 'Completed',
    }[a] ?? 'Saved';

/// Asks for what the action needs, runs it, and returns the updated task (null if the person backed out).
Future<Task?> runAction(BuildContext context, WidgetRef ref, Task t, String action) async {
  final spec = actionSpecs[action] ?? ActionSpec(action, Need.none);
  final repo = ref.read(repositoryProvider);
  Map<String, dynamic>? body = const {};
  switch (spec.need) {
    case Need.none:
      break;
    case Need.handOff:
      return null; // the case page puts /subtask in the chat box instead
    case Need.edit:
      final cur = (await repo.task(t.id)).message.bodyText ?? '';
      if (!context.mounted) return null;
      final c = TextEditingController(text: cur);
      final text = await showDialog<String>(context: context, builder: (d) => AlertDialog(
        title: const Text('Edit'),
        content: TextField(controller: c, autofocus: true, minLines: 2, maxLines: 8, decoration: InputDecoration(
            labelText: 'Your message', helperText: t.isNote ? null : 'The card is read again from your new words.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Back')),
          FilledButton(onPressed: () { if (c.text.trim().isNotEmpty) Navigator.pop(d, c.text.trim()); }, child: const Text('Save')),
        ],
      ));
      if (text == null) return null;
      body = {'text': text};
    case Need.confirm:
      final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        title: Text('${spec.label}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(spec.label)),
        ],
      ));
      if (ok != true) return null;
    case Need.reason:
    case Need.remarks:
    case Need.question:
      final key = spec.need == Need.remarks ? 'remarks' : spec.need == Need.question ? 'question' : 'reason';
      final text = await _askText(context, spec.label, spec.need == Need.remarks ? 'What was done?' : spec.need == Need.question ? 'Your question' : spec.prompt ?? 'Reason');
      if (text == null) return null;
      body = {key: text};
    case Need.close:
      body = t.isNote ? const {} : await _askClose(context);
    case Need.department:
      final depts = (await repo.departments()).where((d) => d.id != t.departmentId).toList();
      if (!context.mounted) return null;
      final dept = await _pick(context, 'Move to', [for (final d in depts) (d.id, d.name)]);
      if (dept == null || !context.mounted) return null;
      final reason = await _askText(context, spec.label, spec.prompt ?? 'Reason');
      if (reason == null) return null;
      body = {'departmentId': dept, 'reason': reason};
    case Need.escalate:
      final level = await _pick(context, 'Escalate to', const [('team_lead', 'Team lead'), ('dept_head', 'Department head'), ('management', 'Management')]);
      if (level == null || !context.mounted) return null;
      final reason = await _askText(context, 'Escalate', 'Why are you escalating?');
      if (reason == null) return null;
      body = {'level': level, 'reason': reason};
    case Need.priority:
      final p = await _pick(context, 'Priority', [for (final x in const ['Critical', 'High', 'Medium', 'Low']) if (x != t.priority) (x, x)]);
      if (p == null || !context.mounted) return null;
      final reason = await _askText(context, 'Change priority', 'Reason for the change');
      if (reason == null) return null;
      body = {'priority': p, 'reason': reason};
    case Need.member:
      final deptId = t.departmentId;
      if (deptId == null) return null;
      final dept = await ref.read(departmentProvider(deptId).future);
      if (!context.mounted) return null;
      final who = await _pick(context, 'Reassign to', [
        for (final m in dept.members.where((m) => m.id != t.assigneeId))
          (m.id, '${m.name} · ${m.roleLabel ?? ''} · ${m.active} active${m.full ? ' · full' : ''}${m.away ? ' · away' : ''}'),
      ]);
      if (who == null) return null;
      return repo.reassign(t.id, who);
  }
  if (body == null) return null;
  return repo.action(t.id, action, body);
}

Future<String?> _askText(BuildContext context, String title, String label) {
  final c = TextEditingController();
  return showDialog<String>(context: context, builder: (d) => AlertDialog(
    title: Text(title),
    content: TextField(controller: c, autofocus: true, minLines: 1, maxLines: 4, decoration: InputDecoration(labelText: label)),
    actions: [
      TextButton(onPressed: () => Navigator.pop(d), child: const Text('Back')),
      FilledButton(onPressed: () { if (c.text.trim().isNotEmpty) Navigator.pop(d, c.text.trim()); }, child: Text(title)),
    ],
  ));
}

Future<String?> _pick(BuildContext context, String title, List<(String, String)> options) => showModalBottomSheet<String>(
      context: context,
      builder: (s) => SafeArea(child: ListView(shrinkWrap: true, children: [
        ListTile(title: Text(title, style: Theme.of(s).textTheme.titleMedium)),
        for (final (v, label) in options) ListTile(title: Text(label), onTap: () => Navigator.pop(s, v)),
      ])),
    );

/// Close: a resolution summary and "Was the customer informed?" (Ornate's close).
Future<Map<String, dynamic>?> _askClose(BuildContext context) {
  final c = TextEditingController();
  String? informed;
  return showDialog<Map<String, dynamic>>(context: context, builder: (d) => StatefulBuilder(builder: (d, set) => AlertDialog(
    title: const Text('Close'),
    content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(controller: c, autofocus: true, minLines: 1, maxLines: 4, decoration: const InputDecoration(labelText: 'Resolution summary')),
      const SizedBox(height: 12),
      const Text('Was the customer informed?'),
      Wrap(spacing: 8, children: [
        for (final (v, l) in const [('yes', 'Yes'), ('no', 'No'), ('n/a', 'No customer')])
          ChoiceChip(label: Text(l), selected: informed == v, onSelected: (_) => set(() => informed = v)),
      ]),
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.pop(d), child: const Text('Back')),
      FilledButton(
        onPressed: () { if (c.text.trim().isNotEmpty && informed != null) Navigator.pop(d, {'resolution': c.text.trim(), 'customerInformed': informed}); },
        child: const Text('Close'),
      ),
    ],
  )));
}
