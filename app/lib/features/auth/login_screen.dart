import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/auth/auth_controller.dart';

/// Phone number, then the 6-digit code.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() f) async {
    setState(() { _busy = true; _error = null; });
    try {
      await f();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submit() {
    final auth = ref.read(authProvider.notifier);
    if (!_codeSent) {
      _run(() async {
        await auth.requestOtp(_phone.text);
        setState(() => _codeSent = true);
      });
    } else {
      _run(() => auth.verifyOtp(_phone.text, _code.text));
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Task Plus', style: t.textTheme.headlineMedium?.copyWith(color: t.colorScheme.primary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 24),
                TextField(
                  key: const Key('phone'),
                  controller: _phone,
                  enabled: !_codeSent && !_busy,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  decoration: const InputDecoration(labelText: 'Mobile number', prefixText: '+91 '),
                  onSubmitted: (_) => _submit(),
                ),
                if (_codeSent) ...[
                  const SizedBox(height: 16),
                  TextField(
                    key: const Key('code'),
                    controller: _code,
                    enabled: !_busy,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: '6-digit code'),
                    onSubmitted: (_) => _submit(),
                  ),
                ],
                if (_error != null) Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(color: t.colorScheme.error)),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? 'Please wait…' : _codeSent ? 'Sign in' : 'Send code'),
                ),
                if (_codeSent) TextButton(
                  onPressed: _busy ? null : () => setState(() { _codeSent = false; _code.clear(); }),
                  child: const Text('Change number'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
