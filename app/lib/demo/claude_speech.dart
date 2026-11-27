// Browser demo on claude.ai: the page can't record audio, so speech comes from the viewer's Claude dictation
// and voice notes are read aloud with Claude's text-to-speech (runtime capabilities `dictation` and `tts`).
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../features/composer/composer.dart';

@JS('claude')
external JSObject? get _claude;

class ClaudeSpeech implements SpeechHost {
  JSObject? _dictation, _tts;
  /// What the person-picker shows: checking, ready, or why not.
  String status = 'Checking for speech…';
  void Function()? onStatus;
  void _set(String s) { status = s; onStatus?.call(); }
  void Function(String)? _onPartial, _onFinal;
  void Function(bool)? _onListening;

  /// Asks the viewer's page host for both capabilities; null (not on claude.ai, or not offered) leaves [ready] false.
  Future<void> load() async {
    // The page host may provide `claude` a little after the app starts: keep looking for 15 s.
    var c = _claude;
    for (var i = 0; c == null && i < 50; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      c = _claude;
    }
    if (c == null) return _set('Speech works only on the claude.ai link (Chrome or Edge).');
    final host = c;
    Future<JSObject?> use(String name) async {
      try { return await host.callMethod<JSPromise<JSObject?>>('use'.toJS, name.toJS).toDart; } catch (_) { return null; }
    }
    _dictation = await use('dictation');
    _tts = await use('tts');
    final d = _dictation;
    if (d == null) return _set('Speech is not offered here. Use Chrome or Edge on a computer, signed in to claude.ai in your organization.');
    String text(JSObject e) => (e['text'] as JSString?)?.toDart ?? '';
    d.callMethod('onPartial'.toJS, ((JSObject e) => _onPartial?.call(text(e))).toJS);
    d.callMethod('onFinal'.toJS, ((JSObject e) => _onFinal?.call(text(e))).toJS);
    d.callMethod('onState'.toJS, ((JSObject e) => _onListening?.call((e['state'] as JSString?)?.toDart != 'idle')).toJS);
    _set(_tts == null ? 'Speech ready (read-aloud not offered in this browser).' : 'Speech ready: dictation and voice notes work.');
  }

  @override
  String get why => status;

  @override
  bool get ready => _dictation != null;
  @override
  bool get canSpeak => _tts != null;

  @override
  void start({required void Function(String) onPartial, required void Function(String) onFinal, required void Function(bool) onListening,
      required void Function(String) onError}) {
    _onPartial = onPartial;
    _onFinal = onFinal;
    _onListening = onListening;
    // Called straight from the viewer's tap: nothing awaited before start().
    _dictation!.callMethod<JSPromise>('start'.toJS).toDart.catchError((Object e) {
      onListening(false);
      onError(_message(e));
      return null;
    });
  }

  @override
  Future<void> stop() async {
    try { await _dictation?.callMethod<JSPromise>('stop'.toJS).toDart; } catch (_) {}
  }

  @override
  Future<void> speak(String text) async {
    await _tts!.callMethod<JSPromise>('speak'.toJS, (text.length > 2000 ? text.substring(0, 2000) : text).toJS).toDart;
  }

  @override
  void stopSpeaking() => _tts?.callMethod('stop'.toJS);

  static String _message(Object e) {
    final code = e is JSObject ? (e['code'] as JSString?)?.toDart : null;
    return switch (code) {
      'not_granted' => 'Microphone use was turned down for this page.',
      'dismissed' => 'Allow speech for this page to use the mic.',
      'unavailable' => 'Speech is not available in this browser. Use Chrome or Edge.',
      'rate_limited' => 'Too many tries. Wait a moment and try again.',
      _ => 'Could not start listening.',
    };
  }
}
