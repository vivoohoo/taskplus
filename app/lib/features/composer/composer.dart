import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:uuid/uuid.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../chat/voice_player.dart';
import '../slash/slash.dart';

const maxVoiceSeconds = 180;
const dictationLocales = {'en_IN': 'English', 'hi_IN': 'हिंदी', 'gu_IN': 'ગુજરાતી'};

/// Bottom-pinned input: text with / commands and @mentions, dictation, hold-to-record voice notes, attachments.
class Composer extends ConsumerStatefulWidget {
  const Composer({super.key, required this.threadId, this.departmentId, required this.onSend, this.replyTo, this.onCancelReply});
  final String threadId;
  /// Answering a question on this task: the message is a reply, not a new task.
  final Task? replyTo;
  final VoidCallback? onCancelReply;
  /// Set in department chats: enables @mention and /module.
  final String? departmentId;
  final void Function(Draft) onSend;
  @override
  ConsumerState<Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<Composer> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _overrides = <String, String>{};
  Member? _tagged;
  final _files = <String>[];
  ActiveToken? _slash, _mention;

  // Voice note
  final _recorder = AudioRecorder();
  bool _recording = false, _cancelling = false;
  int _seconds = 0;
  Timer? _tick;
  DateTime? _startedAt;

  // Dictation
  final _speech = SpeechToText();
  bool _listening = false;
  String _locale = 'en_IN';

  @override
  void initState() {
    super.initState();
    _text.addListener(_onTextChanged);
    SharedPreferences.getInstance().then((p) { final l = p.getString('dictation_locale'); if (l != null && mounted) setState(() => _locale = l); });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    _tick?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final cursor = _text.selection.baseOffset;
    setState(() {
      _slash = ActiveToken.at(_text.text, cursor, '/');
      _mention = widget.departmentId == null ? null : ActiveToken.at(_text.text, cursor, '@');
    });
  }

  void _removeToken(ActiveToken t) {
    final s = t.removeFrom(_text.text);
    _text.value = TextEditingValue(text: s, selection: TextSelection.collapsed(offset: t.start.clamp(0, s.length)));
  }

  Future<void> _pickCommand(SlashCommand c) async {
    final token = _slash!;
    String? value;
    if (c.name == 'customer') {
      List<String> list = const [];
      try { list = await ref.read(repositoryProvider).customers(); } catch (_) {}
      if (!mounted) return;
      value = await showModalBottomSheet<String>(context: context, builder: (_) => SafeArea(child: ListView(shrinkWrap: true, children: [
        ListTile(title: Text(c.label)),
        for (final v in list) ListTile(title: Text(v), onTap: () => Navigator.pop(context, v)),
        ListTile(leading: const Icon(Icons.edit), title: const Text('Someone else (type a name or number)'), onTap: () => Navigator.pop(context, '\u0000')),
      ])));
      if (value == '\u0000' && mounted) value = await _askText(c.label);
    } else if (c.freeText) {
      value = await _askText(c.label);
    } else {
      var choices = c.choices ?? const ['Other'];
      if (c.name == 'module' && widget.departmentId != null) {
        try { choices = (await ref.read(departmentProvider(widget.departmentId!).future)).modules; } catch (_) {}
      }
      if (!mounted) return;
      value = await showModalBottomSheet<String>(context: context, builder: (_) => SafeArea(child: ListView(shrinkWrap: true, children: [
        ListTile(title: Text(c.label)),
        for (final v in choices) ListTile(title: Text(v), onTap: () => Navigator.pop(context, v)),
      ])));
    }
    _removeToken(token);
    if (value != null && value.trim().isNotEmpty) setState(() => _overrides[c.name] = value!.trim());
    _focus.requestFocus();
  }

  Future<String?> _askText(String label) {
    final c = TextEditingController();
    return showDialog<String>(context: context, builder: (_) => AlertDialog(
      title: Text(label),
      content: TextField(controller: c, autofocus: true, onSubmitted: (v) => Navigator.pop(context, v)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Add')),
      ],
    ));
  }

  void _send({String? audioPath, int? audioSeconds}) {
    final body = _text.text.trim();
    final kind = audioPath != null ? 'voice' : body.isEmpty ? 'attachment' : 'text';
    if (kind == 'attachment' && _files.isEmpty) return;
    widget.onSend(Draft(
      clientMsgId: const Uuid().v4(), threadId: widget.threadId, kind: kind,
      bodyText: body.isEmpty ? null : body, audioPath: audioPath, audioDurationS: audioSeconds,
      attachmentPaths: List.of(_files), overrides: Map.of(_overrides), taggedUserId: _tagged?.id, replyToTaskId: widget.replyTo?.id,
    ));
    widget.onCancelReply?.call();
    setState(() { _text.clear(); _files.clear(); _overrides.clear(); _tagged = null; });
  }

  // ---- voice note: hold to record, slide left to cancel, release to send ----
  void _phoneOnly(String what) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$what need the phone app.')));

  Future<void> _startRecording() async {
    if (kIsWeb) return _phoneOnly('Voice notes');
    if (!await _recorder.hasPermission()) return;
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/${const Uuid().v4()}.ogg';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.opus, bitRate: 16000, numChannels: 1, sampleRate: 16000), path: path);
    _startedAt = DateTime.now();
    setState(() { _recording = true; _cancelling = false; _seconds = 0; });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _seconds = DateTime.now().difference(_startedAt!).inSeconds);
      if (_seconds >= maxVoiceSeconds) _stopRecording(send: true);
    });
  }

  Future<void> _stopRecording({required bool send}) async {
    if (!_recording) return;
    _tick?.cancel();
    final path = await _recorder.stop();
    final secs = DateTime.now().difference(_startedAt!).inSeconds.clamp(1, maxVoiceSeconds);
    setState(() => _recording = false);
    if (path == null) return;
    if (send && secs >= 1) {
      _send(audioPath: path, audioSeconds: secs);
    } else {
      File(path).delete().ignore();
    }
  }

  // ---- dictation ----
  Future<void> _toggleDictation() async {
    if (_listening) { await _speech.stop(); setState(() => _listening = false); return; }
    if (!await _speech.initialize(onStatus: (s) { if (s == 'done' || s == 'notListening') setState(() => _listening = false); })) return;
    final base = _text.text;
    setState(() => _listening = true);
    await _speech.listen(listenOptions: SpeechListenOptions(localeId: _locale), onResult: (r) {
      final t = r.recognizedWords;
      _text.value = TextEditingValue(text: base.isEmpty ? t : '$base $t', selection: TextSelection.collapsed(offset: (base.isEmpty ? t : '$base $t').length));
    });
  }

  Future<void> _chooseLocale() async {
    final l = await showModalBottomSheet<String>(context: context, builder: (_) => SafeArea(child: ListView(shrinkWrap: true, children: [
      const ListTile(title: Text('Dictation language')),
      for (final e in dictationLocales.entries) ListTile(title: Text(e.value), trailing: e.key == _locale ? const Icon(Icons.check) : null, onTap: () => Navigator.pop(context, e.key)),
    ])));
    if (l == null) return;
    setState(() => _locale = l);
    (await SharedPreferences.getInstance()).setString('dictation_locale', l);
  }

  // ---- attachments ----
  Future<void> _attach() async {
    if (kIsWeb) return _phoneOnly('Attachments');
    final how = await showModalBottomSheet<String>(context: context, builder: (_) => SafeArea(child: Wrap(children: [
      ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Camera'), onTap: () => Navigator.pop(context, 'camera')),
      ListTile(leading: const Icon(Icons.photo), title: const Text('Gallery'), onTap: () => Navigator.pop(context, 'gallery')),
      ListTile(leading: const Icon(Icons.attach_file), title: const Text('PDF file'), onTap: () => Navigator.pop(context, 'file')),
    ])));
    if (how == null) return;
    final picked = <String>[];
    if (how == 'file') {
      final r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
      picked.addAll(r.map((f) => f.path).whereType<String>());
    } else {
      final img = await ImagePicker().pickImage(source: how == 'camera' ? ImageSource.camera : ImageSource.gallery);
      if (img != null) picked.add(await _compress(img.path));
    }
    setState(() => _files.addAll(picked.take(10 - _files.length)));
  }

  /// Max 1600 px, JPEG quality 70 (spec §3).
  Future<String> _compress(String path) async {
    final out = '${(await getTemporaryDirectory()).path}/${const Uuid().v4()}.jpg';
    final r = await FlutterImageCompress.compressAndGetFile(path, out, minWidth: 1600, minHeight: 1600, quality: 70, format: CompressFormat.jpeg);
    return r?.path ?? path;
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final hasText = _text.text.trim().isNotEmpty;
    final commands = _slash == null ? const <SlashCommand>[] : matchingCommands(_slash!.query)
        .where((x) => x.name != 'module' || widget.departmentId != null).toList();
    final members = _mention == null ? const <Member>[] : (ref.watch(departmentProvider(widget.departmentId!)).value?.members ?? const <Member>[])
        .where((m) => m.name.toLowerCase().contains(_mention!.query)).toList();

    return Material(
      color: c.surface,
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (commands.isNotEmpty)
            _Menu(key: const Key('slash-menu'), children: [
              for (final cmd in commands) ListTile(dense: true, leading: Text('/${cmd.name}', style: TextStyle(color: c.primary)), title: Text(cmd.label), onTap: () => _pickCommand(cmd)),
            ]),
          if (members.isNotEmpty)
            _Menu(key: const Key('mention-menu'), children: [
              for (final m in members) ListTile(dense: true, title: Text(m.name), onTap: () { _removeToken(_mention!); setState(() => _tagged = m); }),
            ]),
          if (widget.replyTo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: Align(alignment: Alignment.centerLeft, child: InputChip(
                key: const Key('replying'),
                avatar: const Icon(Icons.reply, size: 18),
                label: Text('Answering: ${widget.replyTo!.subject ?? 'task'}', overflow: TextOverflow.ellipsis),
                onDeleted: widget.onCancelReply,
              )),
            ),
          if (_overrides.isNotEmpty || _tagged != null || _files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                for (final e in _overrides.entries) InputChip(label: Text(overrideLabel(e.key, e.value)), onDeleted: () => setState(() => _overrides.remove(e.key))),
                if (_tagged != null) InputChip(label: Text('@${_tagged!.name}'), onDeleted: () => setState(() => _tagged = null)),
                for (final f in _files) InputChip(
                  avatar: f.endsWith('.pdf') ? const Icon(Icons.picture_as_pdf, size: 18) : CircleAvatar(backgroundImage: FileImage(File(f))),
                  label: Text(f.split(RegExp(r'[\\/]')).last, overflow: TextOverflow.ellipsis),
                  onDeleted: () => setState(() => _files.remove(f))),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: _recording
                    ? _RecordingBar(seconds: _seconds, cancelling: _cancelling)
                    : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    IconButton(tooltip: 'Attach', icon: const Icon(Icons.attach_file), onPressed: _attach),
                    Expanded(
                      child: TextField(
                        key: const Key('composer'),
                        controller: _text,
                        focusNode: _focus,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: 4000,
                        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: widget.departmentId != null ? 'Message, / for tags, @ to tag someone' : 'Message, / for tags',
                          isDense: true, filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                          suffixIcon: GestureDetector(
                            onLongPress: _chooseLocale,
                            child: IconButton(tooltip: 'Dictate (hold to change language)', icon: Icon(_listening ? Icons.hearing : Icons.keyboard_voice_outlined, color: _listening ? c.primary : null), onPressed: _toggleDictation),
                          ),
                        ),
                      ),
                    ),
                  ]),
              ),
              const SizedBox(width: 4),
              // Stays mounted while recording, so the hold gesture isn't lost.
              hasText || _files.isNotEmpty
                  ? IconButton.filled(key: const Key('send'), tooltip: 'Send', icon: const Icon(Icons.send), onPressed: _send)
                  : GestureDetector(
                      key: const Key('record'),
                      onLongPressStart: (_) => _startRecording(),
                      onLongPressMoveUpdate: (d) { final cancel = d.offsetFromOrigin.dx < -80; if (cancel != _cancelling) setState(() => _cancelling = cancel); },
                      onLongPressEnd: (_) => _stopRecording(send: !_cancelling),
                      child: Tooltip(
                        message: 'Hold to record a voice note',
                        child: CircleAvatar(radius: 24, backgroundColor: _recording ? c.error : c.primary,
                            child: Icon(Icons.mic, color: _recording ? c.onError : c.onPrimary)),
                      ),
                    ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: Material(elevation: 2, child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: children)),
      );
}

class _RecordingBar extends StatelessWidget {
  const _RecordingBar({required this.seconds, required this.cancelling});
  final int seconds;
  final bool cancelling;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: Row(children: [
          const SizedBox(width: 12),
          Icon(Icons.fiber_manual_record, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 8),
          Text('${mmss(seconds)} / ${mmss(maxVoiceSeconds)}'),
          const Spacer(),
          Text(cancelling ? 'Release to cancel' : '◀ Slide to cancel', style: TextStyle(color: cancelling ? Theme.of(context).colorScheme.error : null)),
        ]),
      );
}
