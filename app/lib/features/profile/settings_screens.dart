import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/providers.dart';

/// Ornate's You-page settings: alert kinds, public holidays (heads), suggest an improvement.

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotifState();
}

class _NotifState extends ConsumerState<NotificationSettingsScreen> {
  List<Map<String, dynamic>> _kinds = [];
  Set<String> _muted = {};
  @override
  void initState() {
    super.initState();
    ref.read(repositoryProvider).notificationSettings().then((d) {
      if (mounted) setState(() { _kinds = (d['kinds'] as List).cast<Map<String, dynamic>>(); _muted = {...(d['muted'] as List).cast<String>()}; });
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: ListView(children: [
          for (final k in _kinds)
            SwitchListTile(
              title: Text(k['label'] as String),
              subtitle: k['required'] == true ? const Text('Always on') : null,
              value: !_muted.contains(k['id']),
              onChanged: k['required'] == true ? null : (on) async {
                setState(() => on ? _muted.remove(k['id']) : _muted.add(k['id'] as String));
                await ref.read(repositoryProvider).setMuted(_muted.toList());
              },
            ),
        ]),
      );
}

class HolidaysScreen extends ConsumerStatefulWidget {
  const HolidaysScreen({super.key});
  @override
  ConsumerState<HolidaysScreen> createState() => _HolidaysState();
}

class _HolidaysState extends ConsumerState<HolidaysScreen> {
  List<Map<String, dynamic>> _days = [];
  Future<void> _load() async { final d = await ref.read(repositoryProvider).holidays(); if (mounted) setState(() => _days = d); }
  @override
  void initState() { super.initState(); _load(); }

  Future<void> _add() async {
    final day = await showDatePicker(context: context, firstDate: DateTime(2026), lastDate: DateTime(2030), initialDate: DateTime.now());
    if (day == null || !mounted) return;
    final name = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Holiday name'),
      content: TextField(controller: name, autofocus: true),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Back')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add'))],
    ));
    if (ok != true) return;
    final iso = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    try { await ref.read(repositoryProvider).addHoliday(iso, name.text); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Public holidays')),
        floatingActionButton: FloatingActionButton(onPressed: _add, tooltip: 'Add a holiday', child: const Icon(Icons.add)),
        body: ListView(children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('The task clock skips these days, like Sundays.')),
          for (final h in _days)
            ListTile(
              title: Text(h['name'] as String? ?? 'Holiday'),
              subtitle: Text(h['day'] as String),
              trailing: IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Remove',
                  onPressed: () async { await ref.read(repositoryProvider).removeHoliday(h['day'] as String); await _load(); }),
            ),
        ]),
      );
}

class SuggestionsScreen extends ConsumerStatefulWidget {
  const SuggestionsScreen({super.key});
  @override
  ConsumerState<SuggestionsScreen> createState() => _SuggestionsState();
}

class _SuggestionsState extends ConsumerState<SuggestionsScreen> {
  Map<String, dynamic>? _data;
  final _text = TextEditingController();
  Future<void> _load() async { final d = await ref.read(repositoryProvider).suggestions(); if (mounted) setState(() => _data = d); }
  @override
  void initState() { super.initState(); _load(); }

  @override
  Widget build(BuildContext context) {
    final list = ((_data?['suggestions'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final review = _data?['canReview'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Suggest an improvement')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _text, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'Your idea for this app')),
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: () async {
          if (_text.text.trim().length < 5) return;
          await ref.read(repositoryProvider).suggest(_text.text.trim());
          _text.clear();
          await _load();
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sent')));
        }, child: const Text('Send'))),
        const Divider(height: 32),
        for (final s in list)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s['text'] as String),
            subtitle: Text(review ? '${s['byName']}' : 'Your idea'),
            trailing: review
                ? DropdownButton<String>(
                    value: s['status'] as String,
                    items: [for (final x in const ['New', 'Seen', 'Planned', 'Done', 'Not planned']) DropdownMenuItem(value: x, child: Text(x))],
                    onChanged: (v) async { if (v != null) { await ref.read(repositoryProvider).setSuggestionStatus(s['id'] as String, v); await _load(); } },
                  )
                : Chip(label: Text(s['status'] as String)),
          ),
      ]),
    );
  }
}
