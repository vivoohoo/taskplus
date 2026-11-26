import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/config.dart';

/// Phone and password. "Server address" holds the trial's tunnel address, which changes when the server restarts.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _server = TextEditingController();
  bool _busy = false, _hide = true, _showServer = false;
  String? _error, _serverNote;

  @override
  void initState() {
    super.initState();
    _server.text = ref.read(serverUrlProvider);
  }

  Future<void> _signIn() async {
    setState(() { _busy = true; _error = null; });
    try {
      if (_showServer && AppConfig.normalise(_server.text) != ref.read(serverUrlProvider)) await ref.read(serverUrlProvider.notifier).set(_server.text);
      await ref.read(authProvider.notifier).signIn(_phone.text, _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Saves the address and checks the server answers.
  Future<void> _checkServer() async {
    setState(() { _serverNote = 'Checking…'; });
    final url = AppConfig.normalise(_server.text);
    await ref.read(serverUrlProvider.notifier).set(url);
    _server.text = url;
    try {
      await Dio(BaseOptions(connectTimeout: const Duration(seconds: 6), receiveTimeout: const Duration(seconds: 6))).get('$url/healthz');
      if (mounted) setState(() => _serverNote = 'Connected.');
    } catch (_) {
      if (mounted) setState(() => _serverNote = 'Can\'t reach this address. Check it with whoever runs the server.');
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _server.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: AutofillGroup(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Task Plus', style: t.textTheme.headlineMedium?.copyWith(color: t.colorScheme.primary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 24),
                  TextField(
                    key: const Key('phone'),
                    controller: _phone,
                    enabled: !_busy,
                    keyboardType: TextInputType.phone,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    decoration: const InputDecoration(labelText: 'Mobile number', prefixText: '+91 '),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('password'),
                    controller: _password,
                    enabled: !_busy,
                    obscureText: _hide,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(icon: Icon(_hide ? Icons.visibility : Icons.visibility_off), tooltip: _hide ? 'Show password' : 'Hide password',
                          onPressed: () => setState(() => _hide = !_hide)),
                    ),
                    onSubmitted: (_) => _signIn(),
                  ),
                  if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: t.colorScheme.error))),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _busy ? null : _signIn, child: Text(_busy ? 'Please wait…' : 'Sign in')),
                  const SizedBox(height: 4),
                  Text('Forgot your password? Ask your department head to reset it.', style: t.textTheme.bodySmall, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    key: const Key('server-toggle'),
                    onPressed: () => setState(() => _showServer = !_showServer),
                    icon: Icon(_showServer ? Icons.expand_less : Icons.dns_outlined),
                    label: const Text('Server address'),
                  ),
                  if (_showServer) ...[
                    TextField(
                      key: const Key('server'),
                      controller: _server,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(labelText: 'Server address', hintText: 'https://….trycloudflare.com'),
                      onSubmitted: (_) => _checkServer(),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      OutlinedButton(onPressed: _checkServer, child: const Text('Save and check')),
                      const SizedBox(width: 12),
                      if (_serverNote != null) Expanded(child: Text(_serverNote!, style: t.textTheme.bodySmall)),
                    ]),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
