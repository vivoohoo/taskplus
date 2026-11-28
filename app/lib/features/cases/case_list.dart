import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../ornate/widgets.dart';
import 'filters_dialog.dart';

const chips = ['All', 'Active', 'To Verify', 'Sent by me', 'Overdue/Escalated', 'Verified / Closed'];

final caseQueryProvider = NotifierProvider.family<CaseQueryState, CaseQuery, String>(CaseQueryState.new);
class CaseQueryState extends Notifier<CaseQuery> {
  CaseQueryState(this.tab);
  final String tab;
  @override
  CaseQuery build() {
    ref.watch(authProvider.select((u) => u.value?.id)); // a new person starts with clear filters
    return CaseQuery(tab: tab);
  }
  void set(CaseQuery q) => state = q;
}

/// Wide screens (WhatsApp Web, as in Ornate): what the right pane shows. `case:<taskId>` or `person:<party>|<tab>`.
final paneProvider = NotifierProvider<Pane, String?>(Pane.new);
class Pane extends Notifier<String?> {
  @override
  String? build() { ref.watch(authProvider.select((u) => u.value?.id)); return null; }
  void show(String? v) => state = v;
}
bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 900;

void openCase(BuildContext context, WidgetRef ref, String taskId) =>
    isWide(context) ? ref.read(paneProvider.notifier).show('case:$taskId') : context.push('/case/$taskId');
void openPerson(BuildContext context, WidgetRef ref, Party p, String tab) => isWide(context)
    ? ref.read(paneProvider.notifier).show('person:${p.key}|$tab')
    : context.push('/person/${Uri.encodeComponent(p.key)}?tab=$tab', extra: p);

final casesProvider = FutureProvider.family<CaseList, CaseQuery>((ref, q) => ref.watch(repositoryProvider).cases(q));
final caseCountsProvider = FutureProvider<({int my, int queue, int all})>((ref) => ref.watch(repositoryProvider).caseCounts());

/// One tab (My Tasks, Queue or All Cases): search, department, Filters, chips, then one chat per person (Ornate's CaseList).
class CaseListView extends ConsumerStatefulWidget {
  const CaseListView({super.key, required this.tab});
  final String tab;
  @override
  ConsumerState<CaseListView> createState() => _CaseListViewState();
}

class _CaseListViewState extends ConsumerState<CaseListView> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = context.o;
    final q = ref.watch(caseQueryProvider(widget.tab));
    final set = ref.read(caseQueryProvider(widget.tab).notifier).set;
    final list = ref.watch(casesProvider(q));
    final me = ref.watch(authProvider).value?.id ?? '';
    final depts = ref.watch(_deptsProvider).value ?? const [];

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: TextField(
          key: Key('case-search-${widget.tab}'),
          controller: _search,
          onSubmitted: (v) => set(q.copy(q: v.trim())),
          onChanged: (v) { if (v.isEmpty) set(q.copy(q: '')); },
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search', prefixIcon: Icon(Icons.search, color: o.muted), isDense: true, filled: true, fillColor: o.panel,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
          ),
        ),
      ),
      SizedBox(
        height: 48,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
          _DeptChip(value: q.dept, depts: depts, onChanged: (d) => set(d == null ? q.copy(clearDept: true) : q.copy(dept: d))),
          const SizedBox(width: 8),
          OChip(q.filterCount > 0 ? 'Filters (${q.filterCount})' : 'Filters', on: q.filterCount > 0, onTap: () async {
            final f = await showFiltersDialog(context, ref, q);
            if (f != null) set(q.withFilters(f));
          }),
          for (final c in chips) ...[const SizedBox(width: 8), OChip(c, key: Key('chip-$c'), on: q.chip == c, onTap: () => set(q.copy(chip: c)))],
        ]),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () async { ref.invalidate(casesProvider(q)); ref.invalidate(caseCountsProvider); await ref.read(casesProvider(q).future); },
          child: list.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('$e', textAlign: TextAlign.center))]),
            data: (l) => _rows(context, l, me, q),
          ),
        ),
      ),
    ]);
  }

  Widget _rows(BuildContext context, CaseList l, String me, CaseQuery q) {
    final o = context.o;
    final children = <Widget>[];
    if (l.stats != null) {
      final s = l.stats!;
      children.add(Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: o.panel, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          for (final (n, label, warn) in [(s.waiting, 'Waiting', false), (s.inProgress, 'In progress', false), (s.overdue, 'Overdue', s.overdue > 0)])
            Expanded(child: Column(children: [
              Text('$n', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: warn ? o.danger : o.text)),
              Text(label, style: TextStyle(fontSize: 12.5, color: warn ? o.danger : o.muted)),
            ])),
        ]),
      ));
    }
    if (l.grouped) {
      // One chat per person: open tickets only, grouped by who is on the other side (Ornate).
      final groups = <String, List<CaseRow>>{};
      for (final r in l.rows.where((r) => !const ['Closed', 'Rejected', 'Cancelled', 'Transferred'].contains(r.task.status))) {
        groups.putIfAbsent(r.party.key, () => []).add(r);
      }
      for (final g in groups.values) {
        children.add(g.length == 1 ? CaseRowTile(row: g.first, me: me) : PersonRow(rows: g, me: me, tab: q.tab));
      }
    } else {
      for (final r in l.rows) {
        children.add(CaseRowTile(row: r, me: me));
      }
    }
    if (children.isEmpty || (l.stats != null && children.length == 1)) {
      children.add(Padding(padding: const EdgeInsets.fromLTRB(16, 32, 16, 32),
          child: Text(q.q.isNotEmpty || q.filterCount > 0 ? 'No cases match your search and filters.' : 'Nothing here right now.',
              textAlign: TextAlign.center, style: TextStyle(color: o.muted))));
    }
    return ListView(padding: const EdgeInsets.only(bottom: 110), children: children);
  }
}

final _deptsProvider = FutureProvider((ref) => ref.watch(repositoryProvider).departments());

class _DeptChip extends StatelessWidget {
  const _DeptChip({required this.value, required this.depts, required this.onChanged});
  final String? value;
  final List<({String id, String name})> depts;
  final void Function(String?) onChanged;
  @override
  Widget build(BuildContext context) {
    final name = depts.where((d) => d.id == value).firstOrNull?.name;
    return OChip(name ?? 'All departments ▾', key: const Key('dept-chip'), on: value != null, onTap: () async {
      final pick = await showModalBottomSheet<String>(context: context, builder: (s) => SafeArea(child: ListView(shrinkWrap: true, children: [
        ListTile(title: const Text('All departments'), trailing: value == null ? const Icon(Icons.check) : null, onTap: () => Navigator.pop(s, '')),
        for (final d in depts) ListTile(title: Text(d.name), trailing: d.id == value ? const Icon(Icons.check) : null, onTap: () => Navigator.pop(s, d.id)),
      ])));
      if (pick != null) onChanged(pick.isEmpty ? null : pick);
    });
  }
}

/// One ticket: who, the ticket number and subject, the last message.
class CaseRowTile extends ConsumerWidget {
  const CaseRowTile({super.key, required this.row, required this.me});
  final CaseRow row;
  final String me;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = context.o;
    final t = row.task;
    final active = ref.watch(paneProvider) == 'case:${t.id}';
    final mine = row.lastMine && row.lastEvent == null;
    return Material(
      color: active ? o.panel : Colors.transparent,
      child: InkWell(
      key: Key('row-${t.id}'),
      onTap: () => openCase(context, ref, t.id),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        child: Row(children: [
          OAvatar(row.party.name, lock: row.party.isSelf),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: o.line))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (row.party.isSelf) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.lock, size: 14, color: o.muted)),
                  Expanded(child: Text.rich(TextSpan(children: [
                    TextSpan(text: row.party.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                    TextSpan(text: ' · ${row.party.sub}', style: TextStyle(fontSize: 14, color: o.muted)),
                  ]), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text(listTime(row.lastAt), style: TextStyle(fontSize: 12, color: row.overdue ? o.danger : o.muted, fontWeight: row.overdue ? FontWeight.w600 : null)),
                ]),
                Text('${t.ticketNo ?? ''} · ${t.subject ?? 'Reading the message…'}', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: row.overdue ? o.danger : o.muted)),
                Row(children: [
                  if (mine) Padding(padding: const EdgeInsets.only(right: 3), child: Icon(Icons.done_all, size: 16, color: o.tick)),
                  Expanded(child: Text(previewOf(row), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: o.muted))),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    ));
  }
}

/// A person with several open tickets: their summary line; opens their chat.
class PersonRow extends ConsumerWidget {
  const PersonRow({super.key, required this.rows, required this.me, required this.tab});
  final List<CaseRow> rows;
  final String me, tab;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = context.o;
    final p = rows.first.party;
    final active = ref.watch(paneProvider) == 'person:${p.key}|$tab';
    final over = rows.any((r) => r.overdue);
    final last = rows.first;
    return Material(
      color: active ? o.panel : Colors.transparent,
      child: InkWell(
      key: Key('person-${p.key}'),
      onTap: () => openPerson(context, ref, p, tab),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        child: Row(children: [
          OAvatar(p.name, lock: p.isSelf),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: o.line))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text.rich(TextSpan(children: [
                    TextSpan(text: p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                    TextSpan(text: ' · ${p.sub}', style: TextStyle(fontSize: 14, color: o.muted)),
                  ]), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text(listTime(last.lastAt), style: TextStyle(fontSize: 12, color: over ? o.danger : o.muted)),
                ]),
                Text(summaryLine(rows, me), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: over ? o.danger : o.muted)),
                Text('${last.task.ticketNo?.split('-').last ?? ''} · ${previewOf(last)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: o.muted)),
              ]),
            ),
          ),
        ]),
      ),
    ));
  }
}
