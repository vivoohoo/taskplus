import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../task_card/task_card.dart';
import 'filter_block.dart';

/// Tasks for one filter, as the same cards as in chats. Tapping the header of a card opens its chat.
class FilterResultsScreen extends ConsumerStatefulWidget {
  const FilterResultsScreen({super.key, required this.filter});
  final TaskFilter filter;
  @override
  ConsumerState<FilterResultsScreen> createState() => _FilterResultsScreenState();
}

class _FilterResultsScreenState extends ConsumerState<FilterResultsScreen> {
  List<ChatItem> _items = [];
  int? _next = 0;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading || _next == null) return;
    setState(() => _loading = true);
    try {
      final r = await ref.read(repositoryProvider).tasks(widget.filter.api, cursor: _next!);
      setState(() { _items = [..._items, ...r.items]; _next = r.nextCursor; _error = null; });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _replace(Task t) => setState(() => _items = [for (final i in _items) i.task?.id == t.id ? ChatItem(message: i.message, task: Task.newest(i.task, t)) : i]);

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authProvider).value;
    return Scaffold(
      appBar: AppBar(title: Text(widget.filter.label)),
      body: _error != null && _items.isEmpty
          ? Center(child: Text(_error!))
          : _items.isEmpty && !_loading
              ? const Center(child: Text('Nothing here.'))
              : NotificationListener<ScrollNotification>(
                  onNotification: (n) { if (n.metrics.extentAfter < 300) _load(); return false; },
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _items.length + (_loading ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == _items.length) return const Center(child: CircularProgressIndicator());
                      final item = _items[i];
                      return GestureDetector(
                        onLongPress: () => context.push('/chat/${item.message.threadId}'),
                        child: TaskCard(item: item, directRecipient: item.message.senderId != me?.id, onTask: _replace),
                      );
                    },
                  ),
                ),
    );
  }
}
