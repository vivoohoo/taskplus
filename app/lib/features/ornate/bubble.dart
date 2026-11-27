import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/outbox.dart';
import '../chat/attachments.dart';
import '../chat/voice_player.dart';

/// A WhatsApp-style bubble (Ornate): mine on the right in green, theirs on the left in white with the sender's name.
class OBubble extends StatelessWidget {
  const OBubble({super.key, required this.message, required this.out, this.name, this.tail = true, this.about});
  final Message message;
  final bool out, tail;
  final String? name;
  /// "↪ ORN-…-00042": a reply on a task, shown in a person's timeline.
  final String? about;

  @override
  Widget build(BuildContext context) {
    final o = context.o;
    final m = message;
    final r = const Radius.circular(7.5);
    return Align(
      alignment: out ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        child: Container(
          key: Key('bubble-${m.clientMsgId}'),
          margin: EdgeInsets.only(top: tail ? 6 : 2),
          padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
          decoration: BoxDecoration(
            color: out ? o.outBubble : o.inBubble,
            borderRadius: BorderRadius.only(topLeft: !out && tail ? Radius.zero : r, topRight: out && tail ? Radius.zero : r, bottomLeft: r, bottomRight: r),
            boxShadow: const [BoxShadow(color: Color(0x210B141A), blurRadius: 0.5, offset: Offset(0, 1))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (!out && tail && name != null) Text(name!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: o.accentInk)),
            if (about != null) Text('↪ $about', style: TextStyle(fontSize: 12, color: o.muted)),
            if (m.kind == 'voice') VoicePlayer(audioKey: m.audioKey!, durationS: m.audioDurationS ?? 0, transcript: m.transcript),
            if (m.bodyText != null) Text(m.bodyText!, style: TextStyle(color: o.text)),
            if (m.attachments.isNotEmpty) AttachmentStrip(attachments: m.attachments),
            Align(alignment: Alignment.centerRight, child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(DateFormat.Hm().format(m.createdAt.toLocal()), style: TextStyle(fontSize: 11.5, color: o.muted)),
              if (out) Padding(padding: const EdgeInsets.only(left: 3), child: Icon(Icons.done_all, size: 16, color: o.tick, semanticLabel: 'Sent')),
            ])),
          ]),
        ),
      ),
    );
  }
}

/// Ornate's centred date chip between days.
class DateChip extends StatelessWidget {
  const DateChip(this.at, {super.key});
  final DateTime at;
  @override
  Widget build(BuildContext context) {
    final o = context.o;
    final d = at.toLocal(), n = DateTime.now();
    final today = d.year == n.year && d.month == n.month && d.day == n.day;
    return Center(child: Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: o.bg, borderRadius: BorderRadius.circular(8)),
      child: Text(today ? 'TODAY' : DateFormat('d MMMM yyyy').format(d).toUpperCase(), style: TextStyle(fontSize: 12.5, color: o.muted)),
    ));
  }
}

bool sameDay(DateTime a, DateTime b) { final x = a.toLocal(), y = b.toLocal(); return x.year == y.year && x.month == y.month && x.day == y.day; }

/// Still in the outbox: shown at once with a clock, or a retry if the server refused it.
class PendingBubble extends StatelessWidget {
  const PendingBubble({super.key, required this.row, required this.outbox});
  final OutboxRow row;
  final OutboxSender outbox;
  @override
  Widget build(BuildContext context) {
    final o = context.o;
    final failed = row.status == 'failed';
    final files = (jsonDecode(row.attachmentPaths) as List).length;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        key: Key('pending-${row.clientMsgId}'),
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        decoration: BoxDecoration(color: o.outBubble.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(7.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (row.bodyText != null) Align(alignment: Alignment.centerLeft, child: Text(row.bodyText!)),
          if (row.audioPath != null) VoicePlayer(audioKey: '', durationS: row.audioDurationS ?? 0, localPath: row.audioPath),
          if (files > 0) Text('$files file${files > 1 ? 's' : ''}'),
          if (failed) ...[
            Text(row.error ?? 'Not sent', style: TextStyle(color: o.danger)),
            Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton(onPressed: () => outbox.discard(row.clientMsgId), child: const Text('Delete')),
              TextButton(onPressed: () => outbox.retryFailed(row.clientMsgId), child: const Text('Retry')),
            ]),
          ] else
            Icon(Icons.schedule, size: 14, color: o.muted, semanticLabel: 'Sending'),
        ]),
      ),
    );
  }
}
