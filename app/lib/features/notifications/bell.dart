import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';
import '../../data/providers.dart';
import '../ornate/widgets.dart';

final notificationsProvider = FutureProvider((ref) => ref.watch(repositoryProvider).notifications());

/// The bell in the top bar, with the unread count (Ornate).
class BellButton extends ConsumerWidget {
  const BellButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(notificationsProvider).value?.unread ?? 0;
    return IconButton(
      key: const Key('bell'),
      tooltip: 'Notifications, $unread unread',
      onPressed: () => context.push('/notifications'),
      icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), backgroundColor: context.o.badge, textColor: context.o.badgeText,
          child: const Icon(Icons.notifications_none)),
    );
  }
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = context.o;
    final n = ref.watch(notificationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications'), actions: [
        TextButton(key: const Key('read-all'), onPressed: () async {
          await ref.read(repositoryProvider).markAllNotificationsRead();
          ref.invalidate(notificationsProvider);
        }, child: const Text('Mark all read')),
      ]),
      body: n.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (d) => d.items.isEmpty
            ? Center(child: Text('No notifications yet.', style: TextStyle(color: o.muted)))
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(notificationsProvider),
                child: ListView.separated(
                  itemCount: d.items.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: o.line),
                  itemBuilder: (_, i) {
                    final x = d.items[i];
                    return ListTile(
                      key: Key('notif-${x.id}'),
                      title: Text(x.text, style: TextStyle(fontWeight: x.read ? FontWeight.w400 : FontWeight.w700)),
                      subtitle: Text('${x.ticketNo ?? ''}${x.subject != null ? ' · ${x.subject}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(listTime(x.at), style: TextStyle(fontSize: 12, color: o.muted)),
                        if (!x.read) Padding(padding: const EdgeInsets.only(top: 6), child: Container(width: 10, height: 10, decoration: BoxDecoration(color: o.accent, shape: BoxShape.circle))),
                      ]),
                      onTap: () async {
                        if (!x.read) {
                          await ref.read(repositoryProvider).markNotificationRead(x.id);
                          ref.invalidate(notificationsProvider);
                        }
                        if (context.mounted) context.push('/case/${x.taskId}');
                      },
                    );
                  },
                ),
              ),
      ),
    );
  }
}
