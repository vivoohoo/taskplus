// Browser demo: the whole app on sample data, no server. Build: flutter build web -t lib/demo/main_demo.dart
import 'dart:async';

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:drift/drift.dart' show LazyDatabase;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/api/api_client.dart';
import '../core/auth/auth_controller.dart';
import '../core/auth/token_store.dart';
import '../core/config.dart';
import '../core/realtime.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/outbox.dart';
import '../data/providers.dart';
import '../data/repository.dart';
import '../main.dart';
import 'demo_backend.dart';
import 'claude_speech.dart';
import 'vercel_sync.dart';
import '../features/composer/composer.dart' show speechHost;

final demoSpeech = ClaudeSpeech();
VercelSync? demoShared;
/// What /api/ai said about itself (null: no AI on this site).
String? demoAiStatus;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.apiBaseUrl = 'https://demo.local';
  AppTheme.font = 'NotoSans';
  AppTheme.fallback = const ['NotoSansDevanagari', 'NotoSansGujarati'];
  // On Vercel with a database: everyone shares the demo's data. Elsewhere it lives in this tab.
  final sync = await VercelSync.connect();
  demoShared = sync;
  demoAiStatus = await vercelAiStatus();
  // On Vercel the AI fills in each new task (api/ai.js), with or without the shared database; elsewhere the keyword reader does.
  final api = DemoApi(null, sync, vercelAi());
  loginPage = () => const DemoLogin();
  // On claude.ai: dictation and read-aloud come from the page host (asked for in the background; the app starts at once).
  speechHost = demoSpeech;
  // Not on claude.ai (e.g. on Vercel): the browser's own microphone and speech recognition take over.
  unawaited(demoSpeech.load().then((_) { if (!demoSpeech.onClaude) speechHost = null; }));
  runApp(ProviderScope(overrides: [
    tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
    apiClientProvider.overrideWith((ref) => ApiClient(baseUrl: AppConfig.apiBaseUrl, tokens: ref.watch(tokenStoreProvider),
        onSignedOut: () => ref.read(authProvider.notifier).signedOut(), adapter: api)),
    realtimeProvider.overrideWith((ref) async => null),
    outboxProvider.overrideWith((ref) => MemoryOutbox(ref.watch(repositoryProvider), onSent: (i) => ref.read(sentItemsProvider.notifier).add(i))),
  ], child: const TaskPlusApp()));
}

/// Sends straight away (the demo "server" is in the page); keeps refused messages so the chat shows Retry / Delete.
class MemoryOutbox extends OutboxSender {
  MemoryOutbox(Repository repo, {super.onSent}) : super(OutboxDb(LazyDatabase(() => throw UnsupportedError('no database in the demo'))), repo);
  final _failed = <OutboxRow>[];
  final _drafts = <String, Draft>{};
  final _changes = StreamController<void>.broadcast();

  @override
  Future<void> add(Draft d) async {
    _drafts[d.clientMsgId] = d;
    try {
      onSent?.call(await repo.send(d, audioKey: d.audioPath, attachmentKeys: const []));
      _drafts.remove(d.clientMsgId);
    } on ApiException catch (e) {
      _failed.add(OutboxRow(clientMsgId: d.clientMsgId, threadId: d.threadId, kind: d.kind, bodyText: d.bodyText, attachmentPaths: '[]', overrides: '{}',
          attachmentKeys: '[]', status: 'failed', error: e.message, attempts: 1, createdAt: DateTime.now()));
      _changes.add(null);
    }
  }

  @override
  Stream<List<OutboxRow>> watch(String threadId) async* {
    List<OutboxRow> mine() => _failed.where((r) => r.threadId == threadId).toList();
    yield mine();
    await for (final _ in _changes.stream) { yield mine(); }
  }

  @override
  Future<void> retryFailed(String clientMsgId) async {
    final d = _drafts[clientMsgId];
    await discard(clientMsgId);
    if (d != null) await add(d);
  }

  @override
  Future<void> discard(String clientMsgId) async { _failed.removeWhere((r) => r.clientMsgId == clientMsgId); _changes.add(null); }

  @override
  Future<void> flush() async {}
}

/// Pick who to be. Sign out (You page) to switch person.
class DemoLogin extends ConsumerWidget {
  const DemoLogin({super.key});
  static const _people = [
    ('9800000002', 'Riya Shah', 'Support team · sends most tasks'),
    ('9800000005', 'Dhaval Dalsania', 'ProfitNX lead · reports to Tushar'),
    ('9800000006', 'Vishwas', 'PowerBI lead · reports to Dhaval'),
    ('9800000007', 'Nisha Patel', 'PowerBI team'),
    ('9800000011', 'Kunal Mehta', 'ProfitNX team'),
    ('9800000012', 'Amit Vora', 'Ornate team'),
    ('9800000004', 'Tushar Parmar', 'Development head'),
    ('9800000009', 'Priya Nair', 'Sales team'),
    ('9800000001', 'Support Lead', 'Support head'),
    ('9800000014', 'HR Lead', 'HR head'),
  ];

  static bool _auto = false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ?as=9800000005 opens the demo signed in as that person (for screenshots and shared links).
    final as = Uri.base.queryParameters['as'];
    if (as != null && !_auto) {
      _auto = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(authProvider.notifier).signIn(as, 'demo'));
    }
    final t = Theme.of(context);
    return Scaffold(
      body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: ListView(padding: const EdgeInsets.all(16), children: [
        const SizedBox(height: 16),
        Text('Task Plus', style: t.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Demo with sample data. Choose who to be; sign out on the You page to switch.', style: t.textTheme.bodyMedium),
        const SizedBox(height: 6),
        const _SpeechStatus(),
        const SizedBox(height: 4),
        Row(children: [
          Icon(demoShared != null ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, size: 16, color: t.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(child: Text(demoShared != null ? 'Shared data: everyone using this link sees the same tasks.' : 'Data stays in this tab (no shared database here).',
              style: t.textTheme.bodySmall)),
          if (demoShared != null) TextButton(
            onPressed: () async {
              final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
                title: const Text('Start over with the sample data?'),
                content: const Text('Everyone using this link loses the tasks added so far.'),
                actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Back')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Start over'))],
              ));
              if (ok == true) { await demoShared!.reset(); reloadPage(); }
            },
            child: const Text('Start over'),
          ),
        ]),
        Row(children: [
          Icon(Icons.auto_awesome_outlined, size: 16, color: t.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(child: Text(demoAiStatus ?? 'AI: off on this site (simple keyword reader instead).', style: t.textTheme.bodySmall)),
        ]),
        const SizedBox(height: 16),
        for (final (phone, name, role) in _people)
          Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
            leading: CircleAvatar(child: Text(name[0])),
            title: Text(name),
            subtitle: Text(role),
            onTap: () => ref.read(authProvider.notifier).signIn(phone, 'demo'),
          )),
      ])))),
    );
  }
}

/// Shows whether dictation and voice notes can work in this browser.
class _SpeechStatus extends StatefulWidget {
  const _SpeechStatus();
  @override
  State<_SpeechStatus> createState() => _SpeechStatusState();
}

class _SpeechStatusState extends State<_SpeechStatus> {
  @override
  void initState() {
    super.initState();
    demoSpeech.onStatus = () { if (mounted) setState(() {}); };
  }

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(demoSpeech.ready || demoSpeech.status.startsWith('Using') ? Icons.mic : Icons.mic_off, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(child: Text(demoSpeech.status, key: const Key('speech-status'), style: Theme.of(context).textTheme.bodySmall)),
      ]);
}

JSObject get globalThisLocation => (globalContext['location'] as JSObject);

/// Reloads the browser tab (used after "Start over").
void reloadPage() => globalThisLocation.callMethod('reload'.toJS);
