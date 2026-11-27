import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../ornate/widgets.dart';

const _statuses = ['Open', 'Accepted', 'InProgress', 'WaitingInfo', 'WaitingDept', 'Blocked', 'Completed', 'Verified', 'Closed', 'Rejected', 'Transferred', 'Cancelled'];


/// Ornate's Filters: status, priority, requester, owner, type, raised and closed dates, open only.
Future<CaseQuery?> showFiltersDialog(BuildContext context, WidgetRef ref, CaseQuery current) => showDialog<CaseQuery>(
      context: context,
      builder: (_) => _FiltersDialog(current: current),
    );

class _FiltersDialog extends ConsumerStatefulWidget {
  const _FiltersDialog({required this.current});
  final CaseQuery current;
  @override
  ConsumerState<_FiltersDialog> createState() => _FiltersDialogState();
}

class _FiltersDialogState extends ConsumerState<_FiltersDialog> {
  late String? status = widget.current.status, priority = widget.current.priority, requester = widget.current.requester,
      owner = widget.current.owner, type = widget.current.type, from = widget.current.from, to = widget.current.to,
      closedFrom = widget.current.closedFrom, closedTo = widget.current.closedTo;
  late bool openOnly = widget.current.openOnly;

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(peopleProvider).value ?? const <Member>[];
    Widget drop(String label, String? value, List<(String, String)> options, void Function(String?) on, {String any = 'Any'}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: DropdownButtonFormField<String?>(
            initialValue: value,
            isExpanded: true,
            decoration: InputDecoration(labelText: label, isDense: true),
            items: [DropdownMenuItem(value: null, child: Text(any)), for (final (v, l) in options) DropdownMenuItem(value: v, child: Text(l, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => on(v)),
          ),
        );
    Widget date(String label, String? value, void Function(String?) on) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            onTap: () async {
              final d = await showDatePicker(context: context, firstDate: DateTime(2025), lastDate: DateTime(2030), initialDate: DateTime.now());
              if (d != null) setState(() => on(DateFormat('yyyy-MM-dd').format(d)));
            },
            child: InputDecorator(
              decoration: InputDecoration(labelText: label, isDense: true,
                  suffixIcon: value == null ? const Icon(Icons.event) : IconButton(icon: const Icon(Icons.clear), tooltip: 'Clear', onPressed: () => setState(() => on(null)))),
              child: Text(value ?? 'Any'),
            ),
          ),
        );
    return AlertDialog(
      title: const Text('Filters'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          drop('Status', status, [for (final s in _statuses) (s, statusLabel(s))], (v) => status = v),
          drop('Priority', priority, [for (final p in const ['Critical', 'High', 'Medium', 'Low']) (p, p)], (v) => priority = v),
          drop('Requester', requester, [for (final m in people) (m.id, m.name)], (v) => requester = v, any: 'Anyone'),
          drop('Owner', owner, [for (final m in people) (m.id, m.name)], (v) => owner = v, any: 'Anyone'),
          drop('Type', type, const [('Internal', 'Internal'), ('Self', 'Private note')], (v) => type = v),
          CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('Open only'), value: openOnly, onChanged: (v) => setState(() => openOnly = v ?? false)),
          date('Raised from', from, (v) => from = v),
          date('Raised to', to, (v) => to = v),
          date('Closed from', closedFrom, (v) => closedFrom = v),
          date('Closed to', closedTo, (v) => closedTo = v),
        ])),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, const CaseQuery()), child: const Text('Clear all')),
        FilledButton(
          onPressed: () => Navigator.pop(context, CaseQuery(status: status, priority: priority, requester: requester, owner: owner, type: type,
              from: from, to: to, closedFrom: closedFrom, closedTo: closedTo, openOnly: openOnly)),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
