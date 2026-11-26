import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/providers.dart';

String mmss(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

/// Play button + length; "Show transcript" expands the text. The audio URL is fetched (and signed) only on play.
class VoicePlayer extends ConsumerStatefulWidget {
  const VoicePlayer({super.key, required this.audioKey, required this.durationS, this.transcript, this.localPath});
  final String audioKey;
  final int durationS;
  final String? transcript;
  /// Still in the outbox: play from the phone.
  final String? localPath;
  @override
  ConsumerState<VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends ConsumerState<VoicePlayer> {
  AudioPlayer? _player;
  bool _showText = false;
  bool _playing = false;

  Future<void> _toggle() async {
    if (_playing) { await _player?.pause(); return; }
    try {
      if (_player == null) {
        final p = _player = AudioPlayer();
        p.playerStateStream.listen((s) {
          if (s.processingState == ProcessingState.completed) { p.seek(Duration.zero); p.pause(); }
          if (mounted) setState(() => _playing = s.playing && s.processingState != ProcessingState.completed);
        });
        if (widget.localPath != null) {
          await p.setFilePath(widget.localPath!);
        } else {
          await p.setUrl(await ref.read(repositoryProvider).fileUrl(widget.audioKey));
        }
      }
      await _player!.play();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not play: $e')));
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: Icon(_playing ? Icons.pause : Icons.play_arrow), tooltip: _playing ? 'Pause' : 'Play voice note', onPressed: _toggle),
          Text(mmss(widget.durationS)),
          if (widget.transcript != null) TextButton(onPressed: () => setState(() => _showText = !_showText), child: Text(_showText ? 'Hide transcript' : 'Show transcript')),
        ]),
        if (_showText && widget.transcript != null) Text(widget.transcript!, style: Theme.of(context).textTheme.bodySmall),
      ]);
}
