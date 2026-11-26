import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/auth/auth_controller.dart';

/// Chats list. M1: placeholder; the search field, filter block and threads come in M2.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).value;
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
      body: Center(child: Text('Signed in as ${user?.name ?? ''}')),
    );
  }
}
