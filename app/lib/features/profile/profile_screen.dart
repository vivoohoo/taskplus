import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../data/providers.dart';

final _profileProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.watch(repositoryProvider).profile());

/// You: short role label ("ProfitNX lead"), a separate "Reporting manager" line, change password, sign out.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(_profileProvider);
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('You')),
      body: p.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (me) => ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            CircleAvatar(radius: 32, child: Text((me['name'] as String)[0], style: t.textTheme.headlineSmall)),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(me['name'] as String, style: t.textTheme.titleLarge),
              Text(me['roleLabel'] as String? ?? '', key: const Key('role-label'), style: t.textTheme.bodyMedium),
              if (me['reportingManager'] != null)
                Text('Reporting manager: ${me['reportingManager']}', key: const Key('manager'), style: t.textTheme.bodySmall),
            ])),
          ]),
          const SizedBox(height: 16),
          if (me['departmentName'] != null) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.apartment), title: Text(me['departmentName'] as String), subtitle: const Text('Department')),
          if (me['teamName'] != null) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.groups), title: Text('${me['teamName']} team'), subtitle: const Text('Team')),
          const Divider(),
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.lock_outline), title: const Text('Change password'), onTap: () => _changePassword(context, ref)),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout, color: t.colorScheme.error),
            title: Text('Sign out', style: TextStyle(color: t.colorScheme.error)),
            onTap: () => ref.read(authProvider.notifier).signOut(),
          ),
        ]),
      ),
    );
  }

  Future<void> _changePassword(BuildContext context, WidgetRef ref) async {
    final cur = TextEditingController(), next = TextEditingController();
    String? error;
    await showDialog<void>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(
      title: const Text('Change password'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: cur, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
        const SizedBox(height: 12),
        TextField(controller: next, obscureText: true, decoration: const InputDecoration(labelText: 'New password', helperText: 'At least 8 characters, with a letter and a number')),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          try {
            await ref.read(repositoryProvider).changePassword(cur.text, next.text);
            if (ctx.mounted) Navigator.pop(ctx);
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed. Sign in again on your other phones.')));
          } catch (e) {
            set(() => error = '$e');
          }
        }, child: const Text('Change')),
      ],
    )));
  }
}
