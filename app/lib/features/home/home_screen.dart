import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/realtime.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../filters/filter_block.dart';

/// Chats: search, the three filters, then every thread (direct and department), newest first.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  StreamSubscription? _events, _reconnect;

  @override
  void initState() {
    super.initState();
    // Any live change refreshes the list and the badges.
    ref.listenManual(realtimeProvider, (_, next) {
      _events?.cancel();
      _reconnect?.cancel();
      final rt = next.value;
      if (rt == null) return;
      _events = rt.events.listen((_) { ref.invalidate(threadsProvider); ref.invalidate(countsProvider); });
      _reconnect = rt.connected.listen((_) => ref.read(outboxProvider).flush());
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _events?.cancel();
    _reconnect?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final threads = ref.watch(threadsProvider);
    final counts = ref.watch(countsProvider).value;
    ref.watch(outboxProvider); // starts the sender
    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Plus'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (_) => ref.read(authProvider.notifier).signOut(),
            itemBuilder: (_) => const [PopupMenuItem(value: 'out', child: Text('Sign out'))],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async { ref.invalidate(threadsProvider); ref.invalidate(countsProvider); await ref.read(threadsProvider.future); },
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: TextField(
                key: const Key('search'),
                readOnly: true,
                onTap: () => context.push('/search'),
                decoration: InputDecoration(
                  hintText: 'Search people or departments', prefixIcon: const Icon(Icons.search), isDense: true, filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(child: FilterBlock(myPending: counts?.myPending, overdue: counts?.overdue, onTap: (f) => context.push('/tasks/${f.api}'))),
          ...threads.when(
            loading: () => [const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))],
            error: (e, _) => [SliverFillRemaining(child: Center(child: Text('$e')))],
            data: (list) => list.isEmpty
                ? [const SliverFillRemaining(child: Center(child: Text('No chats yet. Search for a person or department to start one.')))]
                : [SliverList.builder(itemCount: list.length, itemBuilder: (_, i) => ThreadTile(thread: list[i]))],
          ),
        ]),
      ),
    );
  }
}

class ThreadTile extends StatelessWidget {
  const ThreadTile({super.key, required this.thread});
  final ThreadSummary thread;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final t = thread;
    return ListTile(
      leading: CircleAvatar(child: t.isDepartment && t.subtitle == 'Department' ? const Icon(Icons.groups) : Text(t.title.isEmpty ? '?' : t.title[0])),
      title: Text(t.title, overflow: TextOverflow.ellipsis),
      subtitle: Text(t.lastText ?? t.subtitle ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (t.lastAt != null) Text(_time(t.lastAt!), style: Theme.of(context).textTheme.bodySmall),
        if (t.openTasks > 0)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(10)),
            child: Text('${t.openTasks}', style: TextStyle(color: c.onPrimary, fontSize: 12)),
          ),
      ]),
      onTap: () => context.push('/chat/${t.id}', extra: t),
    );
  }

  static String _time(DateTime d) {
    final local = d.toLocal(), now = DateTime.now();
    return local.year == now.year && local.month == now.month && local.day == now.day ? DateFormat.Hm().format(local) : DateFormat('d MMM').format(local);
  }
}
