import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/realtime.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../cases/case_list.dart';
import '../notifications/bell.dart';
import '../ornate/widgets.dart';
import '../profile/profile_screen.dart';

/// Ornate Samanvay's home: My Tasks, Queue and All Cases, and You, on a floating bar at the bottom.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

const _tabs = [('my', 'My Tasks', Icons.chat_outlined), ('queue', 'Queue', Icons.inbox_outlined), ('all', 'All Cases', Icons.layers_outlined)];

class _HomeScreenState extends ConsumerState<HomeScreen> {
  StreamSubscription? _events, _reconnect;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Any live change refreshes the lists, the tab badges and the bell.
    ref.listenManual(realtimeProvider, (_, next) {
      _events?.cancel();
      _reconnect?.cancel();
      final rt = next.value;
      if (rt == null) return;
      _events = rt.events.listen((_) { ref.invalidate(casesProvider); ref.invalidate(caseCountsProvider); ref.invalidate(notificationsProvider); });
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
    final o = context.o;
    ref.watch(outboxProvider); // starts the sender
    final counts = ref.watch(caseCountsProvider).value;
    final user = ref.watch(authProvider).value;
    final you = _index == 3;
    return Scaffold(
      appBar: you ? AppBar(title: const Text('You')) : AppBar(
        title: Text('Task Plus', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: o.brand)),
        actions: [
          const BellButton(),
          PopupMenuButton<String>(
            key: const Key('menu'),
            tooltip: 'Menu',
            onSelected: (v) { if (v == 'out') ref.read(authProvider.notifier).signOut(); },
            itemBuilder: (_) => [
              PopupMenuItem(enabled: false, child: Text(user?.name ?? '', style: TextStyle(fontWeight: FontWeight.w600, color: o.text))),
              const PopupMenuItem(value: 'out', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: Stack(children: [
        Positioned.fill(child: IndexedStack(index: _index, children: [
          for (final (key, _, _) in _tabs) CaseListView(tab: key),
          const ProfileBody(),
        ])),
        Positioned(
          left: 12, right: 12, bottom: 12 + MediaQuery.paddingOf(context).bottom,
          child: _NavBar(
            index: _index,
            counts: counts == null ? null : [counts.my, counts.queue, counts.all],
            onTap: (i) => setState(() => _index = i),
            youName: user?.name ?? '?',
          ),
        ),
      ]),
      floatingActionButton: you ? null : Padding(
        padding: const EdgeInsets.only(bottom: 84),
        child: FloatingActionButton(key: const Key('new'), tooltip: 'New task', onPressed: () => context.push('/new'), child: const Icon(Icons.add, size: 26)),
      ),
    );
  }
}

/// Ornate's floating glass tab bar, with a sliding bubble under the current tab.
class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.counts, required this.onTap, required this.youName});
  final int index;
  final List<int>? counts;
  final void Function(int) onTap;
  final String youName;

  @override
  Widget build(BuildContext context) {
    final o = context.o;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 70,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: o.glass, borderRadius: BorderRadius.circular(999), border: Border.all(color: o.text.withValues(alpha: 0.08))),
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth / 4;
            return Stack(children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 420), curve: Curves.easeOutBack,
                left: w * index, top: 0, bottom: 0, width: w,
                child: Container(decoration: BoxDecoration(color: o.text.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(999))),
              ),
              Row(children: [
                for (var i = 0; i < 4; i++)
                  Expanded(
                    child: Semantics(
                      selected: i == index, button: true,
                      label: i < 3 ? '${_tabs[i].$2}, ${counts?[i] ?? 0}' : 'You, $youName',
                      child: InkWell(
                        key: Key('tab-${i < 3 ? _tabs[i].$1 : 'you'}'),
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => onTap(i),
                        child: ExcludeSemantics(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Stack(clipBehavior: Clip.none, children: [
                            i < 3 ? Icon(_tabs[i].$3, size: 24, color: o.text) : OAvatar(youName, size: 28),
                            if (i < 3 && (counts?[i] ?? 0) > 0)
                              Positioned(left: 16, top: -6, child: _Badge('${counts![i]}')),
                          ]),
                          const SizedBox(height: 2),
                          Text(i < 3 ? _tabs[i].$2 : 'You', style: TextStyle(fontSize: 12, color: o.text, fontWeight: i == index ? FontWeight.w800 : FontWeight.w600)),
                        ])),
                      ),
                    ),
                  ),
              ]),
            ]);
          }),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 20),
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: context.o.badge, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: TextStyle(color: context.o.badgeText, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}
