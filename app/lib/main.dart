import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'core/auth/auth_controller.dart';
import 'core/config.dart';
import 'core/theme.dart';
import 'features/auth/login_screen.dart';
import 'data/models.dart';
import 'features/chat/chat_screen.dart';
import 'features/filters/filter_block.dart';
import 'features/filters/filter_results_screen.dart';
import 'features/home/home_screen.dart';
import 'features/notifications/push.dart';
import 'features/profile/profile_screen.dart';
import 'features/profile/settings_screens.dart';
import 'features/team/team_screen.dart';
import 'features/search/search_screen.dart';
import 'features/case/case_screen.dart';
import 'features/notifications/bell.dart';
import 'features/person/person_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();
  runApp(const ProviderScope(child: TaskPlusApp()));
}

/// The sign-in page; the browser demo swaps in a pick-a-person list.
Widget Function() loginPage = () => const LoginScreen();

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
      GoRoute(path: '/new', builder: (_, _) => const SearchScreen()),
      GoRoute(path: '/person/:key', builder: (_, s) => PersonScreen(partyKey: Uri.decodeComponent(s.pathParameters['key']!), party: s.extra as Party?)),
      GoRoute(path: '/case/:id', builder: (_, s) => CaseScreen(taskId: s.pathParameters['id']!)),
      GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
      GoRoute(path: '/team', builder: (_, _) => const TeamScreen()),
      GoRoute(path: '/settings/notifications', builder: (_, _) => const NotificationSettingsScreen()),
      GoRoute(path: '/settings/holidays', builder: (_, _) => const HolidaysScreen()),
      GoRoute(path: '/settings/suggestions', builder: (_, _) => const SuggestionsScreen()),
      GoRoute(path: '/chat/:id', builder: (_, s) => ChatScreen(threadId: s.pathParameters['id']!, thread: s.extra as ThreadSummary?)),
      GoRoute(path: '/tasks/:filter', builder: (_, s) => FilterResultsScreen(filter: TaskFilter.values.firstWhere((f) => f.api == s.pathParameters['filter'], orElse: () => TaskFilter.myPending))),
      GoRoute(path: '/login', builder: (_, _) => loginPage()),
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
    final look = ref.watch(appearanceProvider);
    return MaterialApp.router(
        title: 'Task Plus',
        theme: AppTheme.light(look),
        darkTheme: AppTheme.dark(look),
        themeMode: look.mode,
        routerConfig: ref.watch(routerProvider),
        debugShowCheckedModeBanner: false,
      );
  }
}
