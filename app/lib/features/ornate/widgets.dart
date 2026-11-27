// Small pieces of Ornate Samanvay's look shared by the lists, chats and case page.
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';
import '../../data/models.dart';

/// Ornate's status names.
String statusLabel(String s) => switch (s) {
      'Open' => 'Pending Acceptance',
      'InProgress' => 'In Progress',
      'WaitingInfo' => 'Waiting for Information',
      'WaitingDept' => 'Waiting for Another Dept',
      _ => s,
    };

/// Status pill colours (Ornate's .s-* classes): green working/done, orange waiting, red stopped.
(Color, Color) statusColors(BuildContext context, String s) {
  final o = context.o;
  return switch (s) {
    'InProgress' || 'Accepted' || 'Completed' || 'Verified' => (o.greenBg, o.green),
    'Open' || 'WaitingInfo' || 'WaitingDept' => (o.orangeBg, o.orange),
    'Blocked' || 'Rejected' || 'Cancelled' => (o.redBg, o.red),
    _ => (o.neutralBg, o.neutral),
  };
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.bg, this.fg});
  final String text;
  final Color? bg, fg;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(color: bg ?? context.o.neutralBg, borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg ?? context.o.neutral)),
      );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = statusColors(context, status);
    return Pill(statusLabel(status), bg: bg, fg: fg);
  }
}

/// Coloured initials, as in Ornate; a lock for private notes.
class OAvatar extends StatelessWidget {
  const OAvatar(this.name, {super.key, this.size = 48, this.lock = false, this.icon});
  final String name;
  final double size;
  final bool lock;
  final IconData? icon;
  static const _colors = [Color(0xFF00695C), Color(0xFF1565C0), Color(0xFF6A1B9A), Color(0xFFAD1457), Color(0xFFC62828), Color(0xFF4E342E), Color(0xFF37474F), Color(0xFF2E7D32)];

  @override
  Widget build(BuildContext context) {
    final initials = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty && RegExp(r'^[A-Za-z]').hasMatch(w)).take(2).map((w) => w[0].toUpperCase()).join();
    final color = lock ? const Color(0xFF54656F) : _colors[name.runes.fold(0, (h, c) => h + c) % _colors.length];
    return ExcludeSemantics(
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: lock ? Icon(Icons.lock, color: Colors.white, size: size * 0.42)
            : icon != null ? Icon(icon, color: Colors.white, size: size * 0.5)
            : Text(initials.isEmpty ? '?' : initials, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: size * 0.36)),
      ),
    );
  }
}

/// Ornate's chip: grey, or green and bold when on. 44 px touch target.
class OChip extends StatelessWidget {
  const OChip(this.label, {super.key, required this.on, required this.onTap, this.small = false});
  final String label;
  final bool on, small;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final o = context.o;
    return Semantics(
      button: true, selected: on,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: small ? 6 : 4),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: small ? 7 : 9),
            decoration: BoxDecoration(color: on ? o.chipOn : o.chip, borderRadius: BorderRadius.circular(18)),
            child: Text(label, style: TextStyle(fontSize: small ? 13 : 14, color: on ? o.chipOnText : o.muted, fontWeight: on ? FontWeight.w600 : FontWeight.w400)),
          ),
        ),
      ),
    );
  }
}

/// The doodle-dot chat background (Ornate's .wall).
class Wall extends StatelessWidget {
  const Wall({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final o = context.o;
    return CustomPaint(painter: _Dots(o.wall, o.wallDot), child: child);
  }
}

class _Dots extends CustomPainter {
  _Dots(this.bg, this.dot);
  final Color bg, dot;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    if (dot == bg) return;
    final p = Paint()..color = dot;
    for (var y = 0.0; y < size.height; y += 14) {
      for (var x = (y / 14).floor().isEven ? 0.0 : 14.0; x < size.width; x += 28) {
        canvas.drawCircle(Offset(x, y), 1.2, p);
      }
    }
  }

  @override
  bool shouldRepaint(_Dots old) => old.bg != bg || old.dot != dot;
}

/// 14:05 today, Yesterday, else 27/11/2026 (Ornate's list time).
String listTime(DateTime at, [DateTime? now]) {
  final d = at.toLocal(), n = (now ?? DateTime.now()).toLocal();
  bool same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  if (same(d, n)) return DateFormat.Hm().format(d);
  if (same(d, n.subtract(const Duration(days: 1)))) return 'Yesterday';
  return DateFormat('dd/MM/yyyy').format(d);
}

/// 2 h 15 m, 3 d 4 h.
String duration(Duration d) {
  final m = d.inMinutes.abs();
  if (m < 60) return '$m m';
  if (m < 24 * 60) return '${m ~/ 60} h ${m % 60} m';
  return '${m ~/ (24 * 60)} d ${(m % (24 * 60)) ~/ 60} h';
}

/// "3 open · 2 from you · 1 for you · 1 not accepted · 1 overdue" (Ornate's summary line). Open tasks only.
String summaryLine(List<CaseRow> rows, String me) {
  final fromMe = rows.where((r) => r.requesterId == me).length;
  final forMe = rows.length - fromMe;
  final waiting = rows.where((r) => r.task.status == 'Open').length;
  final over = rows.where((r) => r.overdue).length;
  return [
    '${rows.length} open', if (fromMe > 0) '$fromMe from you', if (forMe > 0) '$forMe for you',
    if (waiting > 0) '$waiting not accepted', if (over > 0) '$over overdue',
  ].join(' · ');
}

/// Same, from timeline items.
String summaryOfTasks(List<Task> open, String me, Map<String, String> senders) {
  final fromMe = open.where((t) => senders[t.id] == me).length;
  final waiting = open.where((t) => t.status == 'Open').length;
  final over = open.where((t) => t.isOverdue(DateTime.now())).length;
  return [
    '${open.length} open', if (fromMe > 0) '$fromMe from you', if (open.length - fromMe > 0) '${open.length - fromMe} for you',
    if (waiting > 0) '$waiting not accepted', if (over > 0) '$over overdue',
  ].join(' · ');
}

/// How an update reads, on the case page and as a row's last activity (Ornate's cards): title, icon, tone, note.
(String, IconData, String, String?) eventLook(String type, Map<String, dynamic> p) {
  final (title, icon, tone) = switch (type) {
    'accepted' => ('Accepted', Icons.check, 'green'), 'completed' => ('Completed', Icons.done_all, 'green'), 'verified' => ('Verified', Icons.verified, 'green'),
    'closed' => ('Closed', Icons.lock_outline, 'green'), 'reopened' => ('Reopened', Icons.replay, 'orange'), 'question' => ('Clock paused · question for requester', Icons.help_outline, 'orange'),
    'answered' => ('Answered', Icons.reply, 'green'), 'blocked' => ('Blocked · clock stopped', Icons.block, 'red'), 'unblocked' => ('Unblocked', Icons.play_arrow, 'green'),
    'escalated' => ('Escalated', Icons.trending_up, 'red'), 'attended' => ('Escalation attended', Icons.how_to_reg, 'green'),
    'reassigned' => ('Reassigned', Icons.swap_horiz, 'neutral'), 'reassign_asked' => ('Reassignment requested', Icons.swap_horiz, 'orange'),
    'reassign_refused' => ('Stays with the owner', Icons.person, 'neutral'), 'declined' => ('Declined', Icons.close, 'orange'),
    'request' => (p['kind'] == 'reject' ? 'Rejection requested' : 'Transfer requested', Icons.outbox, 'orange'), 'request_refused' => ('Request refused', Icons.close, 'neutral'),
    'rejected' => ('Rejected', Icons.cancel_outlined, 'red'), 'transferred' => ('Transferred to ${p['toName'] ?? 'another department'}', Icons.east, 'neutral'),
    'cancelled' => ('Cancelled', Icons.cancel_outlined, 'red'), 'priority_changed' => ('Priority ${p['from']} → ${p['to']}', Icons.flag_outlined, 'neutral'),
    'edited' => ('Edited', Icons.edit_outlined, 'neutral'),
    'warned' => (switch (p['kind']) { 'needs_assigning' => 'Needs assigning', 'over' => 'Overdue', '1h' => '1 working hour left', _ => '75% of the time used' }, Icons.timer_outlined, p['kind'] == 'over' ? 'red' : 'orange'),
    'handed_off' => ('Handed off · clock paused', Icons.call_split, 'orange'), 'subtask_done' => ('Sub-task finished', Icons.done, 'green'),
    'subs_cancelled' => ('Completed, open sub-tasks cancelled', Icons.done_all, 'green'), 'status_changed' => (statusLabel('${p['to']}'), Icons.play_arrow, 'green'),
    final x => (x.replaceAll('_', ' '), Icons.info_outline, 'neutral'),
  };
  final note = p['kind'] == 'needs_assigning' ? 'Still not accepted 1 working hour after escalation'
      : (p['reason'] ?? p['remarks'] ?? p['question'] ?? p['resolution'] ?? p['subject'] ?? (type == 'edited' && p['to'] is String ? p['to'] : null))?.toString();
  return (title, icon, tone, note);
}

/// A row's last line: "Riya: text" for a message, "Clock paused · reason" for an update (Ornate's preview).
String previewOf(CaseRow r) {
  final e = r.lastEvent;
  if (e == null) return r.lastMine ? r.lastText.replaceFirst('You: ', '') : r.lastText;
  final (title, _, _, note) = eventLook(e.$1, e.$2);
  return note == null ? title : '$title · $note';
}
