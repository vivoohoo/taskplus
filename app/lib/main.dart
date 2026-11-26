import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'core/auth/auth_controller.dart';
import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'data/models.dart';
import 'features/chat/chat_screen.dart';
import 'features/filters/filter_block.dart';
import 'features/filters/filter_results_screen.dart';
import 'features/home/home_screen.dart';
import 'features/notifications/push.dart';
import 'features/search/search_screen.dart';

void main() => runApp(const ProviderScope(child: TaskPlusApp()));

/// Sign-in decides the route: nobody signed in -> /login, otherwise -> /.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);
  return GoRouter(
    refreshListenable: refresh,
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
      GoRoute(path: '/chat/:id', builder: (_, s) => ChatScreen(threadId: s.pathParameters['id']!, thread: s.extra as ThreadSummary?)),
      GoRoute(path: '/tasks/:filter', builder: (_, s) => FilterResultsScreen(filter: TaskFilter.values.firstWhere((f) => f.api == s.pathParameters['filter'], orElse: () => TaskFilter.myPending))),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/loading', builder: (_, _) => const Scaffold(body: Center(child: CircularProgressIndicator()))),
    ],
    redirect: (_, state) {
      final auth = ref.read(authProvider);
      if (auth.isLoading) return '/loading';
      final signedIn = auth.value != null;
      final at = state.matchedLocation;
      if (!signedIn) return at == '/login' ? null : '/login';
      return at == '/login' || at == '/loading' ? '/' : null;
    },
  );
});

class TaskPlusApp extends ConsumerWidget {
  const TaskPlusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(pushProvider); // registers this phone for notifications once signed in
    return MaterialApp.router(
        title: 'Task Plus',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        routerConfig: ref.watch(routerProvider),
        debugShowCheckedModeBanner: false,
      );
  }
}
