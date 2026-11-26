import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/providers.dart';
import '../task_card/task_card.dart';

final _teamProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.watch(repositoryProvider).team());

String _pct(Object? r) => r == null ? '–' : '${((r as num) * 100).round()}%';
String _hrs(Object? ms) => ms == null ? '–' : '${((ms as num) / 3600000).toStringAsFixed(1)} h';

/// Ornate's Team performance for leads: what needs attention first, then how the team is doing.
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(_teamProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Team')),
      body: d.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('$e'))),
        data: (x) {
          final k = x['kpis'] as Map<String, dynamic>, att = x['attention'] as Map<String, dynamic>;
          final m = x['thisMonth'] as Map<String, dynamic>, lm = x['lastMonth'] as Map<String, dynamic>;
          final mv = x['moved'] as Map<String, dynamic>;
          List<Map<String, dynamic>> list(Object? o) => ((o as List?) ?? const []).cast<Map<String, dynamic>>();
          Widget section(String title, List<Widget> children) => Card(
                margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: theme.textTheme.titleMedium), const SizedBox(height: 8), ...children,
                ])),
              );
          Widget row(String a, String b, {Color? color}) => Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
                Expanded(child: Text(a)), Text(b, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
              ]));
          Widget taskRow(Map<String, dynamic> t, String note) => ListTile(
                dense: true, contentPadding: EdgeInsets.zero,
                title: Text('${t['subject'] ?? t['ticketNo']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${t['ticketNo'] ?? ''} · ${statusLabel(t['status'] as String)} · $note'),
                onTap: () => context.push('/chat/${t['threadId']}'),
              );
          final attention = [
            for (final t in list(att['dueSoon'])) taskRow(t, 'due soon${t['assignee'] != null ? ' · ${t['assignee']}' : ''}'),
            for (final t in list(att['waiting'])) taskRow(t, 'stuck ${_hrs(t['stuckMs'])}'),
            for (final q in list(att['queues'])) row('${q['team']} team waiting to be accepted', '${q['count']} · oldest ${_hrs(q['oldestMs'])}'),
          ];
          return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('${x['scope']} · last 2 weeks · working hours', style: theme.textTheme.bodySmall)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: GridView.count(
                crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 2.4, mainAxisSpacing: 8, crossAxisSpacing: 8,
                children: [
                  for (final (v, l, warn) in [('${k['completed']}', 'Completed', false), (_pct(k['onTime']), 'On time', false),
                    ('${k['overdueNow']}', 'Overdue now', (k['overdueNow'] as num) > 0), ('${k['reopened']}', 'Reopened', false)])
                    Card(margin: EdgeInsets.zero, child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(v, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: warn ? theme.colorScheme.error : null)),
                      Text(l, style: theme.textTheme.bodySmall),
                    ]))),
                ],
              ),
            ),
            section('Needs attention', attention.isEmpty ? [const Text('Nothing urgent.')] : attention),
            section('This month', [
              row('Completed', '${m['done']}  (last month ${lm['done']})'),
              row('On time', '${_pct(m['onTime'])}  (${_pct(lm['onTime'])})'),
              row('Average time', '${_hrs(m['avgMs'])}  (${_hrs(lm['avgMs'])})'),
            ]),
            section('On time by priority', [
              for (final p in list(x['byPriority'])) row('${p['priority']}', (p['done'] as num) > 0 ? '${_pct(p['onTime'])} of ${p['done']}' : 'None done',
                  color: p['onTime'] != null && (p['onTime'] as num) < 0.8 ? theme.colorScheme.error : null),
            ]),
            section('Moved and escalated', [
              row('Reassigned', '${mv['reassigned']}'), row('Declined', '${mv['declined']}'),
              row('Reopened', '${mv['reopened']}'), row('Transferred', '${mv['transferred']}'),
              row('Escalated', list(mv['escalations']).map((e) => '${(e['level'] as String).replaceAll('_', ' ')} ${e['count']}').join(' · ').ifEmpty('None')),
              row('Still escalated', '${mv['stillEscalated']}', color: (mv['stillEscalated'] as num) > 0 ? theme.colorScheme.error : null),
            ]),
            section('People', [
              for (final p in list(x['people']))
                ListTile(
                  dense: true, contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Text((p['name'] as String)[0])),
                  title: Text('${p['name']}${p['away'] == true ? ' · away' : ''}'),
                  subtitle: Text('${p['roleLabel']} · done ${p['done']} · on time ${_pct(p['onTime'])} · avg ${_hrs(p['avgMs'])} · moved off ${p['movedOff']}'),
                  trailing: Text('${p['active']} active${p['full'] == true ? ' · full' : ''}',
                      style: TextStyle(color: p['full'] == true ? theme.colorScheme.error : null)),
                ),
            ]),
            if (list(x['teams']).isNotEmpty)
              section('Teams', [
                for (final t in list(x['teams'])) row('${t['team']}', 'open ${t['open']} · overdue ${t['overdue']} · done ${t['done']} · ${_pct(t['onTime'])}',
                    color: (t['overdue'] as num) > 0 ? theme.colorScheme.error : null),
              ]),
            section('Where work comes from', list(x['sources']).isEmpty ? [const Text('No new tasks in the last 2 weeks.')]
                : [for (final s in list(x['sources'])) row('${s['name']} · ${s['department']}', '${s['count']}${(s['sentBack'] as num) > 0 ? ' · ${s['sentBack']} sent back' : ''}')]),
            section('Customers', list(x['customers']).isEmpty ? [const Text('No tasks name a customer.')]
                : [for (final c in list(x['customers'])) row('${c['name']}', '${c['total']} · open ${c['open']} · overdue ${c['overdue']}')]),
            section('Repeat problems', list(x['repeats']).isEmpty ? [const Text('None in the last 2 weeks.')]
                : [for (final t in list(x['repeats'])) taskRow(t, '${t['why']}')]),
            section('Oldest open', [for (final t in list(x['oldest'])) taskRow(t, '${_hrs(t['ageMs'])} old')]),
          ]);
        },
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
