import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../data/providers.dart';

/// Search as you type (300 ms pause). Tapping a result opens the chat straight away: no "+" step, no form.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  Timer? _debounce;
  List<SearchResult> _results = const [];
  String? _error;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _run(''); // empty search: recent chats first
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(q.trim()));
  }

  Future<void> _run(String q) async {
    try {
      final r = await ref.read(repositoryProvider).search(q);
      if (mounted) setState(() { _results = r; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _open(SearchResult r) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final t = await ref.read(repositoryProvider).openThread(r.type, r.id);
      if (mounted) context.pushReplacement('/chat/${t.id}', extra: t);
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _opening = false; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: TextField(
            key: const Key('search-input'),
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Search people or departments', border: InputBorder.none),
            onChanged: _onChanged,
          ),
        ),
        body: Column(children: [
          if (_opening) const LinearProgressIndicator(),
          if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (_, i) {
                final r = _results[i];
                return ListTile(
                  leading: CircleAvatar(child: r.type == 'department' ? const Icon(Icons.groups) : Text(r.name[0])),
                  title: Text(r.name),
                  subtitle: r.subtitle == null ? null : Text(r.subtitle!),
                  onTap: () => _open(r),
                );
              },
            ),
          ),
        ]),
      );
}
