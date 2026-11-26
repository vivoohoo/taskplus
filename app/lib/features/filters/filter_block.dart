import 'package:material_ui/material_ui.dart';

/// The three filters, in two rows, equal width, no horizontal scroll (spec §10.1, D1).
enum TaskFilter {
  myPending('my_pending', 'My Pending'),
  overdue('overdue', 'Overdue'),
  sentByMe('sent_by_me', 'Sent by me');

  const TaskFilter(this.api, this.label);
  final String api, label;
}

class FilterBlock extends StatelessWidget {
  const FilterBlock({super.key, required this.onTap, this.myPending, this.overdue, this.sentByMe});
  final void Function(TaskFilter) onTap;
  final int? myPending, overdue, sentByMe;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(children: [
          Row(children: [
            Expanded(child: _FilterButton(TaskFilter.myPending, myPending, onTap)),
            const SizedBox(width: 8),
            Expanded(child: _FilterButton(TaskFilter.overdue, overdue, onTap, danger: true)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _FilterButton(TaskFilter.sentByMe, sentByMe, onTap)),
            const SizedBox(width: 8),
            const Expanded(child: SizedBox.shrink()), // keeps it the same width as the others
          ]),
        ]),
      );
}

class _FilterButton extends StatelessWidget {
  const _FilterButton(this.filter, this.count, this.onTap, {this.danger = false});
  final TaskFilter filter;
  final int? count;
  final void Function(TaskFilter) onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return OutlinedButton(
      key: Key('filter-${filter.api}'),
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 12), visualDensity: VisualDensity.compact),
      onPressed: () => onTap(filter),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Flexible(child: Text(filter.label, overflow: TextOverflow.ellipsis)),
        if (count != null && count! > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: danger ? c.error : c.primary, borderRadius: BorderRadius.circular(10)),
            child: Text('$count', style: TextStyle(color: danger ? c.onError : c.onPrimary, fontSize: 12)),
          ),
        ],
      ]),
    );
  }
}
